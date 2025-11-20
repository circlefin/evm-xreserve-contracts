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
import {UnauthorizedCaller, ZeroAddress} from "../../common/Errors.sol";

/// @title Blocklistable
/// @notice Contract for managing blocklisted addresses across different remote domains
contract Blocklistable is Initializable, Ownable2StepUpgradeable {
    // ============ Events ============

    /// @notice Emitted when an address is blocklisted
    event Blocklisted(uint32 indexed remoteDomain, bytes32 indexed remoteAddress);

    /// @notice Emitted when an address is unblocklisted
    event Unblocklisted(uint32 indexed remoteDomain, bytes32 indexed remoteAddress);

    /// @notice Emitted when the blocklister address is updated
    event BlocklisterUpdated(address indexed oldBlocklister, address indexed newBlocklister);

    // ============ Errors ============

    /// @notice Thrown when an address is blocked from interacting with the contract
    error AccountBlocklisted(uint32 remoteDomain, bytes32 remoteAddress);

    // ============ Initialization ============

    /// @notice Initializes the `blocklister` role
    /// @param blocklister_ The initial blocklister address
    function __Blocklistable_init(address blocklister_) internal onlyInitializing {
        // Note: oldBlocklister may be non-zero during upgrades that re-run this initializer
        // via a reinitializer flow. Do not assume it is always zero; emit the previous value
        // in the event (see helper function body) for accurate auditability across initialization
        // and reinitialization.
        _setBlocklister(blocklister_);
    }

    // ============ Modifiers ============

    /// @notice Restricts the caller to the `blocklister` role, reverting with an error for other callers
    modifier onlyBlocklister() {
        if (msg.sender != BlocklistableStorage.get().blocklister) {
            revert UnauthorizedCaller();
        }
        _;
    }

    // ============ View Functions ============

    /// @notice Whether or not a given address is blocked from interacting with the contract
    /// @param remoteDomain The remote domain to check
    /// @param remoteAddress The remote address to check
    /// @return `true` if the address is blocklisted, `false` otherwise
    function isBlocklisted(uint32 remoteDomain, bytes32 remoteAddress) public view returns (bool) {
        return BlocklistableStorage.get().blocklistMapping[remoteDomain][remoteAddress];
    }

    /// @notice The address with the `blocklister` role that can modify the blocklist
    /// @return The address of the blocklister
    function blocklister() external view returns (address) {
        return BlocklistableStorage.get().blocklister;
    }

    // ============ External Functions ============

    /// @notice Blocklists an address on a specific remote domain
    /// @dev This function allows the blocklister to blocklist an address on a remote domain,
    ///      preventing it from participating in cross-domain operations
    /// @dev This function should be idempotent
    /// @param remoteDomain The domain identifier where the address should be blocklisted
    /// @param remoteAddress The address to blocklist as bytes32 on the specified remote domain
    function blocklist(uint32 remoteDomain, bytes32 remoteAddress) external onlyBlocklister {
        _setBlocklistState(remoteDomain, remoteAddress, true);
        emit Blocklisted(remoteDomain, remoteAddress);
    }

    /// @notice Unblocklists an address on a specific remote domain
    /// @dev This function allows the blocklister to unblocklist an address on a remote domain,
    ///      allowing it to participate in cross-domain operations
    /// @dev This function should be idempotent
    /// @param remoteDomain The domain identifier where the address should be unblocklisted
    /// @param remoteAddress The address to unblocklist as bytes32 on the specified remote domain
    function unblocklist(uint32 remoteDomain, bytes32 remoteAddress) external onlyBlocklister {
        _setBlocklistState(remoteDomain, remoteAddress, false);
        emit Unblocklisted(remoteDomain, remoteAddress);
    }

    /// @notice Updates the blocklister address
    /// @dev This function allows the owner to update the blocklister address,
    ///      granting or revoking the blocklister role
    /// @dev This function should be idempotent
    /// @param blocklister_ The new blocklister address
    function updateBlocklister(address blocklister_) external onlyOwner {
        _setBlocklister(blocklister_);
    }

    // ============ Internal Functions ============

    /// @notice Reverts if the given address is blocklisted
    /// @param remoteDomain The remote domain to check
    /// @param remoteAddress The remote address to check
    function _ensureNotBlocklisted(uint32 remoteDomain, bytes32 remoteAddress) internal view {
        if (isBlocklisted(remoteDomain, remoteAddress)) {
            revert AccountBlocklisted(remoteDomain, remoteAddress);
        }
    }

    /// @notice Sets the blocklist status of an address
    /// @param remoteDomain The remote domain
    /// @param remoteAddress The remote address to set the blocklist status for
    /// @param blocked Whether or not the address should be blocklisted
    function _setBlocklistState(uint32 remoteDomain, bytes32 remoteAddress, bool blocked) internal {
        BlocklistableStorage.get().blocklistMapping[remoteDomain][remoteAddress] = blocked;
    }

    /// @notice Sets the address that is allowed to modify the blocklist
    /// @param newBlocklister The new blocklister address
    function _setBlocklister(address newBlocklister) internal {
        if (newBlocklister == address(0)) {
            revert ZeroAddress();
        }
        address oldBlocklister = BlocklistableStorage.get().blocklister;
        BlocklistableStorage.get().blocklister = newBlocklister;
        emit BlocklisterUpdated(oldBlocklister, newBlocklister);
    }
}

/// @title BlocklistableStorage
/// @notice Implements the EIP-7201 storage pattern for the `Blocklistable` module
library BlocklistableStorage {
    /// @custom:storage-location erc7201:circle.xReserve.Blocklistable
    struct Data {
        /// Mapping of remote domain to remote address to their blocklist status
        mapping(uint32 remoteDomain => mapping(bytes32 remoteAddress => bool blocklisted)) blocklistMapping;
        /// The address that is allowed to manage the blocklist
        address blocklister;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Blocklistable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x0d198be05a52a5c37edefdb6959d3bbd2cec5830bf94c2b41b8b04fa134fb900;

    /// @notice EIP-7201 getter for the storage slot
    /// @return $ The storage struct for the `Blocklistable` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
