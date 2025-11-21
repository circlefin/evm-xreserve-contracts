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

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {UnauthorizedCaller} from "../../common/Errors.sol";
import {IRemoteDomainDepositor} from "../../interfaces/IRemoteDomainDepositor.sol";
import {IRemoteDomainHookExecutor} from "../../interfaces/IRemoteDomainHookExecutor.sol";
import {Pausing} from "./Pausing.sol";
import {TokenSupport} from "./TokenSupport.sol";

/// @title RemoteDomainRegistration
/// @notice Contract for registering and managing remote domains and tokens
abstract contract RemoteDomainRegistration is TokenSupport, Pausing {
    // ============ Events ============

    /// @notice Emitted when a remote domain is registered
    /// @param remoteDomain The domain identifier being registered
    /// @param remoteDomainManager The address of the domain manager on the remote domain
    /// @param remoteDomainAttesters The addresses of the attesters on the remote domain
    /// @param remoteDomainDepositor The address of the deployed RemoteDomainDepositor contract
    event RemoteDomainRegistered(
        uint32 indexed remoteDomain,
        address indexed remoteDomainManager,
        address indexed remoteDomainDepositor,
        address remoteDomainPauser,
        address[] remoteDomainAttesters,
        uint256 signatureThreshold,
        uint256 persistentSignatureBufferDelayBlocks,
        address remoteDomainHookExecutor
    );

    /// @notice Emitted when a remote domain is deregistered
    /// @param remoteDomain The domain identifier being deregistered
    event RemoteDomainDeregistered(uint32 indexed remoteDomain);

    /// @notice Emitted when a remote token is registered
    /// @param localToken The token address on the local domain
    /// @param remoteDomain The domain identifier to register
    /// @param remoteToken The token address on the remote domain
    event RemoteTokenRegistered(address indexed localToken, uint32 indexed remoteDomain, bytes32 indexed remoteToken);

    /// @notice Emitted when a remote token is deregistered
    /// @param localToken The token address on the local domain
    /// @param remoteDomain The domain identifier to deregister
    /// @param remoteToken The token address on the remote domain
    event RemoteTokenDeregistered(address indexed localToken, uint32 indexed remoteDomain, bytes32 indexed remoteToken);

    /// @notice Emitted when the hook executor for a remote domain is set
    /// @param remoteDomain The domain identifier to set the hook executor for
    /// @param oldHookExecutor The address of the old hook executor
    /// @param newHookExecutor The address of the new hook executor
    event RemoteDomainHookExecutorUpdated(
        uint32 indexed remoteDomain, address indexed oldHookExecutor, address indexed newHookExecutor
    );

    /// @notice Emitted when the registration manager address is updated
    /// @param oldManager The old remote domain manager address
    /// @param newManager The new remote domain manager address
    event RegistrationManagerUpdated(address indexed oldManager, address indexed newManager);

    // ============ Errors ============

    /// @notice Thrown when a remote domain is already registered
    /// @param remoteDomain The domain that is already registered
    error RemoteDomainAlreadyRegistered(uint32 remoteDomain);

    /// @notice Thrown when a remote domain is not registered
    /// @param remoteDomain The domain that is not registered
    error RemoteDomainNotRegistered(uint32 remoteDomain);

    /// @notice Thrown when a remote token is already registered
    /// @param remoteDomain The domain identifier
    /// @param remoteToken The token that is already registered
    error RemoteTokenAlreadyRegistered(uint32 remoteDomain, bytes32 remoteToken);

    /// @notice Thrown when an unauthorized address attempts to pause a domain
    /// @param domain The domain the caller tried to pause
    /// @param caller The unauthorized caller
    error UnauthorizedDomainPauser(uint32 domain, address caller);

    /// @notice Thrown when a remote token is not registered
    /// @param remoteDomain The domain identifier
    /// @param remoteToken The token that is not registered
    error RemoteTokenNotRegistered(uint32 remoteDomain, bytes32 remoteToken);

    /// @notice Thrown when a local token is not registered for a remote domain
    /// @param remoteDomain The domain identifier
    /// @param localToken The local token that is not registered
    error LocalTokenNotRegistered(uint32 remoteDomain, address localToken);

    /// @notice Thrown when attempting to register a local token that is already registered for a remote domain
    /// @param remoteDomain The domain identifier
    /// @param localToken The local token that is registered
    error LocalTokenAlreadyRegistered(uint32 remoteDomain, address localToken);

    /// @notice Thrown when an invalid implementation is provided
    error InvalidImplementation();

    // ============ Initialization ============

    /// @notice Initializes the RemoteDomainRegistration module
    /// @param implementation The address of the pre-deployed RemoteDomainDepositor implementation
    /// @param registrationManager_ The initial registration manager address
    function __RemoteDomainRegistration_init(address implementation, address registrationManager_)
        internal
        onlyInitializing
    {
        if (implementation == address(0) || implementation.code.length == 0) {
            revert InvalidImplementation();
        }

        _getStorage().remoteDomainDepositorImplementation = implementation;
        _setRegistrationManager(registrationManager_);
    }

    // ============ Modifiers ============

    /// @notice Restricts the caller to the `registrationManager` role, reverting with an error for other callers
    modifier onlyRegistrationManager() {
        if (msg.sender != registrationManager()) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /// @notice Requires that a remote domain is registered
    /// @param remoteDomain The domain identifier to check
    modifier requireDomainRegistered(uint32 remoteDomain) {
        if (_getStorage().remoteDomainDepositors[remoteDomain] == address(0)) {
            revert RemoteDomainNotRegistered(remoteDomain);
        }
        _;
    }

    /// @notice Requires that a remote domain is not registered
    /// @param remoteDomain The domain identifier to check
    modifier requireDomainNotRegistered(uint32 remoteDomain) {
        if (_getStorage().remoteDomainDepositors[remoteDomain] != address(0)) {
            revert RemoteDomainAlreadyRegistered(remoteDomain);
        }
        _;
    }

    /// @notice Requires that a remote token is not registered
    /// @param remoteDomain The domain identifier to check
    /// @param remoteToken The token address on the remote domain to check
    modifier requireTokenNotRegistered(uint32 remoteDomain, bytes32 remoteToken) {
        if (_getStorage().remoteTokenToLocalTokenMapping[remoteDomain][remoteToken] != address(0)) {
            revert RemoteTokenAlreadyRegistered(remoteDomain, remoteToken);
        }
        _;
    }

    /// @notice Requires that a local token is registered for a remote domain
    /// @param remoteDomain The domain identifier to check
    /// @param localToken The local token address to check
    modifier requireLocalTokenRegistered(uint32 remoteDomain, address localToken) {
        if (_getStorage().localTokenToRemoteTokenMapping[remoteDomain][localToken] == bytes32(0)) {
            revert LocalTokenNotRegistered(remoteDomain, localToken);
        }
        _;
    }

    /// @notice Requires that a local token is not registered for a remote domain
    /// @param remoteDomain The domain identifier to check
    /// @param localToken The local token address to check
    modifier requireLocalTokenNotRegistered(uint32 remoteDomain, address localToken) {
        if (_getStorage().localTokenToRemoteTokenMapping[remoteDomain][localToken] != bytes32(0)) {
            revert LocalTokenAlreadyRegistered(remoteDomain, localToken);
        }
        _;
    }

    // ============ External Functions ============

    /// @notice Registers a new remote domain
    /// @dev Only the registrationManager can register a remote domain
    /// @param remoteDomain The domain identifier to register
    /// @param domainManager The address of the domain manager on the remote domain
    /// @param domainPauser The address of the domain pauser on the remote domain
    /// @param domainAttesters The addresses of the attesters on the remote domain
    /// @param signatureThreshold The threshold of signatures required to attest to a message
    /// @param persistentSignatureBufferDelayBlocks The number of blocks to delay when disabling attesters and increasing signature thresholds
    /// @return remoteDomainDepositor The address of the RemoteDomainDepositor contract for the remote domain
    function registerRemoteDomain(
        uint32 remoteDomain,
        address domainManager,
        address domainPauser,
        address[] calldata domainAttesters,
        uint256 signatureThreshold,
        uint256 persistentSignatureBufferDelayBlocks,
        address remoteDomainHookExecutor
    )
        external
        onlyRegistrationManager
        requireDomainNotRegistered(remoteDomain)
        returns (address remoteDomainDepositor)
    {
        RemoteDomainRegistrationStorage.Data storage $ = _getStorage();

        {
            // Generate deterministic salt based on remote domain for consistent cross-chain addresses
            bytes32 salt = keccak256(abi.encode(remoteDomain));

            bytes memory creationCode = abi.encodePacked(
                type(ERC1967Proxy).creationCode, abi.encode($.remoteDomainDepositorImplementation, bytes(""))
            );

            // Deploy ERC1967Proxy with deterministic address using CREATE2
            remoteDomainDepositor = Create2.deploy(0, salt, creationCode);
        }

        $.remoteDomainDepositors[remoteDomain] = remoteDomainDepositor;
        $.remoteDomainHookExecutors[remoteDomain] = IRemoteDomainHookExecutor(remoteDomainHookExecutor);

        // Emit the registration event with the deployed depositor address
        emit RemoteDomainRegistered(
            remoteDomain,
            domainManager,
            remoteDomainDepositor,
            domainPauser,
            domainAttesters,
            signatureThreshold,
            persistentSignatureBufferDelayBlocks,
            remoteDomainHookExecutor
        );

        // Initialize the proxy (external call to deployed contract)
        IRemoteDomainDepositor(remoteDomainDepositor).initialize(
            domainManager, domainPauser, domainAttesters, signatureThreshold, persistentSignatureBufferDelayBlocks
        );
    }

    /// @notice Deregisters a remote domain
    /// @dev Only the owner can deregister a remote domain
    /// @dev This function does not clear the remote token mappings
    /// @dev Once deregistered, a domain cannot be re-registered as it would attempt to deploy to the same address
    /// @param remoteDomain The domain identifier to deregister
    function deregisterRemoteDomain(uint32 remoteDomain) external onlyOwner requireDomainRegistered(remoteDomain) {
        // Set remoteDomainEnabled[remoteDomain] to false
        delete _getStorage().remoteDomainDepositors[remoteDomain];

        // Set remoteDomainHookExecutors[remoteDomain] to zero address
        delete _getStorage().remoteDomainHookExecutors[remoteDomain];

        emit RemoteDomainDeregistered(remoteDomain);
    }

    /// @notice Registers a new remote token for an existing remote domain
    /// @dev Only the registrationManager can register a remote token
    /// @param localToken The token address on the local domain
    /// @param remoteDomain The domain identifier to register
    /// @param remoteToken The token address on the remote domain
    function registerRemoteToken(address localToken, uint32 remoteDomain, bytes32 remoteToken)
        external
        onlyRegistrationManager
        requireDomainRegistered(remoteDomain)
        requireTokenNotRegistered(remoteDomain, remoteToken)
        requireLocalTokenNotRegistered(remoteDomain, localToken)
    {
        // Validate inputs
        _validateTokenRegistrationInputs(localToken, remoteToken);

        // Store the mapping between remote domain, remote token, and local token
        _getStorage().remoteTokenToLocalTokenMapping[remoteDomain][remoteToken] = localToken;

        // Store the reverse mapping for local token to remote token lookups
        _getStorage().localTokenToRemoteTokenMapping[remoteDomain][localToken] = remoteToken;

        emit RemoteTokenRegistered(localToken, remoteDomain, remoteToken);
    }

    /// @notice Deregisters a remote token from an existing remote domain
    /// @dev Only the owner can deregister a remote token
    /// @param remoteDomain The domain identifier to deregister
    /// @param remoteToken The token address on the remote domain
    function deregisterRemoteToken(uint32 remoteDomain, bytes32 remoteToken)
        external
        onlyOwner
        requireDomainRegistered(remoteDomain)
    {
        // Check if remote token is registered and get local token
        address localToken = _getStorage().remoteTokenToLocalTokenMapping[remoteDomain][remoteToken];
        if (localToken == address(0)) {
            revert RemoteTokenNotRegistered(remoteDomain, remoteToken);
        }

        // Set remoteTokenToLocalTokenMapping[remoteDomain] to zero address
        delete _getStorage().remoteTokenToLocalTokenMapping[remoteDomain][remoteToken];

        //  Set localTokenToRemoteTokenMapping[remoteDomain] to zero address
        delete _getStorage().localTokenToRemoteTokenMapping[remoteDomain][localToken];

        emit RemoteTokenDeregistered(localToken, remoteDomain, remoteToken);
    }

    /// @notice Sets the hook executor for a remote domain
    /// @dev Only the owner can set the hook executor
    /// @dev The hook executor can be set to zero address to disable the hook executor
    /// @param remoteDomain The domain identifier to set the hook executor for
    /// @param newHookExecutor The address of the new hook executor
    function setRemoteDomainHookExecutor(uint32 remoteDomain, address newHookExecutor)
        external
        onlyOwner
        requireDomainRegistered(remoteDomain)
    {
        address oldHookExecutor = address(_getStorage().remoteDomainHookExecutors[remoteDomain]);
        _getStorage().remoteDomainHookExecutors[remoteDomain] = IRemoteDomainHookExecutor(newHookExecutor);

        emit RemoteDomainHookExecutorUpdated(remoteDomain, oldHookExecutor, newHookExecutor);
    }

    // ============ Role Management Functions ============

    /// @notice Updates the registration manager address
    /// @dev This function allows the owner to update the registration manager address,
    ///      granting or revoking the registration manager role
    /// @dev This function should be idempotent
    /// @param newManager The new registration manager address
    function updateRegistrationManager(address newManager) external onlyOwner {
        _setRegistrationManager(newManager);
    }

    /// @notice Sets the pause state for a specific remote domain
    /// @dev May only be called by the domain pauser for that domain (obtained from the remote domain depositor)
    /// @param domain The domain to update
    /// @param depositsPaused Whether deposits should be paused for this domain
    /// @param withdrawalsPaused Whether withdrawals should be paused for this domain
    function setDomainPauseState(uint32 domain, bool depositsPaused, bool withdrawalsPaused)
        external
        requireDomainRegistered(domain)
    {
        // Get the domain pauser from the remote domain depositor
        address _domainPauser = IRemoteDomainDepositor(getRemoteDomainDepositor(domain)).domainPauser();

        // Check that msg.sender is the domain pauser. This also ensures _domainPauser is not zero address, because
        // if _domainPauser were zero, the if condition would always be true (since msg.sender can never be zero).
        if (msg.sender != _domainPauser) {
            revert UnauthorizedDomainPauser(domain, msg.sender);
        }

        // Use the helper function from Pausing module
        _setDomainPauseState(domain, depositsPaused, withdrawalsPaused);
    }

    // ============ Internal Helper Functions ============

    /// @notice Gets the storage struct for the RemoteDomainRegistration module
    /// @return $ The storage struct
    function _getStorage() internal pure returns (RemoteDomainRegistrationStorage.Data storage $) {
        return RemoteDomainRegistrationStorage.get();
    }

    /// @notice Validates inputs for token registration
    /// @param localToken The token address on the local domain
    /// @param remoteToken The token address on the remote domain
    function _validateTokenRegistrationInputs(address localToken, bytes32 remoteToken) internal view {
        AddressLib._checkNotZeroAddress(localToken);
        AddressLib._checkNotZeroBytes32(remoteToken);
        _ensureTokenSupported(localToken);
    }

    /// @notice Sets the address that is allowed to register remote domains and tokens
    /// @param newManager The new remote domain manager address
    function _setRegistrationManager(address newManager) internal {
        AddressLib._checkNotZeroAddress(newManager);
        address oldManager = _getStorage().registrationManager;
        _getStorage().registrationManager = newManager;
        emit RegistrationManagerUpdated(oldManager, newManager);
    }

    // ============ View Functions ============

    /// @notice Gets the shared implementation contract for RemoteDomainDepositor proxies
    /// @return The implementation address
    function remoteDomainDepositorImplementation() external view returns (address) {
        return _getStorage().remoteDomainDepositorImplementation;
    }

    /// @notice The address with the `registrationManager` role that can register remote domains and tokens
    /// @return The address of the registration manager
    function registrationManager() public view returns (address) {
        return _getStorage().registrationManager;
    }

    /// @notice Check if a remote domain is registered
    /// @param remoteDomain The domain identifier to check
    /// @return True if the remote domain is registered, false otherwise
    function isRemoteDomainRegistered(uint32 remoteDomain) public view returns (bool) {
        return _getStorage().remoteDomainDepositors[remoteDomain] != address(0);
    }

    /// @notice Check if a remote token is registered for a specific domain
    /// @param remoteDomain The domain identifier to check
    /// @param remoteToken The token address on the remote domain to check
    /// @return True if the remote token is registered for the domain, false otherwise
    function isRemoteTokenRegistered(uint32 remoteDomain, bytes32 remoteToken) public view returns (bool) {
        return _getStorage().remoteTokenToLocalTokenMapping[remoteDomain][remoteToken] != address(0);
    }

    /// @notice Gets the remote token address for a given local token and remote domain
    /// @param remoteDomain The remote domain identifier
    /// @param localToken The local token address
    /// @return The remote token address as bytes32, or bytes32(0) if not registered
    function getRemoteToken(uint32 remoteDomain, address localToken) public view returns (bytes32) {
        return _getStorage().localTokenToRemoteTokenMapping[remoteDomain][localToken];
    }

    /// @notice Gets the remote domain depositor address for a given remote domain
    /// @param remoteDomain The remote domain identifier
    /// @return The remote domain depositor address, or address(0) if not registered
    function getRemoteDomainDepositor(uint32 remoteDomain) public view returns (address) {
        return _getStorage().remoteDomainDepositors[remoteDomain];
    }

    /// @notice Gets the hook executor for a given remote domain
    /// @param remoteDomain The remote domain identifier
    /// @return The hook executor address, or address(0) if not set
    function getRemoteDomainHookExecutor(uint32 remoteDomain) public view returns (address) {
        return address(_getStorage().remoteDomainHookExecutors[remoteDomain]);
    }
}

/// @title RemoteDomainRegistrationStorage
/// @notice Implements the EIP-7201 storage pattern for the `RemoteDomainRegistration` module
library RemoteDomainRegistrationStorage {
    /// @custom:storage-location erc7201:circle.xReserve.RemoteDomainRegistration
    struct Data {
        /// Mapping from remote domain to remote token to local token address
        mapping(uint32 remoteDomain => mapping(bytes32 remoteToken => address localToken))
            remoteTokenToLocalTokenMapping;
        /// Mapping from remote domain to local token to remote token address
        mapping(uint32 remoteDomain => mapping(address localToken => bytes32 remoteToken))
            localTokenToRemoteTokenMapping;
        /// Mapping from remote domain to remote domain depositor address
        mapping(uint32 remoteDomain => address depositor) remoteDomainDepositors;
        /// Mapping from remote domain to remote domain hook executor address
        mapping(uint32 remoteDomain => IRemoteDomainHookExecutor hookExecutor) remoteDomainHookExecutors;
        /// Shared implementation contract for RemoteDomainDepositor proxies
        address remoteDomainDepositorImplementation;
        /// The address that is allowed to register remote domains and tokens
        address registrationManager;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.RemoteDomainRegistration"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x5b4e4be47fb1acb1ed4bcf1ef4afe1634200c49767dcbd6314604c0214977900;

    /// @notice EIP-7201 getter for the storage slot
    /// @return $ The storage struct for the `RemoteDomainRegistration` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
