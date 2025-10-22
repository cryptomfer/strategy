// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal mirror of Uniswap v4 hook permission packing.
/// @dev Maintains the same bit layout as Hooks library in v4-core.
library HookPermLib {
    // Bit flags (match @uniswap/v4-core/libraries/Hooks.sol)
    uint160 internal constant BEFORE_INITIALIZE_FLAG     = 1 << 0;
    uint160 internal constant AFTER_INITIALIZE_FLAG      = 1 << 1;
    uint160 internal constant BEFORE_ADD_LIQUIDITY_FLAG  = 1 << 2;
    uint160 internal constant AFTER_ADD_LIQUIDITY_FLAG   = 1 << 3;
    uint160 internal constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << 4;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_FLAG  = 1 << 5;
    uint160 internal constant BEFORE_SWAP_FLAG           = 1 << 6;
    uint160 internal constant AFTER_SWAP_FLAG            = 1 << 7;
    uint160 internal constant BEFORE_DONATE_FLAG         = 1 << 8;
    uint160 internal constant AFTER_DONATE_FLAG          = 1 << 9;

    struct Perms {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
    }

    function pack(Perms memory p) internal pure returns (uint160 mask) {
        if (p.beforeInitialize)      mask |= BEFORE_INITIALIZE_FLAG;
        if (p.afterInitialize)       mask |= AFTER_INITIALIZE_FLAG;
        if (p.beforeAddLiquidity)    mask |= BEFORE_ADD_LIQUIDITY_FLAG;
        if (p.afterAddLiquidity)     mask |= AFTER_ADD_LIQUIDITY_FLAG;
        if (p.beforeRemoveLiquidity) mask |= BEFORE_REMOVE_LIQUIDITY_FLAG;
        if (p.afterRemoveLiquidity)  mask |= AFTER_REMOVE_LIQUIDITY_FLAG;
        if (p.beforeSwap)            mask |= BEFORE_SWAP_FLAG;
        if (p.afterSwap)             mask |= AFTER_SWAP_FLAG;
        if (p.beforeDonate)          mask |= BEFORE_DONATE_FLAG;
        if (p.afterDonate)           mask |= AFTER_DONATE_FLAG;
    }
}
