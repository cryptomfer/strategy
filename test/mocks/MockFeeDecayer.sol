// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title MockFeeDecayer
/// @notice Standalone fee-decay mock that reproduces the buy/sell fee logic
///         of CC0StrategyHook without inheriting Uniswap's BaseHook.
///         This lets us unit-test the math without special hook addresses.
contract MockFeeDecayer {
    // Config (match your hook constants)
    uint128 public constant STARTING_BUY_FEE_BIPS = 9500; // 95%
    uint128 public constant SELL_FEE_BIPS = 300;          // 3% (example from your hook)
    uint256 public constant BPS_PER_STEP = 100;           // 1% per step
    uint256 public constant BLOCKS_PER_STEP = 5;          // every 5 blocks

    uint256 public immutable launchBlock;

    constructor(uint256 _launchBlock) {
        launchBlock = _launchBlock;
    }

    /// @notice Mirrors CC0StrategyHook.calculateFee(bool)
    /// @dev For buy: starts high and decays by 1% per 5 blocks
    ///      For sell: constant SELL_FEE_BIPS
    function calculateFee(bool isBuying) external view returns (uint128) {
        if (!isBuying) return SELL_FEE_BIPS;

        uint256 blocksPassed = block.number - launchBlock;
        uint256 reduction = (blocksPassed * BPS_PER_STEP) / BLOCKS_PER_STEP;

        if (reduction >= STARTING_BUY_FEE_BIPS) return 0;
        return uint128(STARTING_BUY_FEE_BIPS - reduction);
    }
}
