// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Super-simple ERC721-like mock with owner(), used as collection input for the factory/strategy tests.
contract MockERC721 {
    string public name = "MockNFT";
    string public symbol = "MNFT";

    address public owner;

    mapping(address => uint256) private _balances;

    constructor(address _owner) {
        owner = _owner;
    }

    function balanceOf(address a) external view returns (uint256) {
        return _balances[a];
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "only-owner");
        _balances[to] += amount;
    }

    function ownerOf(uint256) external view returns (address) {
        return owner;
    }
}
