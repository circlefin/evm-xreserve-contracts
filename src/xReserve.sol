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
import {DepositIntent} from "src/lib/DepositIntent.sol";
import {IGatewayWallet} from "./interfaces/IGatewayWallet.sol";
import {IRemoteDomainDepositor} from "./interfaces/IRemoteDomainDepositor.sol";
import {DepositIntentLib} from "./lib/DepositIntentLib.sol";
import {Domain} from "./modules/x-reserve/Domain.sol";
import {Immutables} from "./modules/x-reserve/Immutables.sol";
import {Withdrawal} from "./modules/x-reserve/Withdrawal.sol";

/// @title xReserve
///
/// @notice xReserve contract for transferring assets between different domains.
/// @notice Users can deposit assets into the reserve contract to initiate a cross-domain
///         transfer. When a deposit is made, xReserve's off-chain systems observe the
///         Deposit event and generate a `DepositAttestation`. This attestation can then
///         be used to mint the corresponding reserved tokens on the remote domain.
/// @notice Users can burn tokens on a remote domain to initiate a withdrawal back to
///         the source domain. This process requires authorization from the remote
///         domain operator through observer signatures. xReserve's attestation infrastructure
///         performs additional verification and generates a `WithdrawAttestation`. Once both the remote
///         domain operator signature and withdrawal attestation are validated, the
///         corresponding funds held in the reserve can be released to the user.
///
/// @dev The reserve contract will also support the transfer of assets from a remote
///      reserved token domain to another domain where CCTP TokenMessenger has been deployed.
/// @dev The reserve contract will also support the transfer of assets from a remote
///      reserved token domain to another domain where GatewayMinter has been deployed.
// solhint-disable-next-line contract-name-capwords
contract xReserve is UUPSUpgradeable, Withdrawal, Domain {
    /// @notice Constructor for the xReserve contract
    /// @dev Sets immutable external contract addresses and disables initializers for the implementation
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address gatewayMinterAddress,
        address gatewayWalletAddress,
        address tokenMessengerAddress,
        address tokenMessengerV2Address
    ) Immutables(gatewayMinterAddress, gatewayWalletAddress, tokenMessengerAddress, tokenMessengerV2Address) {
        // Ensure that the implementation contract cannot be initialized, only the proxy
        _disableInitializers();
    }

    /// @notice Initializes the contract and all of its modules, in the order of inheritance
    /// @dev Assumes the contract is being deployed behind a proxy and that the proxy has already been initialized using
    ///      the `UpgradeablePlaceholder` contract. Ownable is already initialized by UpgradeablePlaceholder.
    /// @param domain_            The operator-issued identifier for this chain
    /// @param pauser_            The address to initialize the pauser role
    /// @param blocklister_       The address to initialize the blocklister role
    /// @param registrationManager_ The address to initialize the registration manager role
    /// @param supportedTokens_   The list of tokens to support initially
    /// @param remoteDomainDepositorImplementation_ The address of the pre-deployed RemoteDomainDepositor implementation
    function initialize(
        uint32 domain_,
        address pauser_,
        address blocklister_,
        address registrationManager_,
        address[] calldata supportedTokens_,
        address remoteDomainDepositorImplementation_
    ) external reinitializer(2) {
        __Pausing_init(pauser_);
        __Blocklistable_init(blocklister_);
        __Domain_init(domain_);
        __TokenSupport_init(supportedTokens_);
        __RemoteDomainRegistration_init(remoteDomainDepositorImplementation_, registrationManager_);
        __ReentrancyGuard_init();
    }

    /// @notice Implements the UUPS upgrade pattern by restricting upgrades to the owner
    /// @param _newImplementation The address of the new implementation
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /// @notice Restores or sets the maximum allowance for GatewayWallet to spend supported tokens owned by this contract.
    /// @dev Anyone can call this function to ensure GatewayWallet has unlimited allowance for each supported token.
    ///      This is useful if allowances are reduced or depleted, allowing uninterrupted operation.
    /// @param tokens Array of token addresses to approve. Must all be supported tokens.
    function setUnlimitedAllowances(address[] calldata tokens) external {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; ++i) {
            address token = tokens[i];

            // Ensure token is supported
            _ensureTokenSupported(token);

            // Set unlimited allowances using the internal method
            _setUnlimitedAllowances(token);
        }
    }

    /// @notice Returns the available balance of a native collateral token for a remote domain
    /// @param localToken The address of the token being used as native collateral
    /// @param remoteDomain The remote domain for which the collateral is held locally
    function balanceOfNativeCollateral(address localToken, uint32 remoteDomain)
        external
        view
        requireDomainRegistered(remoteDomain)
        requireLocalTokenRegistered(remoteDomain, localToken)
        returns (uint256)
    {
        return IGatewayWallet(gatewayWallet).availableBalance(localToken, getRemoteDomainDepositor(remoteDomain));
    }

    /// @notice Updates the domain manager for a specific remote domain
    /// @dev Only the owner can update the domain manager. This function allows rotating
    ///      the domain manager.
    /// @param remoteDomain The remote domain identifier
    /// @param newDomainManager The new domain manager address
    function updateDomainManager(uint32 remoteDomain, address newDomainManager)
        external
        onlyOwner
        requireDomainRegistered(remoteDomain)
    {
        // This function's modifier checks that the Remote Domain Depositor is not null. An event will
        //  be emitted from the RemoteDomainDepositor contract.
        IRemoteDomainDepositor(getRemoteDomainDepositor(remoteDomain)).updateDomainManager(newDomainManager);
    }

    /// @notice Updates the persistent signature buffer delay for a specific remote domain
    /// @dev Only the owner can update the persistent signature buffer delay. This function allows
    ///      adjusting the delay for disabling attesters and increasing signature thresholds.
    /// @param remoteDomain The remote domain identifier
    /// @param newDelay The new delay in blocks
    function setPersistentSignatureBufferDelay(uint32 remoteDomain, uint256 newDelay)
        external
        onlyOwner
        requireDomainRegistered(remoteDomain)
    {
        // This function's modifier checks that the Remote Domain Depositor is not null. An event will
        //  be emitted from the RemoteDomainDepositor contract.
        IRemoteDomainDepositor(getRemoteDomainDepositor(remoteDomain)).setPersistentSignatureBufferDelay(newDelay);
    }

    /// @notice Encodes a DepositIntent struct into bytes
    /// @param intent The DepositIntent to encode
    /// @return The encoded bytes
    function encodeDepositIntent(DepositIntent memory intent) external pure returns (bytes memory) {
        return DepositIntentLib.encodeDepositIntent(intent);
    }

    /// @notice Decodes bytes into a DepositIntent struct
    /// @param data The encoded bytes to decode
    /// @return The decoded DepositIntent struct
    function decodeDepositIntent(bytes memory data) external view returns (DepositIntent memory) {
        return DepositIntentLib.decodeDepositIntent(data);
    }
}
