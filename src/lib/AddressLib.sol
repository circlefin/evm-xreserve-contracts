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

import {ZeroAddress, ZeroBytes32, InvalidAddressPadding} from "./../common/Errors.sol";

/// @title AddressLib
/// @notice A collection of utilities for validating and converting addresses
library AddressLib {
    /// @notice Validates that an address is not the zero address, reverting if it is
    /// @param addr   The `address` being checked
    function _checkNotZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
    }

    /// @notice Validates that a bytes32 is not the zero bytes32, reverting if it is
    /// @param buf   The `bytes32` being checked
    function _checkNotZeroBytes32(bytes32 buf) internal pure {
        if (buf == bytes32(0)) {
            revert ZeroBytes32();
        }
    }

    /// @notice Safely casts `bytes32` to an `address` with zero padding validation
    /// @dev Extracts the rightmost 20 bytes of the bytes32 value after verifying
    ///      that the upper 12 bytes are zero. This ensures the bytes32 represents
    ///      a properly formatted address (right-aligned with zero padding).
    ///      Example: `bytes32(0x00000000000000000000000011...11)` becomes `address(0x11...11)`.
    ///      Reverts if upper 12 bytes contain non-zero values.
    ///
    /// @param buf   The `bytes32` to cast (must have zero upper 12 bytes)
    /// @return      The `address` represented by the lower 20 bytes of `buf`
    function _bytes32ToAddressSafe(bytes32 buf) internal pure returns (address) {
        // Check that the upper 12 bytes (96 bits) are zero by right-shifting by 160 bits.
        // If the result is non-zero, it means there were bits set in the upper 12 bytes.
        if (uint256(buf) >> 160 != 0) {
            revert InvalidAddressPadding(buf);
        }
        return address(uint160(uint256(buf)));
    }
}
