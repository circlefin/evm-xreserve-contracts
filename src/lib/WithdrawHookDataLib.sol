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
import {BYTES4_BYTES, UINT32_BYTES, BYTES32_BYTES} from "src/common/Constants.sol";
import {
    WithdrawHookData,
    WITHDRAW_HOOK_DATA_MAGIC,
    WITHDRAW_HOOK_DATA_VERSION,
    WITHDRAW_HOOK_DATA_VERSION_OFFSET,
    WITHDRAW_HOOK_DATA_REMOTE_DOMAIN_OFFSET,
    WITHDRAW_HOOK_DATA_REMOTE_TOKEN_OFFSET,
    WITHDRAW_HOOK_DATA_REMOTE_DEPOSITOR_OFFSET,
    WITHDRAW_HOOK_DATA_FORWARDING_CONTRACT_OFFSET,
    WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET,
    WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET
} from "src/lib/WithdrawHookData.sol";

/// @title WithdrawHookDataLib
///
/// @notice Library for encoding, validating, and extracting data from `WithdrawHookData` structs
///
/// @dev Provides functions to handle withdraw hook data, using `TypedMemView` for efficient
///      memory operations
library WithdrawHookDataLib {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // --- Errors ------------------------------------------------------------------------------------------------------

    /// Thrown when casting data as a `WithdrawHookData` and the input is shorter than the expected magic length
    ///
    /// @param expectedMinimumLength   The expected minimum length of the data
    /// @param actualLength            The actual length of the data
    error WithdrawHookDataTooShort(uint256 expectedMinimumLength, uint256 actualLength);

    /// Thrown when casting data as a `WithdrawHookData` and the magic value is not the expected value
    ///
    /// @param actualMagic   The magic value found in the data
    error InvalidWithdrawHookDataMagic(bytes4 actualMagic);

    /// Thrown when validating an encoded `WithdrawHookData` and the header is shorter than expected
    ///
    /// @param expectedMinimumLength   The expected minimum length of the header
    /// @param actualLength            The actual length of the header
    error WithdrawHookDataHeaderTooShort(uint256 expectedMinimumLength, uint256 actualLength);

    /// Thrown when validating an encoded `WithdrawHookData` and the version is not the expected value
    ///
    /// @param actualVersion   The version found in the data
    error InvalidWithdrawHookDataVersion(uint32 actualVersion);

    /// Thrown when validating an encoded `WithdrawHookData` and the length of the data is different than what is
    /// implied by the forwarding calldata length
    ///
    /// @param expectedTotalLength   The expected length of the data
    /// @param actualTotalLength     The actual length of the data
    error WithdrawHookDataOverallLengthMismatch(uint256 expectedTotalLength, uint256 actualTotalLength);

    /// Thrown when the declared forwarding calldata length in the `WithdrawHookData` does not match the actual length of the
    /// forwarding calldata
    ///
    /// @param expectedForwardingCalldataLength   The expected forwarding calldata length declared in the forwarding calldata length field
    /// @param withdrawHookDataLength             The length of the withdraw hook data
    error InvalidWithdrawHookDataForwardingCalldata(
        uint256 expectedForwardingCalldataLength, uint256 withdrawHookDataLength
    );

    // --- Common utilities --------------------------------------------------------------------------------------------

    /// Converts a magic value from the byte encoding to a `TypedMemView` type
    ///
    /// @param magic   The magic value to convert
    /// @return        The `TypedMemView` type for the magic value
    function _toMemViewType(bytes4 magic) internal pure returns (uint40) {
        return uint40(uint32(magic));
    }

    // --- Casting -----------------------------------------------------------------------------------------------------

    /// Creates a typed memory view for a `WithdrawHookData`
    ///
    /// @dev Reverts if data length is less than 4
    ///
    /// @param data   The raw bytes to create a view into. Must contain at least 4 bytes.
    /// @return ref   A `TypedMemView` reference to `data`, typed according to the magic number found
    function _asWithdrawHookDataView(bytes memory data) internal pure returns (bytes29) {
        if (data.length < BYTES4_BYTES) {
            revert WithdrawHookDataTooShort(BYTES4_BYTES, data.length);
        }
        return data.ref(0).castTo(_toMemViewType(WITHDRAW_HOOK_DATA_MAGIC));
    }

    // --- Validation --------------------------------------------------------------------------------------------------

    /// Validates the structural integrity of an encoded `WithdrawHookData` memory view
    ///
    /// @notice Validation steps:
    ///   0. Magic check
    ///   1. Minimum header length check
    ///   2. Version check
    ///   3. Total length consistency check (using declared forwarding calldata length)
    ///
    /// @dev Performs structural validation on a `WithdrawHookData` view. Reverts on failure.
    ///      Assumes outer magic number check has passed (via casting).
    ///
    /// @param hookDataView   The `TypedMemView` reference to the encoded `WithdrawHookData` to validate
    function _validateWithdrawHookDataStructure(bytes29 hookDataView) internal pure {
        // 0. Magic check
        bytes4 magic = bytes4(hookDataView.index(0, BYTES4_BYTES));
        if (magic != WITHDRAW_HOOK_DATA_MAGIC) {
            revert InvalidWithdrawHookDataMagic(magic);
        }

        // 1. Minimum header length check
        if (hookDataView.len() < WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET) {
            revert WithdrawHookDataHeaderTooShort(WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET, hookDataView.len());
        }

        // 2. Version check
        uint32 version = getVersion(hookDataView);
        if (version != WITHDRAW_HOOK_DATA_VERSION) {
            revert InvalidWithdrawHookDataVersion(version);
        }

        // 3. Total length consistency check
        uint32 forwardingCalldataLength = getForwardingCalldataLength(hookDataView);
        uint256 expectedTotalLength = WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET + forwardingCalldataLength;
        if (hookDataView.len() != expectedTotalLength) {
            revert WithdrawHookDataOverallLengthMismatch(expectedTotalLength, hookDataView.len());
        }
    }

    /// Validates the structural integrity of either a `WithdrawHookData`
    ///
    /// @dev First casts the data using `_asWithdrawHookDataView`, then calls the validation function.
    ///      Reverts with specific errors if casting or validation fails.
    ///
    /// @param data   The raw bytes representing an encoded `WithdrawHookData`
    /// @return ref   A `TypedMemView` reference to `data`, typed according to the magic number found
    function _validate(bytes memory data) internal pure returns (bytes29 ref) {
        ref = _asWithdrawHookDataView(data);
        _validateWithdrawHookDataStructure(ref);
    }

    // --- Field accessors ---------------------------------------------------------------------------------------------

    /// Extract the version from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The `version` field
    function getVersion(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(WITHDRAW_HOOK_DATA_VERSION_OFFSET, UINT32_BYTES));
    }

    /// Extract the remote domain from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The `remoteDomain` field
    function getRemoteDomain(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(WITHDRAW_HOOK_DATA_REMOTE_DOMAIN_OFFSET, UINT32_BYTES));
    }

    /// Extract the remote token from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The `remoteToken` field
    function getRemoteToken(bytes29 ref) internal pure returns (bytes32) {
        return ref.index(WITHDRAW_HOOK_DATA_REMOTE_TOKEN_OFFSET, BYTES32_BYTES);
    }

    /// Extract the remote depositor from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The `remoteDepositor` field
    function getRemoteDepositor(bytes29 ref) internal pure returns (bytes32) {
        return ref.index(WITHDRAW_HOOK_DATA_REMOTE_DEPOSITOR_OFFSET, BYTES32_BYTES);
    }

    /// Extract the forwarding contract from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The `forwardingContract` field as bytes32
    function getForwardingContract(bytes29 ref) internal pure returns (bytes32) {
        return ref.index(WITHDRAW_HOOK_DATA_FORWARDING_CONTRACT_OFFSET, BYTES32_BYTES);
    }

    /// Extract the forwarding calldata length from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The forwarding calldata length
    function getForwardingCalldataLength(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET, UINT32_BYTES));
    }

    /// Extract the forwarding calldata from an encoded `WithdrawHookData`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `WithdrawHookData`
    /// @return      The `forwardingCalldata` field as bytes
    function getForwardingCalldata(bytes29 ref) internal view returns (bytes memory) {
        uint32 forwardingCalldataLength = getForwardingCalldataLength(ref);
        bytes29 forwardingCalldataSlice =
            ref.slice(WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET, forwardingCalldataLength, 0);

        // Verify forwarding calldata view is valid. A NULL view means the actual length differs from the declared length in the
        // forwarding calldata length field and would overrun the allocated memory. This check should be unreachable since
        // validation of withdraw hook data structure happens before calling this function, but included for completeness.
        if (forwardingCalldataSlice == TypedMemView.NULL) {
            revert InvalidWithdrawHookDataForwardingCalldata(forwardingCalldataLength, ref.len());
        }

        return forwardingCalldataSlice.clone();
    }

    // --- Decoding ----------------------------------------------------------------------------------------------------

    /// Decode bytes into a `WithdrawHookData` struct
    ///
    /// @param data   The encoded bytes to decode
    /// @return       The decoded `WithdrawHookData` struct
    function decodeWithdrawHookData(bytes memory data) internal view returns (WithdrawHookData memory) {
        bytes29 ref = _validate(data);

        return WithdrawHookData({
            version: getVersion(ref),
            remoteDomain: getRemoteDomain(ref),
            remoteToken: getRemoteToken(ref),
            remoteDepositor: getRemoteDepositor(ref),
            forwardingContract: getForwardingContract(ref),
            forwardingCalldata: getForwardingCalldata(ref)
        });
    }

    // --- Encoding ----------------------------------------------------------------------------------------------------

    /// Encode a `WithdrawHookData` struct into bytes
    ///
    /// @param hookData   The `WithdrawHookData` to encode
    /// @return           The encoded bytes
    function encodeWithdrawHookData(WithdrawHookData memory hookData) internal pure returns (bytes memory) {
        return abi.encodePacked(
            WITHDRAW_HOOK_DATA_MAGIC,
            hookData.version,
            hookData.remoteDomain,
            hookData.remoteToken,
            hookData.remoteDepositor,
            hookData.forwardingContract,
            uint32(hookData.forwardingCalldata.length),
            hookData.forwardingCalldata
        );
    }
}
