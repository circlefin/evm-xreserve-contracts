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
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AddressLib} from "src/lib/AddressLib.sol";

/// @title Upgradeable Placeholder
/// @notice A no-op, upgradeable implementation contract for UUPS proxies. Intended to be deployed before the xReserve implementation.
contract UpgradeablePlaceholder is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
    /// @notice Constructor for the UpgradeablePlaceholder contract
    /// @dev Disables initializers to prevent the implementation contract from being initialized
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the given owner address
    /// @param newOwner   The address of the new owner
    function initialize(address newOwner) external initializer {
        // Ensure that the owner address is not the zero address
        AddressLib._checkNotZeroAddress(newOwner);

        __UUPSUpgradeable_init();
        __Ownable_init(newOwner);
        __Ownable2Step_init();
    }

    /// @notice Implements the UUPS upgrade pattern by restricting upgrades to the owner
    /// @param _newImplementation The address of the new implementation
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
