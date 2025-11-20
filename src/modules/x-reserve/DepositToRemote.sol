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

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {IERC7597} from "../../interfaces/IERC7597.sol";
import {IERC7598} from "../../interfaces/IERC7598.sol";
import {IGatewayWallet} from "../../interfaces/IGatewayWallet.sol";
import {IRemoteDomainHookExecutor} from "../../interfaces/IRemoteDomainHookExecutor.sol";
import {DepositParams, PermitParams, AuthorizationParams} from "../../lib/DepositParams.sol";
import {Blocklistable} from "./Blocklistable.sol";
import {RemoteDomainRegistration} from "./RemoteDomainRegistration.sol";

/// @title DepositToRemote
/// @notice Module for handling deposit to remote domain operations with various authorization methods
abstract contract DepositToRemote is Blocklistable, RemoteDomainRegistration, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Events ============

    /// @notice Emitted when tokens are deposited to a remote domain
    /// @param localToken address of token being deposited on source domain
    /// @param value amount being deposited
    /// @param localDepositor address where deposit is transferred from
    /// @param remoteRecipient address receiving tokens on remote domain as bytes32
    /// @param remoteDomain remote domain
    /// @param remoteToken remote token as bytes32
    /// @param maxFee maximum fee to pay on remote domain, in units of localToken
    /// @param hookData optional hook for execution on remote domain
    event DepositedToRemote(
        address indexed localToken,
        uint256 value,
        address indexed localDepositor,
        bytes32 indexed remoteRecipient,
        uint32 remoteDomain,
        bytes32 remoteToken,
        uint256 maxFee,
        bytes hookData
    );

    // ============ Errors ============

    /// @dev Thrown when a zero value is provided for deposit.
    error ZeroValue();

    // ============ External Functions ============

    /// @notice Deposits tokens and transfer them to a remote domain
    /// @dev This function handles the deposit and transfer of tokens to a specified remote domain.
    ///      It validates the deposit intent payload and processes each deposit according to the specified rules.
    /// @param value The amount of tokens to deposit and transfer to remote domain
    /// @param remoteDomain The domain identifier where the tokens will be transferred to
    /// @param remoteRecipient The recipient address on the remote domain (as bytes32)
    /// @param localToken The address of the token being deposited and transferred to
    /// @param maxFee The maximum fee to pay on the remote domain, specified in units of localToken
    /// @param hookData Optional hook data to append to the transfer message for interpretation on the remote domain
    function depositToRemote(
        uint256 value,
        uint32 remoteDomain,
        bytes32 remoteRecipient,
        address localToken,
        uint256 maxFee,
        bytes calldata hookData
    ) external nonReentrant {
        _depositToRemote(value, remoteDomain, remoteRecipient, localToken, msg.sender, maxFee, hookData);
    }

    /// @notice Deposits tokens and transfers them to a remote domain using an EIP-2612/EIP-7597 permit
    /// @dev This function handles the deposit and transfer of tokens using a permit signature.
    ///      The permit allows for gasless token approvals and supports smart contract wallets.
    /// @param depositParams The deposit parameters (value, remoteDomain, remoteRecipient, localToken, maxFee, hookData)
    /// @param permitParams The permit parameters (owner, deadline, signature)
    function depositToRemoteWithPermit(DepositParams calldata depositParams, PermitParams calldata permitParams)
        external
        nonReentrant
    {
        // Validate deposit requirements and constraints
        _validateDepositInputs(
            depositParams.value, depositParams.remoteDomain, depositParams.remoteRecipient, depositParams.localToken
        );

        // Execute the permit and transfer the tokens from the owner to this contract
        IERC7597(depositParams.localToken).permit(
            permitParams.owner, address(this), depositParams.value, permitParams.deadline, permitParams.signature
        );
        IERC20(depositParams.localToken).safeTransferFrom(permitParams.owner, address(this), depositParams.value);

        // Execute the deposit
        _executeDepositToRemote(depositParams, permitParams.owner);
    }

    /// @notice Deposits tokens and transfers them to a remote domain using an ERC-3009/ERC-7598 authorization
    /// @dev This function handles the deposit and transfer of tokens using an authorization signature.
    ///      The authorization allows for gasless token transfers and supports smart contract wallets.
    /// @param depositParams The deposit parameters (value, remoteDomain, remoteRecipient, localToken, maxFee, hookData)
    /// @param authParams The authorization parameters (from, validAfter, validBefore, nonce, signature)
    function depositToRemoteWithAuthorization(
        DepositParams calldata depositParams,
        AuthorizationParams calldata authParams
    ) external nonReentrant {
        // Validate deposit requirements and constraints
        _validateDepositInputs(
            depositParams.value, depositParams.remoteDomain, depositParams.remoteRecipient, depositParams.localToken
        );

        // Execute the authorization to transfer the tokens from the depositor to this contract
        IERC7598(depositParams.localToken).receiveWithAuthorization(
            authParams.from,
            address(this),
            depositParams.value,
            authParams.validAfter,
            authParams.validBefore,
            authParams.nonce,
            authParams.signature
        );

        // Execute the deposit
        _executeDepositToRemote(depositParams, authParams.from);
    }

    // ============ Internal Functions ============

    /// @dev Internal implementation for basic deposit and transfer operations
    /// @param value The amount of tokens to deposit and transfer to remote domain
    /// @param remoteDomain The domain identifier where the tokens will be transferred to
    /// @param remoteRecipient The recipient address on the remote domain (as bytes32)
    /// @param localToken The address of the token being deposited and transferred to
    /// @param depositor The address of the depositor
    /// @param maxFee The maximum fee to pay on the remote domain, specified in units of localToken
    /// @param hookData Optional hook data to append to the transfer message for interpretation on the remote domain
    function _depositToRemote(
        uint256 value,
        uint32 remoteDomain,
        bytes32 remoteRecipient,
        address localToken,
        address depositor,
        uint256 maxFee,
        bytes memory hookData
    ) internal {
        // Validate deposit requirements and constraints
        _validateDepositInputs(value, remoteDomain, remoteRecipient, localToken);

        // Token is already transferred to this contract in the case of forwarding
        if (depositor != address(this)) {
            IERC20(localToken).safeTransferFrom(depositor, address(this), value);
        }

        // Execute the deposit
        DepositParams memory depositParams = DepositParams({
            value: value,
            remoteDomain: remoteDomain,
            remoteRecipient: remoteRecipient,
            localToken: localToken,
            maxFee: maxFee,
            hookData: hookData
        });

        _executeDepositToRemote(depositParams, depositor);
    }

    /// @dev Internal function to validate deposit requirements and enforce business constraints
    /// @dev Checks value limits, token support, address validity, and blocklist restrictions
    /// @param value The amount of tokens to deposit and transfer to remote domain
    /// @param remoteDomain The domain identifier where the tokens will be transferred to
    /// @param remoteRecipient The recipient address on the remote domain (as bytes32)
    /// @param localToken The address of the token being deposited and transferred to
    function _validateDepositInputs(uint256 value, uint32 remoteDomain, bytes32 remoteRecipient, address localToken)
        internal
        view
    {
        if (value == 0) {
            revert ZeroValue();
        }

        AddressLib._checkNotZeroAddress(localToken);

        // Check global pause state
        _requireNotPaused();

        // Check domain-specific deposit pause state
        if (domainDepositsPaused(remoteDomain)) {
            revert DomainDepositsPaused(remoteDomain);
        }

        if (!isRemoteDomainRegistered(remoteDomain)) {
            revert RemoteDomainNotRegistered(remoteDomain);
        }

        _ensureTokenSupported(localToken);
        _ensureNotBlocklisted(remoteDomain, remoteRecipient);

        // Enforce remote token registered
        bytes32 remoteToken = getRemoteToken(remoteDomain, localToken);
        if (remoteToken == bytes32(0)) {
            revert LocalTokenNotRegistered(remoteDomain, localToken);
        }
    }

    /// @dev Common deposit execution logic
    /// @param depositParams The deposit parameters
    /// @param depositor The address of the depositor
    function _executeDepositToRemote(DepositParams memory depositParams, address depositor) internal {
        // Emit the DepositedToRemote event BEFORE external call (CEI pattern)
        emit DepositedToRemote(
            depositParams.localToken,
            depositParams.value,
            depositor,
            depositParams.remoteRecipient,
            depositParams.remoteDomain,
            getRemoteToken(depositParams.remoteDomain, depositParams.localToken),
            depositParams.maxFee,
            depositParams.hookData
        );

        // Move funds into the GatewayWallet
        address remoteDomainDepositor = getRemoteDomainDepositor(depositParams.remoteDomain);
        IGatewayWallet wallet = IGatewayWallet(gatewayWallet);
        wallet.depositFor(depositParams.localToken, remoteDomainDepositor, depositParams.value);

        // Execute the hook if it exists
        address remoteDomainHookExecutor = getRemoteDomainHookExecutor(depositParams.remoteDomain);
        if (remoteDomainHookExecutor != address(0)) {
            IRemoteDomainHookExecutor(remoteDomainHookExecutor).executeHook(depositParams);
        }
    }
}
