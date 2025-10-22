// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* =========================== External deps =========================== */
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
// Removed unused BeforeSwapDelta import

/* ============================== Local =============================== */
import {ICC0Strategy, ICC0StrategyFactory, IERC721} from "./Interfaces.sol";

/**
 * @title CC0StrategyHook
 * @author cc0.company
 * @notice Uniswap v4 hook that charges dynamic fees on CC0Strategy pools and splits them:
 *         80% -> strategy (to buy NFTs), 10% -> factory (to buy&burn $CC0COMPANY),
 *         10% -> feeAddress or per-collection override.
 * @dev Buy fee decays from 95% down to 10% (sell fee is 10%). Follows the reference layout.
 */
contract CC0StrategyHook is BaseHook, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeCast for int128;

    /*//////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////*/

    uint128 private constant TOTAL_BIPS = 10_000;
    uint128 private constant DEFAULT_FEE = 1000;     // 10%
    uint128 private constant STARTING_BUY_FEE = 9500;// 95%

    uint160 private constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;
    uint160 private constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;

    /// @notice Pool manager (immutable, required by BaseHook)
    IPoolManager public immutable manager;

    /// @notice CC0 factory
    ICC0StrategyFactory public immutable cc0Factory;

    /// @notice Default address to receive the 10% fee split
    address public feeAddress;

    /*//////////////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////////////*/

    /// @notice collection (strategy address) => block number at pool deploy
    mapping(address => uint256) public deploymentBlock;

    /// @notice per-strategy custom fee recipient (if collection owner sets it)
    mapping(address => address) public feeAddressClaimedByOwner;

    /*//////////////////////////////////////////////////////////////////////
                                   EVENTS
    //////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted after fees are taken from a swap
    event HookFee(bytes32 indexed poolId, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

    /// @notice Emitted on trades for analytics
    event Trade(address indexed strategy, uint160 sqrtPriceX96, int128 ethAmount, int128 tokenAmount);

    /*//////////////////////////////////////////////////////////////////////
                                    ERRORS
    //////////////////////////////////////////////////////////////////////*/

    error NotCC0Strategy();
    error NotCC0FactoryOwner();
    error InvalidCollection();
    error NotCollectionOwner();

    /*//////////////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////*/

    /**
     * @param _poolManager Uniswap v4 PoolManager
     * @param _cc0Factory CC0StrategyFactory
     * @param _feeAddress Default fee recipient (10% split)
     */
    constructor(IPoolManager _poolManager, ICC0StrategyFactory _cc0Factory, address _feeAddress)
        BaseHook(_poolManager)
    {
        manager = _poolManager;
        cc0Factory = _cc0Factory;
        feeAddress = _feeAddress;
    }

    /*//////////////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////////////*/

    /// @notice Update the default fee receiver (10% split).
    function updateFeeAddress(address _feeAddress) external {
        if (msg.sender != cc0Factory.owner()) revert NotCC0FactoryOwner();
        feeAddress = _feeAddress;
    }

    /// @notice Set a custom fee receiver for a given strategy, callable by the NFT collection owner.
    function updateFeeAddressForCollection(address strategy, address destination) external {
        address collection = cc0Factory.cc0StrategyToCollection(strategy);
        if (collection == address(0)) revert InvalidCollection();
        if (IERC721(collection).owner() != msg.sender) revert NotCollectionOwner();
        feeAddressClaimedByOwner[strategy] = destination;
    }

    /// @notice Admin override for fee receiver on a given strategy (factory owner or factory itself).
    function adminUpdateFeeAddress(address strategy, address destination) external {
        if (msg.sender != cc0Factory.owner() && msg.sender != address(cc0Factory)) {
            revert NotCC0FactoryOwner();
        }
        feeAddressClaimedByOwner[strategy] = destination;
    }

    /*//////////////////////////////////////////////////////////////////////
                              HOOK PERMISSIONS
    //////////////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /*//////////////////////////////////////////////////////////////////////
                           LIFECYCLE INSTRUMENTATION
    //////////////////////////////////////////////////////////////////////*/

    /// @dev Only allow ETH/token pools, record deployment block. Must be called during factory liquidity load.
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        require(key.currency0.isAddressZero(), "Only ETH/token pools");
        if (!cc0Factory.loadingLiquidity()) revert NotCC0Strategy();

        // token1 in the pool is the CC0Strategy address
        address strategy = Currency.unwrap(key.currency1);
        deploymentBlock[strategy] = block.number;

        return BaseHook.beforeInitialize.selector;
    }

    /// @dev During factory liquidity loading, authorize transient allowance on the strategy.
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (!cc0Factory.loadingLiquidity()) revert NotCC0Strategy();

        // delta.amount1() is negative on add-liquidity; we authorize that absolute amount
        ICC0Strategy(Currency.unwrap(key.currency1)).increaseTransferAllowance(
            uint256(int256(-delta.amount1()))
        );

        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /*//////////////////////////////////////////////////////////////////////
                                 FEE LOGIC
    //////////////////////////////////////////////////////////////////////*/

    /// @notice Compute current fee bips. Buys start high and decay to DEFAULT_FEE.
    function calculateFee(address strategy, bool isBuying) public view returns (uint128) {
        if (!isBuying) return DEFAULT_FEE;

        uint256 deployedAt = deploymentBlock[strategy];
        if (deployedAt == 0) return DEFAULT_FEE;

        uint256 blocksPassed = block.number - deployedAt;
        uint256 feeReductions = (blocksPassed * 100) / 5; // reduce 1% every 5 blocks

        uint256 maxReducible = STARTING_BUY_FEE - DEFAULT_FEE;
        if (feeReductions >= maxReducible) return DEFAULT_FEE;

        return uint128(STARTING_BUY_FEE - feeReductions);
    }

    /// @dev Take fee from swap, convert to ETH if needed, split, and emit events.
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Determine the fee currency and absolute swap amount
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        if (swapAmount < 0) swapAmount = -swapAmount;

        bool ethFee = Currency.unwrap(feeCurrency) == address(0);
        address strategy = Currency.unwrap(key.currency1);

        uint128 currentFee = calculateFee(strategy, params.zeroForOne);
        uint256 feeAmount = (uint128(swapAmount) * currentFee) / TOTAL_BIPS;

        // Always ensure the pool can transfer strategy tokens by increasing transient allowance.
        uint256 strategyAmountToTransfer =
            delta.amount1() < 0 ? uint256(int256(-delta.amount1())) : uint256(int256(delta.amount1()));

        if (feeAmount == 0) {
            ICC0Strategy(strategy).increaseTransferAllowance(strategyAmountToTransfer);
            return (BaseHook.afterSwap.selector, 0);
        }

        // Account for fee-in-strategy-token for allowance on exact-in and exact-out flows.
        if (feeCurrency == key.currency1) {
            strategyAmountToTransfer += feeAmount;
            if (params.amountSpecified > 0) {
                // exact-output scenario: hook pulls fee from PM and PM again from hook (surplus pattern)
                strategyAmountToTransfer += feeAmount;
            }
        }

        ICC0Strategy(strategy).increaseTransferAllowance(strategyAmountToTransfer);

        // Pull the fee into the hook
        manager.take(feeCurrency, address(this), feeAmount);

        emit HookFee(PoolId.unwrap(key.toId()), sender, ethFee ? uint128(feeAmount) : 0, ethFee ? 0 : uint128(feeAmount));

        // Convert to ETH if fee is in strategy tokens
        uint256 feeInETH;
        if (!ethFee) {
            feeInETH = _swapToEth(key, feeAmount);
        } else {
            feeInETH = feeAmount;
        }

        // Split and forward
        _processFees(strategy, feeInETH);

        // Emit price/flow telemetry
        emit Trade(strategy, _getCurrentPrice(key), delta.amount0(), delta.amount1());

        // Return fee amount to be accounted by PM
        return (BaseHook.afterSwap.selector, feeAmount.toInt128());
    }

    /// @dev Split: 80% -> strategy.addFees, 10% -> factory (for $CC0COMPANY buy&burn TWAP),
    ///             10% -> feeAddress or collection override.
    function _processFees(address strategy, uint256 feeAmount) internal {
        if (feeAmount == 0) return;

        uint256 toStrategy = (feeAmount * 80) / 100;
        uint256 toFactory = (feeAmount * 10) / 100;
        uint256 toOwner   = feeAmount - toStrategy - toFactory;

        // 80%: deposit into strategy
        ICC0Strategy(strategy).addFees{value: toStrategy}();

        // 10%: forward to factory; factory will manage $CC0COMPANY buy&burn via its TWAP function(s)
        SafeTransferLib.forceSafeTransferETH(address(cc0Factory), toFactory);

        // 10%: to per-collection override or default feeAddress
        address dest = feeAddressClaimedByOwner[strategy];
        SafeTransferLib.forceSafeTransferETH(dest == address(0) ? feeAddress : dest, toOwner);
    }

    /*//////////////////////////////////////////////////////////////////////
                           INTERNAL SWAP HELPERS
    //////////////////////////////////////////////////////////////////////*/

    /// @dev Convert strategy tokens to ETH using the pool.
    function _swapToEth(PoolKey memory key, uint256 amount) internal returns (uint256) {
        uint256 ethBefore = address(this).balance;

        BalanceDelta d = manager.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: MAX_PRICE_LIMIT}),
            bytes("")
        );

        // Settle token out / take ETH in
        key.currency1.settle(poolManager, address(this), uint256(int256(-d.amount1())), false);
        key.currency0.take(poolManager, address(this), uint256(int256(d.amount0())), false);

        return address(this).balance - ethBefore;
    }

    function _getCurrentPrice(PoolKey calldata key) internal view returns (uint160) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        return sqrtPriceX96;
    }

    /*//////////////////////////////////////////////////////////////////////
                                  RECEIVE
    //////////////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
