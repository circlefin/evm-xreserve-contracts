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

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Attestable} from "./modules/remote-domain-depositor/Attestable.sol";

/// @title RemoteDomainDepositor
/// @notice Contract for managing deposits from remote domains and minting tokens via gateway
contract RemoteDomainDepositor is UUPSUpgradeable, Attestable {
    /// @notice Constructor for the RemoteDomainDepositor contract
    /// @dev Disables initializers to prevent the implementation contract from being initialized
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the RemoteDomainDepositor contract
    /// @param domainManager_ The address of the domain manager
    /// @param domainPauser_ The address of the domain pauser
    /// @param attesters_ The addresses of the attesters
    /// @param signatureThreshold_ The threshold of signatures required to attest to a message
    /// @param persistentSignatureBufferDelayBlocks_ The delay in blocks for the persistent signature buffer
    function initialize(
        address domainManager_,
        address domainPauser_,
        address[] memory attesters_,
        uint256 signatureThreshold_,
        uint256 persistentSignatureBufferDelayBlocks_
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __Attestable_init(attesters_, signatureThreshold_, persistentSignatureBufferDelayBlocks_);
        __DomainManageable_init(domainManager_, domainPauser_);
    }

    /// @notice Authorizes the upgrade of the RemoteDomainDepositor contract
    /// @dev This function is used to authorize the upgrade of the RemoteDomainDepositor contract
    /// @param _newImplementation The address of the new implementation
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
