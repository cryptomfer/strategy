// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* ============ External deps ============ */
import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

/* Router interface (local vendor) */
import {IUniswapV4Router04} from "./vendor/IUniswapV4Router04.sol";

/* Shared interfaces (CC0 versions) */
import {ICC0Strategy, ICC0StrategyHook, ICC0StrategyFactory, IERC721} from "./Interfaces.sol";

/* ============ Minimal interfaces ============ */
interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/* Forward declaration so this file can exist before CC0Strategy.sol is added */
contract CC0Strategy {
    function initialize(
        address _collection,
        address _hook,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _buyIncrement,
        address _owner
    ) external {}
}

/**
 * @title CC0StrategyFactory
 * @author cc0.company
 * @notice Factory that deploys CC0Strategy pools with a Uniswap v4 hook tax.
 * @dev Mirrors nftstrategy.fun Factory semantics with the following changes:
 *      - Launch fee payable in ETH (default 0.69 ETH, owner-configurable)
 *      - Optional fee payment in $CC0COMPANY on Base with a discount (default 20%)
 *      - Admin free launch function
 *      - Buyback/burn sends 10% tax to this factory and performs a TWAP-based burn of $CC0COMPANY
 */
contract CC0StrategyFactory is Ownable, ReentrancyGuard, ICC0StrategyFactory {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH used when pairing initial liquidity (match nftstrategy semantics)
    uint256 private constant ETH_TO_PAIR = 2 wei;

    /// @notice Dead address used for burns
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IPositionManager private immutable posm;
    IAllowanceTransfer private immutable permit2;
    IUniswapV4Router04 private immutable router;
    IPoolManager private immutable poolManager;

    /// @notice Whether this deployment is on Base (enables fee-in-CC0 discount path)
    bool public immutable isBaseChain;

    /*//////////////////////////////////////////////////////////////
                               STATE VARS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping: collection => strategy
    mapping(address => address) public collectionToCC0Strategy;

    /// @notice Mapping: strategy => collection
    mapping(address => address) public cc0StrategyToCollection;

    /// @notice Authorized launchers (besides owner)
    mapping(address => bool) public launchers;

    /// @notice Hook address used by newly deployed pools
    address public hookAddress;

    /// @notice True only while the factory performs initial liquidity (checked by hook)
    bool public loadingLiquidity;

    /// @notice If true, newly launched strategies are upgradeable (UUPS owner set to owner())
    bool public launchUpgradeable = true;

    /// @notice Address that receives deployment fees
    address public feeAddress;

    /// @notice Implementation contract used for ERC1967 proxies
    address public cc0StrategyImplementation;

    /// @notice $CC0COMPANY token used for Base-chain discounted fees and buyback burns
    address public cc0CompanyToken;

    /// @notice Launch fee in ETH (default 0.69 ETH)
    uint256 public launchFeeEth = 0.69 ether;

    /// @notice When paying fee in $CC0COMPANY on Base, fixed token amount taken
    /// @dev Owner should set this so it reflects ~20% discount versus launchFeeEth at current prices.
    uint256 public launchFeeCc0OnBase;

    /// @notice Discount in basis points for Base fee-in-CC0 informationally (not enforced by math)
    /// @dev Only informational; enforcement is done by launchFeeCc0OnBase amount set by owner.
    uint256 public cc0DiscountBips = 2000; // 20%

    /// @notice TWAP buyback settings for factory-held ETH (10% hook share)
    uint256 public twapIncrement = 1 ether;
    uint256 public twapDelayInBlocks = 1;
    uint256 public lastTwapBlock;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new strategy is launched
    event CC0StrategyLaunched(
        address indexed collection,
        address indexed strategy,
        string tokenName,
        string tokenSymbol
    );

    /// @notice Emitted when fees are paid
    event LaunchFeePaid(address indexed payer, bool paidInCc0, uint256 amount);

    /// @notice Emitted on TWAP burn
    event Cc0BoughtAndBurned(uint256 amountInEth);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error HookNotSet();
    error CollectionAlreadyLaunched();
    error WrongEthAmount();
    error NotERC721();
    error CannotLaunch();
    error InvalidIncrement();
    error NotBaseChain();
    error Cc0TokenNotSet();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _posm,
        address _permit2,
        address payable _router,
        address _poolManager,
        address _feeAddress,
        address _cc0CompanyToken,
        bool _isBaseChain
    ) {
        posm = IPositionManager(_posm);
        permit2 = IAllowanceTransfer(_permit2);
        router = IUniswapV4Router04(_router);
        poolManager = IPoolManager(_poolManager);
        feeAddress = _feeAddress;
        cc0CompanyToken = _cc0CompanyToken;
        isBaseChain = _isBaseChain;

        // prepare implementation
        cc0StrategyImplementation = address(new CC0Strategy());
        _initializeOwner(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyLauncher() {
        if (msg.sender != owner() && !launchers[msg.sender]) revert Ownable.Unauthorized();
        _;
    }

    /// @notice Explicit override to resolve owner() collision between Ownable and ICC0StrategyFactory
    function owner()
        public
        view
        override(Ownable, ICC0StrategyFactory)
        returns (address)
    {
        return Ownable.owner();
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN AREA
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the strategy implementation (for future launches)
    function setCc0StrategyImplementation(address _impl) external onlyOwner {
        cc0StrategyImplementation = _impl;
    }

    /// @notice Disable upgrade ownership on future launches (locks future proxies)
    function disableLaunchUpgradeable() external onlyOwner {
        launchUpgradeable = false;
    }

    /// @notice Set launch fee in ETH
    function setLaunchFeeEth(uint256 newFee) external onlyOwner {
        launchFeeEth = newFee;
    }

    /// @notice Set the CC0 token address (used for Base discount and buyback)
    function setCc0CompanyToken(address token) external onlyOwner {
        cc0CompanyToken = token;
    }

    /// @notice Set the fee amount in $CC0COMPANY when paying on Base
    /// @dev Owner should maintain this to reflect ~20% discount at current token prices
    function setLaunchFeeCc0OnBase(uint256 amount) external onlyOwner {
        launchFeeCc0OnBase = amount;
    }

    /// @notice Set the informational discount bips (UI/UX only)
    function setCc0DiscountBips(uint256 bips) external onlyOwner {
        cc0DiscountBips = bips;
    }

    /// @notice Update the Uniswap v4 hook used by newly launched pools
    function updateHookAddress(address _hook) external onlyOwner {
        hookAddress = _hook;
    }

    /// @notice Allow or remove external launcher
    function updateLauncher(address who, bool auth) external onlyOwner {
        launchers[who] = auth;
    }

    /// @notice Set fee receiver
    function setFeeAddress(address to) external onlyOwner {
        feeAddress = to;
    }

    /// @notice Adjust factory TWAP settings
    function setFactoryTwap(uint256 increment, uint256 delayInBlocks) external onlyOwner {
        if (increment == 0) revert InvalidIncrement();
        twapIncrement = increment;
        twapDelayInBlocks = delayInBlocks;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL DEPLOY HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployUpgradeableCC0Strategy(
        address _collection,
        address _hook,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _buyIncrement,
        address _owner
    ) internal returns (CC0Strategy proxy) {
        bytes memory args = abi.encodePacked(address(this), router, poolManager);
        proxy = CC0Strategy(payable(LibClone.deployERC1967(cc0StrategyImplementation, args)));

        proxy.initialize(
            _collection, _hook, _tokenName, _tokenSymbol, _buyIncrement, launchUpgradeable ? _owner : address(0)
        );
    }

    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    )
        internal
        pure
        returns (bytes memory actions, bytes[] memory params)
    {
        actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        params = new bytes[](2);
        params[0] =
            abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
    }

    function _loadLiquidity(address _token) internal {
        loadingLiquidity = true;

        // Pool: ETH (currency0) / CC0 token (currency1)
        Currency currency0 = Currency.wrap(address(0));
        Currency currency1 = Currency.wrap(_token);

        uint24 lpFee = 0;
        int24 tickSpacing = 60;

        uint256 token0Amount = 1; // 1 wei
        uint256 token1Amount = 1_000_000_000 * 1e18; // 1B TOKEN

        // same initial price constant as reference
        uint160 startingPrice = 501082896750095888663770159906816;

        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = int24(175020);

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        bytes memory hookData = new bytes(0);

        // Hard-coded liquidity matching reference
        uint128 liquidity = 158372218983990412488087;

        uint256 amount0Max = token0Amount + 1;
        uint256 amount1Max = token1Amount + 1;

        // Approve token1 (ERC20) to PositionManager for liquidity add
        permit2.approve(_token, address(posm), type(uint160).max, type(uint48).max);

        // Initialize the pool directly on the position manager (payable)
        uint256 valueToPass = amount0Max;
        int24 tick = posm.initializePool{value: valueToPass}(poolKey, startingPrice);
        require(tick != type(int24).max, "Pool init failed or already exists");

        // Build mint-only modifyLiquidities batch
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            uint128(amount0Max),
            uint128(amount1Max),
            DEAD_ADDRESS,
            hookData
        );

        posm.modifyLiquidities{value: valueToPass}(abi.encode(actions, params), block.timestamp + 60);

        loadingLiquidity = false;
    }

    /*//////////////////////////////////////////////////////////////
                           BUYBACK / TWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    function _buyAndBurnCC0(uint256 amountIn) internal {
        // PoolKey(ETH, CC0 token, 0 fee, spacing 60, hookAddress)
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(cc0CompanyToken),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        router.swapExactTokensForTokens{value: amountIn}(
            amountIn,
            0,
            true, // zeroForOne: ETH -> TOKEN
            key,
            "",
            DEAD_ADDRESS,
            block.timestamp
        );
        emit Cc0BoughtAndBurned(amountIn);
    }

    /// @notice TWAP buyback/burn using this factory’s ETH balance
    function processTokenTwap() external nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert CannotLaunch();

        if (block.number < lastTwapBlock + twapDelayInBlocks) revert CannotLaunch();

        uint256 burnAmount = balance < twapIncrement ? balance : twapIncrement;

        // 0.5% caller reward
        uint256 reward = (burnAmount * 5) / 1000;
        burnAmount -= reward;

        lastTwapBlock = block.number;

        _buyAndBurnCC0(burnAmount);
        SafeTransferLib.forceSafeTransferETH(msg.sender, reward);
    }

    /*//////////////////////////////////////////////////////////////
                              FEE HANDLING
    //////////////////////////////////////////////////////////////*/

    function _takeEthFee() internal {
        if (msg.value != launchFeeEth) revert WrongEthAmount();
        SafeTransferLib.forceSafeTransferETH(feeAddress, msg.value);
        emit LaunchFeePaid(msg.sender, false, msg.value);
    }

    function _takeCc0FeeOnBase(address payer) internal {
        if (!isBaseChain) revert NotBaseChain();
        if (cc0CompanyToken == address(0)) revert Cc0TokenNotSet();
        if (launchFeeCc0OnBase == 0) revert CannotLaunch();

        // pull tokens to feeAddress
        require(IERC20(cc0CompanyToken).transferFrom(payer, feeAddress, launchFeeCc0OnBase), "CC0 transfer failed");
        emit LaunchFeePaid(payer, true, launchFeeCc0OnBase);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL USER FLOWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Public launch with ETH fee
    function launchCC0StrategyWithEth(
        address collection,
        string calldata tokenName,
        string calldata tokenSymbol,
        address collectionOwner,
        uint256 buyIncrement
    ) external payable nonReentrant returns (address) {
        return _launch(collection, tokenName, tokenSymbol, collectionOwner, buyIncrement, FeeMode.ETH);
    }

    /// @notice Public launch on Base paying in $CC0COMPANY (discounted)
    function launchCC0StrategyWithCc0(
        address collection,
        string calldata tokenName,
        string calldata tokenSymbol,
        address collectionOwner,
        uint256 buyIncrement
    ) external nonReentrant returns (address) {
        return _launch(collection, tokenName, tokenSymbol, collectionOwner, buyIncrement, FeeMode.CC0);
    }

    /// @notice Admin/launcher free launch (no fee taken)
    function adminLaunchCC0Strategy(
        address collection,
        string calldata tokenName,
        string calldata tokenSymbol,
        address collectionOwner,
        uint256 buyIncrement
    ) external onlyLauncher nonReentrant returns (address) {
        return _launch(collection, tokenName, tokenSymbol, collectionOwner, buyIncrement, FeeMode.FREE);
    }

    enum FeeMode {
        ETH,
        CC0,
        FREE
    }

    function _launch(
        address collection,
        string memory tokenName,
        string memory tokenSymbol,
        address collectionOwner,
        uint256 buyIncrement
    ) internal returns (address) {
        // default path is ETH unless function-specific
        return _launch(collection, tokenName, tokenSymbol, collectionOwner, buyIncrement, FeeMode.ETH);
    }

    function _launch(
        address collection,
        string memory tokenName,
        string memory tokenSymbol,
        address collectionOwner,
        uint256 buyIncrement,
        FeeMode feeMode
    ) internal returns (address) {
        if (hookAddress == address(0)) revert HookNotSet();
        if (collectionToCC0Strategy[collection] != address(0)) revert CollectionAlreadyLaunched();
        if (!IERC721(collection).supportsInterface(0x80ac58cd)) revert NotERC721();

        // Fees
        if (feeMode == FeeMode.ETH) {
            _takeEthFee();
        } else if (feeMode == FeeMode.CC0) {
            _takeCc0FeeOnBase(msg.sender);
        } else {
            // FREE: no fee
        }

        // Deploy strategy proxy
        CC0Strategy strat = _deployUpgradeableCC0Strategy(
            collection,
            hookAddress,
            tokenName,
            tokenSymbol,
            buyIncrement,
            owner()
        );

        // Indexing
        collectionToCC0Strategy[collection] = address(strat);
        cc0StrategyToCollection[address(strat)] = collection;

        // Load initial liquidity (costs 2 wei)
        _loadLiquidity(address(strat));

        // Forward fee destination to collection owner (hook distribution)
        ICC0StrategyHook(hookAddress).adminUpdateFeeAddress(address(strat), collectionOwner);

        emit CC0StrategyLaunched(collection, address(strat), tokenName, tokenSymbol);
        return address(strat);
    }

    /// @notice Allows the contract to receive ETH (used by TWAP logic)
    receive() external payable {}
}


