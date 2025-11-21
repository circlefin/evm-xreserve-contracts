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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Domain
///
/// @notice Stores the operator-issued domain identifier of the current chain
contract Domain is Initializable {
    /// @notice Initializes the domain
    /// @param domain_   The operator-issued identifier for the current chain
    function __Domain_init(uint32 domain_) internal onlyInitializing {
        DomainStorage.get().domain = domain_;
    }

    /// @notice The domain assigned to the chain this contract is deployed on
    /// @return   The operator-issued identifier for the current chain
    function domain() external view returns (uint32) {
        return DomainStorage.get().domain;
    }
}

/// @title DomainStorage
///
/// @notice Implements the EIP-7201 storage pattern for the `Domain` module
library DomainStorage {
    /// @custom:storage-location erc7201:circle.xReserve.Domain
    struct Data {
        /// An operator-issued identifier for the current chain (does not match the chainId)
        uint32 domain;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Domain"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x8fadb1ee53eb9315f14ed344b360999a6bf6db266066acf6d0a7a70190dedf00;

    /// @notice EIP-7201 getter for the storage slot
    /// @return $   The storage struct for the `Domain` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
