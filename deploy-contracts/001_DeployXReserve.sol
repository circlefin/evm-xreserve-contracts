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

import {console} from "forge-std/console.sol";
import {EnvSelector, EnvConfig} from "deploy-contracts/000_Constants.sol";
import {BaseBytecodeDeployScript} from "deploy-contracts/BaseBytecodeDeployScript.sol";

/// @title DeployXReserve
/// @notice Deployment script for RemoteDomainDepositor and xReserve system
/// @dev Deploys in sequence:
///      1. RemoteDomainDepositor implementation
///      2. UpgradeablePlaceholder implementation (temporary implementation)
///      3. xReserve implementation (actual implementation)
///      4. ERC1967Proxy pointing to placeholder, then upgrades to actual implementation
contract DeployXReserve is BaseBytecodeDeployScript {
    /// @dev Maximum number of supported tokens that can be configured
    uint256 private constant NUM_MAX_SUPPORTED_TOKENS = 1;

    /// @dev Environment selector for multi-environment deployment
    EnvSelector private envSelector;

    constructor() {
        envSelector = new EnvSelector();
    }

    /// @dev Prepares constructor arguments for xReserve implementation
    /// @return Encoded constructor arguments for xReserve
    function prepareConstructorArgs() internal view returns (bytes memory) {
        address gatewayMinterAddress = vm.envAddress("X_RESERVE_GATEWAY_MINTER_ADDRESS");
        address gatewayWalletAddress = vm.envAddress("X_RESERVE_GATEWAY_WALLET_ADDRESS");
        address tokenMessengerAddress = vm.envAddress("X_RESERVE_TOKEN_MESSENGER_ADDRESS");
        address tokenMessengerV2Address = vm.envAddress("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS");

        // Encode constructor arguments
        return abi.encode(gatewayMinterAddress, gatewayWalletAddress, tokenMessengerAddress, tokenMessengerV2Address);
    }

    /// @dev Prepares constructor arguments for RemoteDomainDepositor
    /// @return Empty bytes since RemoteDomainDepositor constructor takes no parameters
    function prepareRemoteDomainDepositorConstructorArgs() internal pure returns (bytes memory) {
        return bytes("");
    }

    /// @dev Prepares initialization data for xReserve
    /// @return Encoded initialization call data including all configuration parameters
    function prepareInitData(address remoteDomainDepositorImplAddress) internal view returns (bytes memory) {
        address xReservePauser = vm.envAddress("X_RESERVE_PAUSER_ADDRESS");
        address xReserveBlocklister = vm.envAddress("X_RESERVE_BLOCKLISTER_ADDRESS");

        // Parse supported tokens from environment. This supports up to NUM_MAX_SUPPORTED_TOKENS tokens.
        address[] memory supportedTokens = new address[](NUM_MAX_SUPPORTED_TOKENS);
        uint256 tokenCount = 0;
        for (uint256 i = 1; i <= NUM_MAX_SUPPORTED_TOKENS; i++) {
            string memory key = string.concat("X_RESERVE_SUPPORTED_TOKEN_", vm.toString(i));
            try vm.envAddress(key) returns (address tokenAddress) {
                supportedTokens[tokenCount] = tokenAddress;
                tokenCount++;
            } catch {
                // Stop when the first numbered token is not found
                break;
            }
        }

        address[] memory finalSupportedTokens = new address[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            finalSupportedTokens[i] = supportedTokens[i];
        }

        uint32 domain = uint32(vm.envUint("X_RESERVE_DOMAIN"));
        address xReserveRegistrationManager = vm.envAddress("X_RESERVE_REGISTRATION_MANAGER_ADDRESS");

        // Encode initialization call with all parameters (using the deployed RemoteDomainDepositor address)
        return abi.encodeWithSignature(
            "initialize(uint32,address,address,address,address[],address)",
            domain,
            xReservePauser,
            xReserveBlocklister,
            xReserveRegistrationManager,
            finalSupportedTokens,
            remoteDomainDepositorImplAddress
        );
    }

    /// @notice Main deployment function that sets up the entire xReserve system
    /// @dev Deployment process using UpgradeablePlaceholder pattern:
    ///      1. Deploy RemoteDomainDepositor implementation
    ///      2. Deploy UpgradeablePlaceholder implementation
    ///      3. Deploy xReserve implementation with constructor arguments
    ///      4. Deploy ERC1967Proxy pointing to placeholder with owner initialization
    ///      5. Upgrade proxy from placeholder to xReserve with initialization
    ///      6. Transfer ownership to final owner
    function run()
        public
        returns (
            address remoteDomainDepositorImplAddress,
            address placeholderAddress,
            address implAddress,
            address proxyAddress
        )
    {
        // Get environment configuration
        EnvConfig memory config = envSelector.getEnvironmentConfig();

        vm.startBroadcast(config.deployerAddress);

        // Step 1: Deploy RemoteDomainDepositor implementation
        remoteDomainDepositorImplAddress = _deployRemoteDomainDepositor(config);

        // Step 2: Deploy UpgradeablePlaceholder implementation
        placeholderAddress = _deployPlaceholder(config);

        // Step 3: Deploy xReserve implementation with constructor arguments
        implAddress = _deployXReserveImplementation(config);

        // Step 4-5: Deploy proxy with placeholder and execute upgrade + ownership transfer
        proxyAddress = _deployAndUpgradeProxy(config, remoteDomainDepositorImplAddress, placeholderAddress, implAddress);

        vm.stopBroadcast();
    }

    /// @dev Deploy RemoteDomainDepositor implementation
    function _deployRemoteDomainDepositor(EnvConfig memory config) internal returns (address) {
        address remoteDomainDepositorImplAddress = deploy(
            config.factoryAddress,
            "RemoteDomainDepositor.json",
            config.remoteDomainDepositorSalt,
            prepareRemoteDomainDepositorConstructorArgs()
        );
        console.log("RemoteDomainDepositor implementation deployed at:", remoteDomainDepositorImplAddress);
        return remoteDomainDepositorImplAddress;
    }

    /// @dev Deploy UpgradeablePlaceholder implementation
    function _deployPlaceholder(EnvConfig memory config) internal returns (address) {
        bytes32 reservePlaceholderSalt = keccak256(abi.encodePacked(config.reserveSalt, "placeholder"));
        address placeholderAddress =
            deploy(config.factoryAddress, "UpgradeablePlaceholder.json", reservePlaceholderSalt, hex"");
        console.log("UpgradeablePlaceholder address", placeholderAddress);
        return placeholderAddress;
    }

    /// @dev Deploy xReserve implementation
    function _deployXReserveImplementation(EnvConfig memory config) internal returns (address) {
        address implAddress =
            deploy(config.factoryAddress, "xReserve.json", config.reserveSalt, prepareConstructorArgs());
        console.log("xReserve implementation address", implAddress);
        return implAddress;
    }

    /// @dev Deploy proxy with placeholder and execute upgrade + ownership transfer
    function _deployAndUpgradeProxy(
        EnvConfig memory config,
        address remoteDomainDepositorImplAddress,
        address placeholderAddress,
        address implAddress
    ) internal returns (address) {
        address xReserveOwner = vm.envAddress("X_RESERVE_OWNER_ADDRESS");

        // Ensure the xReserve owner is an EOA (not a contract)
        require(xReserveOwner.code.length == 0, "xReserve owner must be an EOA");

        // Initialize placeholder with factory as temporary owner so it can execute the upgrade
        bytes memory placeholderInitData = abi.encodeWithSignature("initialize(address)", config.factoryAddress);
        bytes memory proxyConstructorArgs = abi.encode(placeholderAddress, placeholderInitData);

        // Prepare initialization data using the deployed RemoteDomainDepositor address
        bytes memory xReserveInitData = prepareInitData(remoteDomainDepositorImplAddress);

        bytes[] memory proxyMultiCallData = new bytes[](2);
        // First: Upgrade to xReserve implementation with initialization
        proxyMultiCallData[0] =
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", implAddress, xReserveInitData);
        // Second: Transfer ownership to final owner
        proxyMultiCallData[1] = abi.encodeWithSignature("transferOwnership(address)", xReserveOwner);

        // Deploy proxy with placeholder and execute upgrade + ownership transfer
        address proxyAddress = deployAndMultiCall(
            config.factoryAddress,
            "ERC1967Proxy.json",
            config.reserveProxySalt,
            proxyConstructorArgs,
            proxyMultiCallData
        );
        console.log("xReserve proxy address", proxyAddress);
        return proxyAddress;
    }
}
