// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Re-export canonical interfaces so tests can import a single stable path.
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager}     from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

// We vendor the v4 router interface locally to keep it stable.
import {IUniswapV4Router04} from "./IUniswapV4Router04.sol";

// No code: the imports are the product; tests import this file for stable paths.

