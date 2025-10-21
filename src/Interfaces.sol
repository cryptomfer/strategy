// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IUniswapV4Router04} from "./vendor/IUniswapV4Router04.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @title Core Interfaces (CC0Strategy)
/// @notice Shared interfaces for CC0 strategy, factory, and hook contracts

/// @notice Minimal ERC721 interface including optional owner()
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function owner() external view returns (address);
}

/// @notice Core interface for CC0-backed strategy token contracts
interface ICC0Strategy {
    function initialize(
        address _collection,
        address _hook,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _buyIncrement,
        address _owner
    ) external;

    function updateName(string memory _tokenName) external;
    function updateSymbol(string memory _tokenSymbol) external;
    function setPriceMultiplier(uint256 _newMultiplier) external;

    function addFees() external payable;
    function increaseTransferAllowance(uint256 amountAllowed) external;

    function factory() external view returns (address);
    function router() external view returns (IUniswapV4Router04);
    function poolManager() external view returns (IPoolManager);
    function owner() external view returns (address);
}

/// @notice Hook interface for fee routing and protocol management
interface ICC0StrategyHook {
    function adminUpdateFeeAddress(address cc0Strategy, address destination) external;
}

/// @notice Factory interface for deploying and tracking CC0 strategy contracts
interface ICC0StrategyFactory {
    function loadingLiquidity() external view returns (bool);
    function owner() external view returns (address);
    function cc0StrategyToCollection(address) external view returns (address);
    function collectionToCC0Strategy(address) external view returns (address);
}

/// @notice Marker interface for PunkStrategy tokens
interface IPunkStrategy {}

/// @notice Interface for validating router senders
interface IValidRouter {
    function msgSender() external view returns (address);
}
