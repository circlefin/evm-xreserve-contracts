/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity ^0.8.29;

import {Cursor} from "@gateway/src/lib/Cursor.sol";
import {TransferSpecLib} from "@gateway/src/lib/TransferSpecLib.sol";
import {TypedMemView} from "@memview-sol/TypedMemView.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BYTES4_BYTES} from "./../../common/Constants.sol";
import {IGatewayMinter} from "./../../interfaces/IGatewayMinter.sol";
import {AddressLib} from "./../../lib/AddressLib.sol";
import {NoValidationAttestationLib} from "./../../lib/NoValidationAttestationLib.sol";
import {WithdrawHookDataLib} from "./../../lib/WithdrawHookDataLib.sol";
import {DepositToRemote} from "./DepositToRemote.sol";

/// @title Withdrawal
/// @notice Module for handling withdrawal operations with complete forwarding support
/// @dev Handles all withdrawal logic including validation and forwarding
abstract contract Withdrawal is DepositToRemote {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using WithdrawHookDataLib for bytes29;
    using TransferSpecLib for bytes29;

    // ============ Errors ============

    /// @dev Thrown when an invalid forwarding contract is provided.
    error InvalidForwardingContract(address forwardingContract);

    /// @dev Thrown when the forwarding calldata is invalid.
    error InvalidForwardingCalldata(bytes forwardingCalldata);

    /// @dev Thrown when the destination recipient is invalid.
    error InvalidDestinationRecipient(bytes32 destinationRecipient);

    /// @dev Thrown when the hook data length is zero.
    error HookDataEmpty();

    /// @dev Thrown when the function selector is invalid.
    error InvalidFunctionSelector(bytes4 functionSelector);

    /// @dev Thrown when the forwarding calldata is too short to contain a function selector.
    error ForwardingCalldataTooShort(uint32 length);

    // ============ Events ============

    /// @notice Emitted when a withdrawal operation is completed
    /// @param localToken address of token being withdrawn on source domain
    /// @param value amount being withdrawn
    /// @param remoteDepositor address that originally deposited on remote domain as bytes32
    /// @param localRecipient address receiving tokens on source domain
    /// @param remoteDomain source domain where the original deposit occurred
    /// @param remoteToken token address on remote domain as bytes32
    /// @param transferSpecHash hash of the transfer spec that was executed during withdrawal
    event Withdrawn(
        address indexed localToken,
        uint256 value,
        bytes32 indexed remoteDepositor,
        address indexed localRecipient,
        uint32 remoteDomain,
        bytes32 remoteToken,
        bytes32 transferSpecHash
    );

    // ============ Public Functions ============

    /// @notice Withdraws tokens from the reserve contract
    /// @dev This function handles the withdrawal of tokens from the reserve contract.
    ///      It validates the attestation payload and signature and processes the withdrawal accordingly.
    /// @param attestationPayload The encoded gateway attestation data containing withdrawal details
    /// @param signature The signature from a valid attestation signer on `attestationPayload`
    function withdraw(bytes calldata attestationPayload, bytes calldata signature) external nonReentrant {
        // Phase 1: Execute gatewayMint
        // We mint tokens first because:
        // 1. Combining validation and processing in one phase is more gas efficient.
        // 2. Since transaction is atomic, minting will revert if any of the validations fail.
        IGatewayMinter(gatewayMinter).gatewayMint(attestationPayload, signature);

        // Phase 2: Integrated validation and processing - iterate through attestations
        {
            Cursor memory cursor = NoValidationAttestationLib.cursor(attestationPayload);

            while (!cursor.done) {
                bytes29 attestationView = NoValidationAttestationLib.next(cursor);
                bytes29 transferSpecView = NoValidationAttestationLib.getTransferSpec(attestationView);
                bytes29 hookDataView = transferSpecView.getHookData();

                // Validate hook data and process forwarding
                (uint32 remoteDomain, bytes32 remoteDepositor, bytes32 remoteToken) =
                    _validateAndProcessHookData(hookDataView, transferSpecView);

                uint256 value = transferSpecView.getValue();
                address localToken = AddressLib._bytes32ToAddressSafe(transferSpecView.getDestinationToken());
                bytes32 localRecipient = transferSpecView.getDestinationRecipient();

                // Emit withdrawal event
                emit Withdrawn(
                    localToken,
                    value,
                    remoteDepositor,
                    AddressLib._bytes32ToAddressSafe(localRecipient),
                    remoteDomain,
                    remoteToken,
                    transferSpecView.getHash()
                );
            }
        }
    }

    // ============ Internal Validation and Forwarding ============

    /// @notice Validates withdrawal hook data and processes forwarding
    /// @param hookDataView The hook data view containing withdrawal information
    /// @param transferSpecView The transfer spec view containing transfer details
    /// @return remoteDomain The remote domain from hook data
    /// @return remoteDepositor The remote depositor from hook data
    /// @return remoteToken The remote token from hook data
    function _validateAndProcessHookData(bytes29 hookDataView, bytes29 transferSpecView)
        internal
        returns (uint32 remoteDomain, bytes32 remoteDepositor, bytes32 remoteToken)
    {
        if (transferSpecView.getHookDataLength() == 0) {
            revert HookDataEmpty();
        }

        // Validate hook data structure
        hookDataView._validateWithdrawHookDataStructure();

        // Extract hook data fields once for validation and processing
        remoteDomain = hookDataView.getRemoteDomain();
        remoteDepositor = hookDataView.getRemoteDepositor();
        remoteToken = hookDataView.getRemoteToken();

        // Check global pause state
        _requireNotPaused();

        // Validate remote domain is registered
        if (!isRemoteDomainRegistered(remoteDomain)) {
            revert RemoteDomainNotRegistered(remoteDomain);
        }

        // Validate remote domain is not paused
        if (domainWithdrawalsPaused(remoteDomain)) {
            revert DomainWithdrawalsPaused(remoteDomain);
        }

        // Validate remote depositor is not blocklisted
        _ensureNotBlocklisted(remoteDomain, remoteDepositor);

        // Validate remote token is registered
        if (!isRemoteTokenRegistered(remoteDomain, remoteToken)) {
            revert RemoteTokenNotRegistered(remoteDomain, remoteToken);
        }

        // Validate and process forwarding
        address forwardingContract = AddressLib._bytes32ToAddressSafe(hookDataView.getForwardingContract());

        if (forwardingContract == address(0)) {
            return (remoteDomain, remoteDepositor, remoteToken);
        }

        // Validate destination recipient for forwarding
        bytes32 destinationRecipient = transferSpecView.getDestinationRecipient();
        if (AddressLib._bytes32ToAddressSafe(destinationRecipient) != address(this)) {
            revert InvalidDestinationRecipient(destinationRecipient);
        }

        // Validate forwarding contract
        if (
            forwardingContract != tokenMessenger && forwardingContract != tokenMessengerV2
                && forwardingContract != address(this)
        ) {
            revert InvalidForwardingContract(forwardingContract);
        }

        // Validate forwarding calldata length
        uint32 forwardingCalldataLength = hookDataView.getForwardingCalldataLength();
        if (forwardingCalldataLength < BYTES4_BYTES) {
            revert ForwardingCalldataTooShort(forwardingCalldataLength);
        }

        // Execute forwarding
        bytes memory forwardingCalldata = hookDataView.getForwardingCalldata();
        _processForwarding(forwardingContract, forwardingCalldata);
    }

    /// @notice Internal function to process forwarding operations
    /// @dev Handles different forwarding scenarios
    /// @param forwardingContract The address of the forwarding contract
    /// @param forwardingCalldata The raw forwarding calldata to validate and decode
    function _processForwarding(address forwardingContract, bytes memory forwardingCalldata) internal {
        if (forwardingContract == tokenMessenger || forwardingContract == tokenMessengerV2) {
            // CCTP forwarding
            Address.functionCall(forwardingContract, forwardingCalldata);
        } else {
            // xReserve forwarding
            _processXReserveForwarding(forwardingCalldata);
        }
    }

    /// @notice Processes xReserve forwarding calldata with validation and decoding
    /// @dev Uses TypedMemView to verify function selector and abi.decode for parameters.
    ///      Enhanced validation includes:
    ///      1. TypedMemView-based function selector verification
    ///      2. Minimum length validation for expected parameters
    ///      3. Proper slicing to remove function selector before decoding
    ///      4. Structured parameter decoding with improved error handling
    /// @param forwardingCalldata The raw forwarding calldata to validate and decode
    function _processXReserveForwarding(bytes memory forwardingCalldata) internal {
        // Use TypedMemView to verify function selector
        bytes29 calldataView = forwardingCalldata.ref(0);
        bytes4 functionSelector = bytes4(calldataView.index(0, 4));

        if (functionSelector != DepositToRemote.depositToRemote.selector) {
            revert InvalidFunctionSelector(functionSelector);
        }

        // Additional validation: ensure minimum length for expected parameters
        // depositToRemote(uint256,uint32,bytes32,address,uint256,bytes)
        // Minimum size: 4 (selector) + 5*32 (static params) + 32 (offset) + 32 (length) = 228 bytes
        if (forwardingCalldata.length < 228) {
            revert InvalidForwardingCalldata(forwardingCalldata);
        }

        // Slice calldata to remove function selector (first 4 bytes)
        bytes29 parameterSlice = calldataView.slice(4, forwardingCalldata.length - 4, 0);

        // Decode parameters directly
        (
            uint256 value,
            uint32 remoteDomain,
            bytes32 remoteRecipient,
            address localToken,
            uint256 maxFee,
            bytes memory hookData
        ) = abi.decode(parameterSlice.clone(), (uint256, uint32, bytes32, address, uint256, bytes));

        _depositToRemote(value, remoteDomain, remoteRecipient, localToken, address(this), maxFee, hookData);
    }
}
