// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* =========================== External deps =========================== */
import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/* Router interface (local vendor alias) */
import {IUniswapV4Router04} from "./vendor/IUniswapV4Router04.sol";

/* Shared interfaces (CC0 versions) */
import {IERC721} from "./Interfaces.sol";

/**
 * @title CC0Strategy
 * @author cc0.company
 * @notice ERC20 token backed by a target ERC721 collection. Trading fees from the Uniswap v4 hook
 *         accumulate as ETH in this contract, which can be spent to buy floor NFTs and relist them
 *         with a configurable markup. ETH from sales is used for token TWAP buyback & burn.
 * @dev Deployed via ERC1967 proxy using immutable-args (factory, router, poolManager).
 */
contract CC0Strategy is Initializable, UUPSUpgradeable, Ownable, ReentrancyGuard, ERC20 {
    /*////////////////////////////////////////////////////////////////////
                                  CONSTANTS
    ////////////////////////////////////////////////////////////////////*/

    /// @notice Maximum token supply (1 billion tokens)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice Dead address for burning tokens
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Contract version for upgrades bookkeeping
    uint256 public constant VERSION = 1;

    /*////////////////////////////////////////////////////////////////////
                                STORAGE LAYOUT
    ////////////////////////////////////////////////////////////////////*/

    // ERC20 metadata
    string tokenName;
    string tokenSymbol;

    /// @notice Uniswap v4 hook address paired with this strategy’s pool
    address public hookAddress;

    /// @notice The NFT collection this strategy targets
    IERC721 public collection;

    /// @notice Multiplier for NFT resale price (basis points; 1200 = 1.2x)
    uint256 public priceMultiplier;

    /// @notice Mapping of tokenId => resale price (wei); 0 means not listed
    mapping(uint256 => uint256) public nftForSale;

    /// @notice ETH fees accumulated by the hook for buying NFTs
    uint256 public currentFees;

    /// @notice ETH accumulated from NFT sales, reserved for token TWAP buyback
    uint256 public ethToTwap;

    /// @notice Amount of ETH per TWAP step
    uint256 public twapIncrement;

    /// @notice Minimum blocks delay between TWAP steps
    uint256 public twapDelayInBlocks;

    /// @notice Last block when TWAP occurred
    uint256 public lastTwapBlock;

    /// @notice Block number when the strategy was deployed
    uint256 public deployBlock;

    /// @notice Time-based buy increment for getMaxPriceForBuy()
    uint256 public buyIncrement;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*////////////////////////////////////////////////////////////////////
                                    EVENTS
    ////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted after the protocol buys an NFT
    event NFTBoughtByProtocol(uint256 indexed tokenId, uint256 purchasePrice, uint256 listPrice);

    /// @notice Emitted after the protocol sells an NFT
    event NFTSoldByProtocol(uint256 indexed tokenId, uint256 price, address buyer);

    /// @notice Emitted when the transient allowance is increased by the hook
    event AllowanceIncreased(uint256 amount);

    /// @notice Emitted when the transient allowance is consumed
    event AllowanceSpent(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when implementation is upgraded
    event ContractUpgraded(address indexed oldImplementation, address indexed newImplementation, uint256 version);

    /*////////////////////////////////////////////////////////////////////
                                     ERRORS
    ////////////////////////////////////////////////////////////////////*/

    error NFTNotForSale();
    error NFTPriceTooLow();
    error InsufficientContractBalance();
    error InvalidMultiplier();
    error NoETHToTwap();
    error TwapDelayNotMet();
    error NotEnoughEth();
    error PriceTooHigh();
    error NotFactory();
    error AlreadyNFTOwner();
    error NeedToBuyNFT();
    error NotNFTOwner();
    error OnlyHook();
    error InvalidCollection();
    error ExternalCallFailed(bytes reason);
    error InvalidTarget();
    error InvalidTransfer();

    /*////////////////////////////////////////////////////////////////////
                                 INITIALIZATION
    ////////////////////////////////////////////////////////////////////*/

    /// @dev Disable implementation initialization
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize proxy storage.
     * @param _collection ERC721 collection address
     * @param _hook Hook address for the Uniswap v4 pool
     * @param _tokenName ERC20 name
     * @param _tokenSymbol ERC20 symbol
     * @param _buyIncrement Buy increment step (wei) for time-based max buy price
     * @param _owner Owner address (UUPS admin)
     */
    function initialize(
        address _collection,
        address _hook,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _buyIncrement,
        address _owner
    ) external initializer {
        require(_collection != address(0), "Invalid collection");
        require(bytes(_tokenName).length > 0, "Empty name");
        require(bytes(_tokenSymbol).length > 0, "Empty symbol");

        collection = IERC721(_collection);
        hookAddress = _hook;
        tokenName = _tokenName;
        tokenSymbol = _tokenSymbol;
        deployBlock = block.number;
        buyIncrement = _buyIncrement;

        _initializeOwner(_owner);

        // Default params aligned with reference strategy
        priceMultiplier = 1200; // 1.2x
        twapIncrement = 1 ether;
        twapDelayInBlocks = 1;

        // Mint the entire supply to the factory (encoded in immutable args)
        _mint(factory(), MAX_SUPPLY);
    }

    /*////////////////////////////////////////////////////////////////////
                                 MODIFIERS
    ////////////////////////////////////////////////////////////////////*/

    modifier onlyFactory() {
        if (msg.sender != factory()) revert NotFactory();
        _;
    }

    /*////////////////////////////////////////////////////////////////////
                                UUPS UPGRADE
    ////////////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
        require(newImplementation.code.length > 0, "Implementation must be contract");
        emit ContractUpgraded(address(this), newImplementation, VERSION);
    }

    function getImplementation() external view returns (address result) {
        assembly {
            result := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
    }

    /*////////////////////////////////////////////////////////////////////
                                  ERC20 META
    ////////////////////////////////////////////////////////////////////*/

    function name() public view override returns (string memory) {
        return tokenName;
    }

    function symbol() public view override returns (string memory) {
        return tokenSymbol;
    }

    /*////////////////////////////////////////////////////////////////////
                                ADMIN CONTROLS
    ////////////////////////////////////////////////////////////////////*/

    /// @notice Update the hook address
    function updateHookAddress(address _hookAddress) external onlyOwner {
        hookAddress = _hookAddress;
    }

    /// @notice Update the ERC20 name (factory-only)
    function updateName(string memory _tokenName) external onlyFactory {
        tokenName = _tokenName;
    }

    /// @notice Update the ERC20 symbol (factory-only)
    function updateSymbol(string memory _tokenSymbol) external onlyFactory {
        tokenSymbol = _tokenSymbol;
    }

    /// @notice Update resale multiplier (factory-only). Range: 1.1x to 10x.
    function setPriceMultiplier(uint256 _newMultiplier) external onlyFactory {
        if (_newMultiplier < 1100 || _newMultiplier > 10000) revert InvalidMultiplier();
        priceMultiplier = _newMultiplier;
    }

    /*////////////////////////////////////////////////////////////////////
                               STRATEGY MECHANICS
    ////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the time-based maximum price allowed for buying an NFT.
     * @dev Increases by `buyIncrement` every 5 blocks from deployment.
     */
    function getMaxPriceForBuy() public view returns (uint256) {
        uint256 blocksSinceDeployment = block.number - deployBlock;
        uint256 periods = blocksSinceDeployment / 5;
        return (periods + 1) * buyIncrement;
    }

    /**
     * @notice Hook deposits trading fees here.
     * @dev Only callable by the hook.
     */
    function addFees() external payable {
        if (msg.sender != hookAddress) revert OnlyHook();
        currentFees += msg.value;
    }

    /**
     * @notice Increase transient allowance for Uniswap v4 pool transfers.
     * @dev Only callable by the hook.
     */
    function increaseTransferAllowance(uint256 amountAllowed) external {
        if (msg.sender != hookAddress) revert OnlyHook();
        uint256 currentAllowance = getTransferAllowance();
        assembly {
            tstore(0, add(currentAllowance, amountAllowed))
        }
        emit AllowanceIncreased(amountAllowed);
    }

    /**
     * @notice Buy a specific NFT using accumulated fees and relist it.
     * @param value ETH value to spend on the purchase (must be <= currentFees and <= max price)
     * @param data Calldata for the target marketplace
     * @param expectedId Token ID expected to be acquired
     * @param target Marketplace contract to call
     */
    function buyTargetNFT(uint256 value, bytes calldata data, uint256 expectedId, address target)
        external
        nonReentrant
    {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 nftBalanceBefore = collection.balanceOf(address(this));

        if (collection.ownerOf(expectedId) == address(this)) revert AlreadyNFTOwner();
        if (value > currentFees) revert NotEnoughEth();

        if (value > getMaxPriceForBuy()) revert PriceTooHigh();
        if (target == address(collection)) revert InvalidTarget();

        (bool success, bytes memory reason) = target.call{value: value}(data);
        if (!success) revert ExternalCallFailed(reason);

        uint256 nftBalanceAfter = collection.balanceOf(address(this));
        if (nftBalanceAfter != nftBalanceBefore + 1) revert NeedToBuyNFT();
        if (collection.ownerOf(expectedId) != address(this)) revert NotNFTOwner();

        uint256 cost = ethBalanceBefore - address(this).balance;
        currentFees -= cost;

        uint256 salePrice = (cost * priceMultiplier) / 1000;
        nftForSale[expectedId] = salePrice;

        emit NFTBoughtByProtocol(expectedId, cost, salePrice);
    }

    /**
     * @notice Sell a listed NFT to the caller at the fixed price.
     * @param tokenId Token ID to purchase from the strategy
     */
    function sellTargetNFT(uint256 tokenId) external payable nonReentrant {
        uint256 salePrice = nftForSale[tokenId];
        if (salePrice == 0) revert NFTNotForSale();
        if (msg.value != salePrice) revert NFTPriceTooLow();
        if (collection.ownerOf(tokenId) != address(this)) revert NotNFTOwner();

        collection.transferFrom(address(this), msg.sender, tokenId);
        delete nftForSale[tokenId];

        // Sales proceeds are reserved for TWAP token buyback
        ethToTwap += salePrice;

        emit NFTSoldByProtocol(tokenId, salePrice, msg.sender);
    }

    /**
     * @notice TWAP buyback & burn of this ERC20 using `ethToTwap`.
     * @dev 0.5% of the used ETH is rewarded to the caller.
     */
    function processTokenTwap() external nonReentrant {
        if (ethToTwap == 0) revert NoETHToTwap();
        if (block.number < lastTwapBlock + twapDelayInBlocks) revert TwapDelayNotMet();

        uint256 burnAmount = ethToTwap < twapIncrement ? ethToTwap : twapIncrement;

        uint256 reward = (burnAmount * 5) / 1000;
        burnAmount -= reward;

        ethToTwap -= (burnAmount + reward);
        lastTwapBlock = block.number;

        _buyAndBurnTokens(burnAmount);
        SafeTransferLib.forceSafeTransferETH(msg.sender, reward);
    }

    /*////////////////////////////////////////////////////////////////////
                               INTERNAL HELPERS
    ////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute a swap on the strategy pool and burn the received tokens.
     * @dev Swaps ETH -> this token on the v4 pool and sends tokens to DEAD_ADDRESS.
     */
    function _buyAndBurnTokens(uint256 amountIn) internal {
        PoolKey memory key = PoolKey(
            Currency.wrap(address(0)),
            Currency.wrap(address(this)),
            0,
            60,
            IHooks(hookAddress)
        );

        router().swapExactTokensForTokens{value: amountIn}(
            amountIn,
            0,
            true,               // ETH -> token
            key,
            "",
            DEAD_ADDRESS,
            block.timestamp
        );
    }

    /**
     * @dev Validate transfers: only allowed through pool manager using transient allowance,
     *      or minting on launch (from address(0)).
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0)) return;

        if (from == address(poolManager()) || to == address(poolManager())) {
            uint256 transferAllowance = getTransferAllowance();
            require(transferAllowance >= amount, InvalidTransfer());
            assembly {
                let newAllowance := sub(transferAllowance, amount)
                tstore(0, newAllowance)
            }
            emit AllowanceSpent(from, to, amount);
            return;
        }

        revert InvalidTransfer();
    }

    /// @notice Read transient allowance from slot 0
    function getTransferAllowance() public view returns (uint256 transferAllowance) {
        assembly {
            transferAllowance := tload(0)
        }
    }

    /// @notice ERC721 receiver for safe transfers; only accepts from the target collection
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(collection)) revert InvalidCollection();
        return this.onERC721Received.selector;
    }

    /*////////////////////////////////////////////////////////////////////
                                     VIEWS
    ////////////////////////////////////////////////////////////////////*/

    /// @notice Factory address stored in immutable args (bytes 0..20)
    function factory() public view returns (address) {
        bytes memory args = LibClone.argsOnERC1967(address(this), 0, 20);
        return address(bytes20(args));
    }

    /// @notice Router stored in immutable args (bytes 20..40)
    function router() public view returns (IUniswapV4Router04) {
        bytes memory args = LibClone.argsOnERC1967(address(this), 20, 40);
        return IUniswapV4Router04(payable(address(bytes20(args))));
    }

    /// @notice PoolManager stored in immutable args (bytes 40..60)
    function poolManager() public view returns (IPoolManager) {
        bytes memory args = LibClone.argsOnERC1967(address(this), 40, 60);
        return IPoolManager(address(bytes20(args)));
    }

    /// @notice Accept ETH (fees / swaps / TWAP)
    receive() external payable {}
}
