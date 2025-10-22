// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolInitializer_v4} from "@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import {IMulticall_v4} from "@uniswap/v4-periphery/src/interfaces/IMulticall_v4.sol";
import {IEIP712_v4} from "@uniswap/v4-periphery/src/interfaces/IEIP712_v4.sol";
import {IImmutableState} from "@uniswap/v4-periphery/src/interfaces/IImmutableState.sol";
import {INotifier} from "@uniswap/v4-periphery/src/interfaces/INotifier.sol";
import {ISubscriber} from "@uniswap/v4-periphery/src/interfaces/ISubscriber.sol";
import {IUnorderedNonce} from "@uniswap/v4-periphery/src/interfaces/IUnorderedNonce.sol";
import {IERC721Permit_v4} from "@uniswap/v4-periphery/src/interfaces/IERC721Permit_v4.sol";
import {IPermit2Forwarder} from "@uniswap/v4-periphery/src/interfaces/IPermit2Forwarder.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionInfo} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

/// @notice Minimal, complete stub PositionManager that satisfies the IPositionManager interface tree.
contract MockPositionManager is IPositionManager {
    // ---------------- IPoolInitializer_v4 ----------------
    function initializePool(PoolKey calldata, uint160) external payable override returns (int24) {
        return 0;
    }

    // ---------------- IPositionManager core ----------------
    function modifyLiquidities(bytes calldata, uint256) external payable override {}

    function modifyLiquiditiesWithoutUnlock(bytes calldata, bytes[] calldata) external payable override {}

    function nextTokenId() external pure override returns (uint256) {
        return 0;
    }

    function getPositionLiquidity(uint256) external pure override returns (uint128 liquidity) {
        return 0;
    }

    function getPoolAndPositionInfo(uint256)
        external
        pure
        override
        returns (PoolKey memory poolKey, PositionInfo info)
    {
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });
        info = PositionInfo.wrap(0);
    }

    function positionInfo(uint256) external pure override returns (PositionInfo) {
        return PositionInfo.wrap(0);
    }

    // ---------------- IEIP712_v4 ----------------
    function DOMAIN_SEPARATOR() external pure override returns (bytes32) {
        return bytes32(0);
    }

    // ---------------- IMulticall_v4 ----------------
    function multicall(bytes[] calldata) external payable override returns (bytes[] memory results) {
        return new bytes[](0);
    }

    // ---------------- IImmutableState ----------------
    function poolManager() external pure override returns (IPoolManager) {
        return IPoolManager(address(0));
    }

    // ---------------- IUnorderedNonce ----------------
    function nonces(address, uint256) external pure override returns (uint256) {
        return 0;
    }

    function revokeNonce(uint256) external payable override {}

    // ---------------- IERC721Permit_v4 ----------------
    function permit(address, uint256, uint256, uint256, bytes calldata) external payable override {}

    function permitForAll(address, address, bool, uint256, uint256, bytes calldata) external payable override {}

    // ---------------- IPermit2Forwarder ----------------
    function permit(address, IAllowanceTransfer.PermitSingle calldata, bytes calldata)
        external
        payable
        override
        returns (bytes memory err)
    {
        return bytes("");
    }

    function permitBatch(address, IAllowanceTransfer.PermitBatch calldata, bytes calldata)
        external
        payable
        override
        returns (bytes memory err)
    {
        return bytes("");
    }

    // ---------------- INotifier ----------------
    function subscriber(uint256) external pure override returns (ISubscriber) {
        return ISubscriber(address(0));
    }

    function subscribe(uint256, address, bytes calldata) external payable override {}

    function unsubscribe(uint256) external payable override {}

    function unsubscribeGasLimit() external pure override returns (uint256) {
        return 0;
    }
}
