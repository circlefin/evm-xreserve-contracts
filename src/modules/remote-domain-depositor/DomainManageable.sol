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

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {UnauthorizedCaller} from "../../common/Errors.sol";

/// @title DomainManageable
/// @notice Defines domain manager and domain pauser roles that can control domain-specific configurations
contract DomainManageable is Initializable, Ownable2StepUpgradeable {
    // ============ Modifiers ============

    /// @notice Restricts the caller to the domain manager role, reverting with an error for other callers
    modifier onlyDomainManager() {
        if (msg.sender != domainManager()) {
            revert UnauthorizedCaller();
        }
        _;
    }
    // ============ Events ============

    /// @notice Emitted when the domain manager address is updated
    /// @param oldDomainManager The previous domain manager address
    /// @param newDomainManager The new domain manager address
    event DomainManagerUpdated(address indexed oldDomainManager, address indexed newDomainManager);

    /// @notice Emitted when the domain pauser address is updated
    /// @param oldDomainPauser The previous domain pauser address
    /// @param newDomainPauser The new domain pauser address
    event DomainPauserUpdated(address indexed oldDomainPauser, address indexed newDomainPauser);

    // ============ Initialization ============

    /// @notice Initializes the `domainManager` and `domainPauser` roles
    /// @param domainManager_ The initial domain manager address
    /// @param domainPauser_ The initial domain pauser address
    function __DomainManageable_init(address domainManager_, address domainPauser_) internal onlyInitializing {
        _setDomainManager(domainManager_);
        _setDomainPauser(domainPauser_);
    }

    // ============ View Functions ============

    /// @notice The address with the `domainManager` role
    /// @return The address of the domain manager
    function domainManager() public view returns (address) {
        return DomainManageableStorage.get().domainManager;
    }

    /// @notice The address with the `domainPauser` role
    /// @return The address of the domain pauser
    function domainPauser() external view returns (address) {
        return DomainManageableStorage.get().domainPauser;
    }

    // ============ External Functions ============

    /// @notice Updates the domain manager address
    /// @dev This function allows the owner to update the domain manager address,
    ///      granting or revoking the domain manager role
    /// @dev This function should be idempotent
    /// @param domainManager_ The new domain manager address
    function updateDomainManager(address domainManager_) external onlyOwner {
        _setDomainManager(domainManager_);
    }

    /// @notice Updates the domain pauser address
    /// @dev This function allows the domain manager to update the domain pauser address,
    ///      granting or revoking the domain pauser role
    /// @dev This function should be idempotent
    /// @param domainPauser_ The new domain pauser address
    function updateDomainPauser(address domainPauser_) external onlyDomainManager {
        _setDomainPauser(domainPauser_);
    }

    // ============ Internal Functions ============

    /// @notice Sets the address that is allowed to manage domains
    /// @param newDomainManager The new domain manager address
    function _setDomainManager(address newDomainManager) private {
        AddressLib._checkNotZeroAddress(newDomainManager);

        address oldDomainManager = DomainManageableStorage.get().domainManager;
        DomainManageableStorage.get().domainManager = newDomainManager;
        emit DomainManagerUpdated(oldDomainManager, newDomainManager);
    }

    /// @notice Sets the address that is allowed to pause domain-specific operations
    /// @param newDomainPauser The new domain pauser address
    function _setDomainPauser(address newDomainPauser) private {
        AddressLib._checkNotZeroAddress(newDomainPauser);

        address oldDomainPauser = DomainManageableStorage.get().domainPauser;
        DomainManageableStorage.get().domainPauser = newDomainPauser;
        emit DomainPauserUpdated(oldDomainPauser, newDomainPauser);
    }
}

/// @title DomainManageableStorage
/// @notice Implements the EIP-7201 storage pattern for the `DomainManageable` module
library DomainManageableStorage {
    /// @custom:storage-location erc7201:circle.xReserve.DomainManageable
    struct Data {
        /// The manager address responsible for maintaining various domain-specific configurations
        address domainManager;
        /// The pauser address responsible for pausing domain-specific operations
        address domainPauser;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.DomainManageable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x6f2597a7d01bcf835242df16a0d751446053c991498e57422670c735c6c29600;

    /// @notice EIP-7201 getter for the storage slot
    /// @return $ The storage struct for the `DomainManageable` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
