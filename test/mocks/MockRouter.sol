// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IUniswapV4Router04 } from "../../src/vendor/IUniswapV4Router04.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract MockRouter is IUniswapV4Router04 {
    address private _sender;

    constructor() {
        _sender = msg.sender;
    }

    // -------- Multi-pool --------
    function swapExactTokensForTokens(
        uint256,
        uint256,
        Currency,
        PathKey[] calldata,
        address,
        uint256
    ) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    function swapTokensForExactTokens(
        uint256,
        uint256,
        Currency,
        PathKey[] calldata,
        address,
        uint256
    ) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    function swap(
        int256,
        uint256,
        Currency,
        PathKey[] calldata,
        address,
        uint256
    ) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    // -------- Single-pool --------
    function swapExactTokensForTokens(
        uint256,
        uint256,
        bool,
        PoolKey calldata,
        bytes calldata,
        address,
        uint256
    ) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    function swapTokensForExactTokens(
        uint256,
        uint256,
        bool,
        PoolKey calldata,
        bytes calldata,
        address,
        uint256
    ) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    function swap(
        int256,
        uint256,
        bool,
        PoolKey calldata,
        bytes calldata,
        address,
        uint256
    ) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    // -------- Optimized --------
    function swap(bytes calldata, uint256) external payable override returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    // -------- Misc --------
    function msgSender() external view override returns (address) {
        return _sender;
    }

    fallback() external payable {}
    receive() external payable {}
}
