// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @title Uniswap V4 Swap Router
/// @notice Stateless router interface for executing swaps on Uniswap v4 Pools
/// @dev ABI inspired by UniswapV2Router02
interface IUniswapV4Router04 {
    /// ================= MULTI POOL SWAPS ================= ///

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// ================= SINGLE POOL SWAPS ================= ///

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// ================= OPTIMIZED ================= ///

    function swap(bytes calldata data, uint256 deadline) external payable returns (BalanceDelta);

    fallback() external payable;
    receive() external payable;

    function msgSender() external view returns (address);
}
