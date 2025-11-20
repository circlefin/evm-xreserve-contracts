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

import {TypedMemView} from "@memview-sol/TypedMemView.sol";
import {BYTES4_BYTES, UINT32_BYTES, BYTES32_BYTES, UINT256_BYTES} from "src/common/Constants.sol";
import {
    DepositIntent,
    DEPOSIT_INTENT_MAGIC,
    DEPOSIT_INTENT_VERSION,
    DEPOSIT_INTENT_MAGIC_OFFSET,
    DEPOSIT_INTENT_VERSION_OFFSET,
    DEPOSIT_INTENT_AMOUNT_OFFSET,
    DEPOSIT_INTENT_REMOTE_DOMAIN_OFFSET,
    DEPOSIT_INTENT_REMOTE_TOKEN_OFFSET,
    DEPOSIT_INTENT_REMOTE_RECIPIENT_OFFSET,
    DEPOSIT_INTENT_LOCAL_TOKEN_OFFSET,
    DEPOSIT_INTENT_LOCAL_DEPOSITOR_OFFSET,
    DEPOSIT_INTENT_MAX_FEE_OFFSET,
    DEPOSIT_INTENT_NONCE_OFFSET,
    DEPOSIT_INTENT_HOOK_DATA_LENGTH_OFFSET,
    DEPOSIT_INTENT_HOOK_DATA_OFFSET
} from "src/lib/DepositIntent.sol";
import {AddressLib} from "./AddressLib.sol";

