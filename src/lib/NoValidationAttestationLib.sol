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

import {
    ATTESTATION_MAGIC,
    ATTESTATION_SET_MAGIC,
    ATTESTATION_TRANSFER_SPEC_LENGTH_OFFSET,
    ATTESTATION_TRANSFER_SPEC_OFFSET,
    ATTESTATION_SET_NUM_ATTESTATIONS_OFFSET,
    ATTESTATION_SET_ATTESTATIONS_OFFSET
} from "@gateway/src/lib/Attestations.sol";
import {Cursor} from "@gateway/src/lib/Cursor.sol";
import {TRANSFER_SPEC_MAGIC} from "@gateway/src/lib/TransferSpec.sol";
import {TransferSpecLib, BYTES4_BYTES, UINT32_BYTES} from "@gateway/src/lib/TransferSpecLib.sol";
import {TypedMemView} from "@memview-sol/TypedMemView.sol";

/// @title NoValidationAttestationLib
/// @notice Identical to Gateway's AttestationLib but skips validation for gas optimization
/// @dev Only use this when the attestation payload has already been validated (e.g., by gatewayMint)
///      This library assumes the input data is well-formed and trusted
library NoValidationAttestationLib {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    /// Checks whether the provided `bytes29` reference is an `AttestationSet`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `Attestation` or `AttestationSet`
    /// @return      `true` if the provided `bytes29` reference is an `AttestationSet`, `false` otherwise
    function _isSet(bytes29 ref) private pure returns (bool) {
        return ref.index(0, BYTES4_BYTES) == ATTESTATION_SET_MAGIC;
    }

    // --- Casting -----------------------------------------------------------------------------------------------------

    /// Creates a typed memory view for an `Attestation` or `AttestationSet`
    ///
    /// @dev Interprets data as `Attestation` if magic matches; otherwise treats as `AttestationSet`
    /// @dev Reverts if data length is less than 4
    ///
    /// @param data   The raw bytes to create a view into. Must contain at least 4 bytes.
    /// @return ref   A `TypedMemView` reference to `data`, typed according to the magic number found
    function _asAttestationOrSetView(bytes memory data) internal pure returns (bytes29 ref) {
        bytes29 initialView = data.ref(0);

        if (_isSet(initialView)) {
            ref = initialView.castTo(TransferSpecLib._toMemViewType(ATTESTATION_SET_MAGIC));
        } else {
            ref = initialView.castTo(TransferSpecLib._toMemViewType(ATTESTATION_MAGIC));
        }
    }

    // --- Iteration ---------------------------------------------------------------------------------------------------

    /// Returns a cursor that can uniformly iterate over any attestations it contains
    ///
    /// @dev For a single `Attestation`, the cursor will yield that single element. For an `AttestationSet`,
    ///      it iterates through each contained `Attestation`. Sets the 'done' flag immediately if the set
    ///      contains zero attestations.
    /// @dev ASSUMES the input data has already been validated (e.g., by gatewayMint)
    ///
    /// @param data   The raw bytes representing either an encoded `Attestation` or `AttestationSet`
    /// @return c     An initialized `Cursor` struct
    function cursor(bytes memory data) internal pure returns (Cursor memory c) {
        bytes29 ref = _asAttestationOrSetView(data);
        c.memView = ref;
        c.index = 0;

        if (!_isSet(ref)) {
            c.offset = 0;
            c.numElements = 1;
            c.done = false; // There's one element to process
            return c;
        }

        uint32 numAttestations = getNumAttestations(ref);
        c.offset = ATTESTATION_SET_ATTESTATIONS_OFFSET;
        c.numElements = numAttestations;
        c.done = (numAttestations == 0); // If the set is empty, the cursor is immediately done
    }

    /// Gets the `TypedMemView` reference to the next element and advances the cursor
    ///
    /// @dev Updates the cursor's internal state (`offset`, `index`, `done`). Reverts with `CursorOutOfBounds` if called
    ///      when no elements are remaining.
    ///
    /// @param c      The `Cursor` struct
    /// @return ref   The element the cursor was pointing at immediately before this function was called
    function next(Cursor memory c) internal pure returns (bytes29 ref) {
        if (c.done) {
            revert TransferSpecLib.CursorOutOfBounds();
        }

        uint32 currentSpecLength =
            uint32(c.memView.indexUint(c.offset + ATTESTATION_TRANSFER_SPEC_LENGTH_OFFSET, UINT32_BYTES));
        uint256 currentAttestationTotalLength = ATTESTATION_TRANSFER_SPEC_OFFSET + currentSpecLength;

        ref =
            c.memView.slice(c.offset, currentAttestationTotalLength, TransferSpecLib._toMemViewType(ATTESTATION_MAGIC));

        c.offset += currentAttestationTotalLength;
        c.index++;

        if (c.index >= c.numElements) {
            c.done = true;
        }

        return ref;
    }

    // --- Field accessors ---------------------------------------------------------------------------------------------

    /// Extract the transfer spec length from an encoded `Attestation`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `Attestation`
    /// @return      The transfer spec length
    function getTransferSpecLength(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(ATTESTATION_TRANSFER_SPEC_LENGTH_OFFSET, UINT32_BYTES));
    }

    /// Extract the transfer spec from an encoded `Attestation` without validation
    ///
    /// @dev ASSUMES the attestation structure is valid
    /// @param ref   The `TypedMemView` reference to the encoded `Attestation`
    /// @return      A `TypedMemView` reference to the `TransferSpec` portion
    function getTransferSpec(bytes29 ref) internal pure returns (bytes29) {
        uint32 specLength = getTransferSpecLength(ref);
        return
            ref.slice(ATTESTATION_TRANSFER_SPEC_OFFSET, specLength, TransferSpecLib._toMemViewType(TRANSFER_SPEC_MAGIC));
    }

    /// Extract the number of attestations from an encoded `AttestationSet`
    ///
    /// @param ref   The `TypedMemView` reference to the encoded `AttestationSet`
    /// @return      The number of attestations in the set
    function getNumAttestations(bytes29 ref) internal pure returns (uint32) {
        return uint32(ref.indexUint(ATTESTATION_SET_NUM_ATTESTATIONS_OFFSET, UINT32_BYTES));
    }
}
