// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Permit2 mock that conforms to IAllowanceTransfer. No-ops all methods.
contract MockPermit2 is IAllowanceTransfer {
    // IEIP712
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return bytes32(0);
    }

    // IAllowanceTransfer core approval/permit
    function approve(address /*token*/, address /*spender*/, uint160 /*amount*/, uint48 /*expiration*/) external {}

    function permit(address /*owner*/, PermitSingle memory /*permitSingle*/, bytes calldata /*signature*/) external {}

    function permit(address /*owner*/, PermitBatch memory /*permitBatch*/, bytes calldata /*signature*/) external {}

    // Views
    function allowance(address, address, address) external view returns (uint160 amount, uint48 expiration, uint48 nonce) {
        return (type(uint160).max, type(uint48).max, 0);
    }

    // Transfers
    function transferFrom(address /*from*/, address /*to*/, uint160 /*amount*/, address /*token*/) external {}

    function transferFrom(AllowanceTransferDetails[] calldata /*transferDetails*/) external {}

    // Revocations / nonce management
    function lockdown(TokenSpenderPair[] calldata /*approvals*/) external {}

    function invalidateNonces(address /*token*/, address /*spender*/, uint48 /*newNonce*/) external {}
}