/// @title DepositIntentLib
///
/// @notice Library for encoding, validating, and decoding `DepositIntent` struct
///
/// @dev Provides functions to handle single deposit intent, using `TypedMemView` for efficient memory operations
library DepositIntentLib {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // --- DepositIntent errors ----------------------------------------------------------------------------------------

    /// Thrown when validating an encoded `DepositIntent` and the version is not the expected value (1)
    ///
    /// @param version   The version found in the data
    error InvalidDepositIntentVersion(uint32 version);

    /// Thrown when validating an encoded `DepositIntent` and the amount is zero
    ///
    /// @param amount   The amount found in the data
    error InvalidDepositAmount(uint256 amount);

    /// Thrown when casting data as a deposit payload and the input is shorter than the
    /// expected magic length
    ///
    /// @param expected   The expected minimum length of the data
    /// @param actual     The actual length of the data
    error DepositPayloadDataTooShort(uint256 expected, uint256 actual);

    /// Thrown when casting data as a deposit payload and the magic value is not an expected
    /// value
    ///
    /// @param magic   The magic value found in the data
    error InvalidDepositPayloadMagic(bytes4 magic);

    /// Thrown when validating an encoded deposit payload and the header is shorter than expected
    ///
    /// @param expected   The expected minimum length of the header
    /// @param actual     The actual length of the header
    error DepositPayloadHeaderTooShort(uint256 expected, uint256 actual);

    /// Thrown when validating an encoded deposit payload and the length of the data is different than what is implied
    /// by the embedded hook data length
    ///
    /// @param expected   The expected length of the data
    /// @param actual     The actual length of the data
    error DepositPayloadOverallLengthMismatch(uint256 expected, uint256 actual);

    /// Thrown when the declared hook data length in the `DepositIntent` does not match the actual length of the hook
    /// data
    ///
    /// @param expectedHookDataLength   The expected hook data length declared in the hook data length field
    /// @param depositIntentLength      The length of the deposit intent
    error InvalidDepositIntentHookData(uint256 expectedHookDataLength, uint256 depositIntentLength);

    // --- Utilities ---------------------------------------------------------------------------------------------------

    /// Convert a magic bytes4 value to a TypedMemView type
    ///
    /// @param magic   The magic bytes4 value
    /// @return        The TypedMemView type for the magic value
    function _toMemViewType(bytes4 magic) private pure returns (uint40) {
        return uint40(uint32(magic));
    }

    /// Creates a typed memory view for a `DepositIntent`
    ///
    /// @dev Checks for `DepositIntent` magic
    /// @dev Reverts with `InvalidDepositPayloadMagic` if the magic number is not present
    /// @dev Reverts if data length is less than 4
    ///
    /// @param data   The raw bytes to create a view into. Must contain at least 4 bytes.
    /// @return ref   A `TypedMemView` reference to `data`, typed according to the magic number found
    function _asIntentView(bytes memory data) internal pure returns (bytes29 ref) {
        if (data.length < BYTES4_BYTES) {
            revert DepositPayloadDataTooShort(BYTES4_BYTES, data.length);
        }

        bytes29 initialView = data.ref(0);
        bytes4 magic = bytes4(initialView.index(DEPOSIT_INTENT_MAGIC_OFFSET, BYTES4_BYTES));

        if (magic == DEPOSIT_INTENT_MAGIC) {
            ref = initialView.castTo(_toMemViewType(DEPOSIT_INTENT_MAGIC));
        } else {
            revert InvalidDepositPayloadMagic(magic);
        }
    }

    // --- Validation --------------------------------------------------------------------------------------------------

    /// Validates the structural integrity of an encoded `DepositIntent` memory view
    ///
    /// @notice Validation steps:
    ///   1. Minimum header length check
    ///   2. Total length consistency check (using declared hook data length)
    ///
    /// @dev Performs structural validation on a `DepositIntent` view. Reverts on failure. Assumes outer magic number
    ///      check has passed (via casting).
    ///
    /// @param intentView   The `TypedMemView` reference to the encoded `DepositIntent` to validate
    function _validateDepositIntentOuterStructure(bytes29 intentView) private pure {
        // 1. Minimum header length check
        if (intentView.len() < DEPOSIT_INTENT_HOOK_DATA_OFFSET) {
            revert DepositPayloadHeaderTooShort(DEPOSIT_INTENT_HOOK_DATA_OFFSET, intentView.len());
        }

        // 2. Total length consistency check
        uint32 hookDataLength = getHookDataLength(intentView);
        uint256 expectedIntentLength = DEPOSIT_INTENT_HOOK_DATA_OFFSET + hookDataLength;
        if (intentView.len() != expectedIntentLength) {
            revert DepositPayloadOverallLengthMismatch(expectedIntentLength, intentView.len());
        }
    }

    /// Validates the full structural integrity of a `DepositIntent` view
    ///
    /// @notice Validation includes:
    ///   1. Wrapper structure validation (header length, total length consistency).
    ///   2. Version validation (must be 1).
    ///   3. Address validation (non-zero addresses).
    ///
    /// @dev Performs structural validation on a `DepositIntent` view. Reverts on failure. Assumes the view has the
    ///      correct `DepositIntent` magic number (e.g., validated by `_asIntentView`).
    ///
    /// @param intentView   The `TypedMemView` reference to the encoded `DepositIntent` to validate
    function _validateDepositIntent(bytes29 intentView) internal pure {
        _validateDepositIntentOuterStructure(intentView);

        // Validate version
        uint32 version = getVersion(intentView);
        if (version != DEPOSIT_INTENT_VERSION) {
            revert InvalidDepositIntentVersion(version);
        }

        // Validate addresses are non-zero
        bytes32 localToken = getLocalToken(intentView);
        bytes32 localDepositor = getLocalDepositor(intentView);
        AddressLib._checkNotZeroBytes32(localToken);
        AddressLib._checkNotZeroBytes32(localDepositor);

        // Validate amount is non-zero
        uint256 amount = getAmount(intentView);
        if (amount == 0) {
            revert InvalidDepositAmount(amount);
        }
    }

    // --- Field accessors ---------------------------------------------------------------------------------------------

    /// Extract the version from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The version number
    function getVersion(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(DEPOSIT_INTENT_VERSION_OFFSET, UINT32_BYTES));
    }

    /// Extract the amount from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The amount of tokens to deposit
    function getAmount(bytes29 ref) internal pure returns (uint256) {
        return ref.indexUint(DEPOSIT_INTENT_AMOUNT_OFFSET, UINT256_BYTES);
    }

    /// Extract the remote domain from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The remote domain identifier
    function getRemoteDomain(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(DEPOSIT_INTENT_REMOTE_DOMAIN_OFFSET, UINT32_BYTES));
    }

    /// Extract the remote token from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The remote token address
    function getRemoteToken(bytes29 ref) internal pure returns (bytes32) {
        return bytes32(ref.index(DEPOSIT_INTENT_REMOTE_TOKEN_OFFSET, BYTES32_BYTES));
    }

    /// Extract the remote recipient from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The remote recipient address
    function getRemoteRecipient(bytes29 ref) internal pure returns (bytes32) {
        return bytes32(ref.index(DEPOSIT_INTENT_REMOTE_RECIPIENT_OFFSET, BYTES32_BYTES));
    }

    /// Extract the local token from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The local token as bytes32
    function getLocalToken(bytes29 ref) internal pure returns (bytes32) {
        return bytes32(ref.index(DEPOSIT_INTENT_LOCAL_TOKEN_OFFSET, BYTES32_BYTES));
    }

    /// Extract the local depositor from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The local depositor as bytes32
    function getLocalDepositor(bytes29 ref) internal pure returns (bytes32) {
        return bytes32(ref.index(DEPOSIT_INTENT_LOCAL_DEPOSITOR_OFFSET, BYTES32_BYTES));
    }

    /// Extract the maximum fee from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The maximum fee amount
    function getMaxFee(bytes29 ref) internal pure returns (uint256) {
        return ref.indexUint(DEPOSIT_INTENT_MAX_FEE_OFFSET, UINT256_BYTES);
    }

    /// Extract the nonce from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The nonce for replay protection
    function getNonce(bytes29 ref) internal pure returns (bytes32) {
        return bytes32(ref.index(DEPOSIT_INTENT_NONCE_OFFSET, BYTES32_BYTES));
    }

    /// Extract the hook data length from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The length of the hook data in bytes
    function getHookDataLength(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(DEPOSIT_INTENT_HOOK_DATA_LENGTH_OFFSET, UINT32_BYTES));
    }

    /// Extract the hook data from an encoded `DepositIntent`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `DepositIntent`
    /// @return      The hook data as a `bytes memory` copy
    function getHookData(bytes29 ref) internal view returns (bytes memory) {
        uint32 hookDataLength = getHookDataLength(ref);
        bytes29 hookDataView = ref.slice(DEPOSIT_INTENT_HOOK_DATA_OFFSET, hookDataLength, 0);

        // Verify hook data view is valid. A NULL view means the actual length differs from the declared length in the
        // hook data length field and would overrun the allocated memory. This check should be unreachable since
        // validation of deposit intent structure happens before calling this function, but included for completeness.
        if (hookDataView == TypedMemView.NULL) {
            revert InvalidDepositIntentHookData(hookDataLength, ref.len());
        }

        return hookDataView.clone();
    }

    // --- Decoding ----------------------------------------------------------------------------------------------------

    /// Decode a `DepositIntent` from encoded bytes
    ///
    /// @param data   The encoded bytes to decode
    /// @return       The decoded `DepositIntent` struct
    function decodeDepositIntent(bytes memory data) internal view returns (DepositIntent memory) {
        bytes29 intentView = _asIntentView(data);
        _validateDepositIntent(intentView);

        // Extract all fields
        return DepositIntent({
            version: getVersion(intentView),
            amount: getAmount(intentView),
            remoteDomain: getRemoteDomain(intentView),
            remoteToken: getRemoteToken(intentView),
            remoteRecipient: getRemoteRecipient(intentView),
            localToken: getLocalToken(intentView),
            localDepositor: getLocalDepositor(intentView),
            maxFee: getMaxFee(intentView),
            nonce: getNonce(intentView),
            hookData: getHookData(intentView)
        });
    }

    // --- Encoding ----------------------------------------------------------------------------------------------------

    /// Encode a `DepositIntent` struct into bytes
    ///
    /// @param intent   The `DepositIntent` to encode
    /// @return         The encoded bytes
    function encodeDepositIntent(DepositIntent memory intent) internal pure returns (bytes memory) {
        return abi.encodePacked(
            DEPOSIT_INTENT_MAGIC,
            intent.version,
            intent.amount,
            intent.remoteDomain,
            intent.remoteToken,
            intent.remoteRecipient,
            intent.localToken,
            intent.localDepositor,
            intent.maxFee,
            intent.nonce,
            uint32(intent.hookData.length),
            intent.hookData
        );
    }
}
