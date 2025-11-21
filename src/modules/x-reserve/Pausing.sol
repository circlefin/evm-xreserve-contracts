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
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UnauthorizedCaller, ZeroAddress} from "../../common/Errors.sol";

/// @title Pausing
///
/// @notice Defines a `pauser` role that may pause and unpause the contract globally and specific domains
contract Pausing is Initializable, Ownable2StepUpgradeable, PausableUpgradeable {
    /// Emitted when the pauser address is updated
    ///
    /// @param oldPauser   The old pauser address
    /// @param newPauser   The new pauser address
    event PauserUpdated(address indexed oldPauser, address indexed newPauser);

    /// Emitted when a domain's pause state is updated
    ///
    /// @param domain             The domain that was updated
    /// @param depositsPaused     Whether deposits are paused for this domain
    /// @param withdrawalsPaused  Whether withdrawals are paused for this domain
    event DomainPauseStateUpdated(uint32 indexed domain, bool depositsPaused, bool withdrawalsPaused);

    /// Thrown when deposits are attempted on a domain with deposits paused
    ///
    /// @param domain   The domain with deposits paused
    error DomainDepositsPaused(uint32 domain);

    /// Thrown when withdrawals are attempted on a domain with withdrawals paused
    ///
    /// @param domain   The domain with withdrawals paused
    error DomainWithdrawalsPaused(uint32 domain);

    /// @notice Initializes the underlying `Pausable` contract and the `pauser` role
    /// @dev All domains start with deposits and withdrawals enabled by default
    /// @param pauser_ The initial pauser address
    function __Pausing_init(address pauser_) internal onlyInitializing {
        __Pausable_init();
        _setPauser(pauser_);
    }

    /// Restricts the caller to the `pauser` role, reverting with an error for other callers
    modifier onlyPauser() {
        if (pauser() != msg.sender) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /// @notice The address with the `pauser` role that can pause and unpause the contract
    /// @return The address of the pauser
    function pauser() public view returns (address) {
        return PausingStorage.get().pauser;
    }

    /// @notice Pauses the contract
    /// @dev May only be called by the `pauser` role
    function pause() external onlyPauser {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev May only be called by the `pauser` role
    function unpause() external onlyPauser {
        _unpause();
    }

    /// @notice Sets the address that may call `pause` and `unpause`
    /// @dev May only be called by the `owner` role
    /// @param newPauser The new pauser address
    function updatePauser(address newPauser) external onlyOwner {
        _setPauser(newPauser);
    }

    /// @notice Checks if deposits are paused for a specific domain
    /// @param domain The domain to check
    /// @return `true` if deposits are paused, `false` otherwise
    function domainDepositsPaused(uint32 domain) public view returns (bool) {
        return PausingStorage.get().domainStates[domain].depositsPaused;
    }

    /// @notice Checks if withdrawals are paused for a specific domain
    /// @param domain The domain to check
    /// @return `true` if withdrawals are paused, `false` otherwise
    function domainWithdrawalsPaused(uint32 domain) public view returns (bool) {
        return PausingStorage.get().domainStates[domain].withdrawalsPaused;
    }

    /// @notice Sets the pause state for a specific domain (internal helper)
    /// @param domain The domain to update
    /// @param depositsPaused Whether deposits should be paused for this domain
    /// @param withdrawalsPaused Whether withdrawals should be paused for this domain
    function _setDomainPauseState(uint32 domain, bool depositsPaused, bool withdrawalsPaused) internal {
        PausingStorage.Data storage $ = PausingStorage.get();
        $.domainStates[domain].depositsPaused = depositsPaused;
        $.domainStates[domain].withdrawalsPaused = withdrawalsPaused;
        emit DomainPauseStateUpdated(domain, depositsPaused, withdrawalsPaused);
    }

    /// @notice Sets the pauser in storage and emits an event
    /// @param newPauser The new pauser address
    function _setPauser(address newPauser) private {
        if (newPauser == address(0)) {
            revert ZeroAddress();
        }
        address oldPauser = PausingStorage.get().pauser;
        PausingStorage.get().pauser = newPauser;
        emit PauserUpdated(oldPauser, newPauser);
    }
}

/// @title PausingStorage
///
/// @notice Implements the EIP-7201 storage pattern for the `Pausing` module
library PausingStorage {
    /// Domain-specific pause state
    struct DomainPauseState {
        /// Whether deposits are paused for this domain (false = not paused, true = paused)
        bool depositsPaused;
        /// Whether withdrawals are paused for this domain (false = not paused, true = paused)
        bool withdrawalsPaused;
    }

    /// @custom:storage-location erc7201:circle.xReserve.Pausing
    struct Data {
        /// The address that is allowed to pause and unpause the contract
        address pauser;
        /// Maps domain ID to its pause state for deposits and withdrawals
        mapping(uint32 => DomainPauseState) domainStates;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Pausing"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0xc1b0aef4073b36d82bede1f3d73be2d41f403b88ee64d408639974796975b800;

    /// EIP-7201 getter for the storage slot
    ///
    /// @return $   The storage struct for the `Pausing` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
