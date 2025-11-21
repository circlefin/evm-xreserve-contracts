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

/// @title IRemoteDomainDepositor
/// @notice Interface for RemoteDomainDepositor contract
/// @dev This interface is used to avoid importing the entire RemoteDomainDepositor bytecode
interface IRemoteDomainDepositor {
    /// @notice Initializes the RemoteDomainDepositor proxy
    /// @param domainManager The address of the domain manager
    /// @param domainPauser The address of the domain pauser
    /// @param attesters Array of attester addresses
    /// @param signatureThreshold Minimum number of signatures required
    /// @param persistentSignatureBufferDelayBlocks The number of blocks to delay when disabling attesters and increasing signature thresholds
    function initialize(
        address domainManager,
        address domainPauser,
        address[] calldata attesters,
        uint256 signatureThreshold,
        uint256 persistentSignatureBufferDelayBlocks
    ) external;

    /// @notice Updates the domain manager address
    /// @dev This function allows the owner to update the domain manager address,
    ///      granting or revoking the domain manager role.
    /// @param domainManager The new domain manager address
    function updateDomainManager(address domainManager) external;

    /// @notice Sets the delay in blocks for disabling attesters and increasing signature thresholds
    /// @dev Only callable by owner. This function allows the owner to update the persistent signature buffer delay.
    /// @param newDelay The new delay in blocks
    function setPersistentSignatureBufferDelay(uint256 newDelay) external;

    /// @notice Returns the address that may pause/unpause deposits for this remote domain
    /// @return The domain pauser address for this remote domain
    function domainPauser() external view returns (address);
}
