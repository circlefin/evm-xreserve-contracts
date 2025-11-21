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

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EnvSelector, EnvConfig} from "deploy-contracts/000_Constants.sol";

/// @title DeployedContractStateValidation
/// @notice Script to verify deployed contract state matches expected values
/// @dev Performs state verification for xReserve system contracts including:
///      - xReserve proxy state (owner, pauser, blocklister, domain, supported tokens, etc.)
///      - RemoteDomainDepositor implementation state
///      - Proxy implementation address verification
contract DeployedContractStateValidation is Script {
    /// @dev Maximum number of supported tokens that can be configured (matches deployment script)
    uint256 private constant NUM_MAX_SUPPORTED_TOKENS = 1;
    /// @notice Verifies a contract state value from a contract against expected value
    /// @param deployedAddress Address of the contract to query
    /// @param functionSignature Function signature to call (e.g., "domain()")
    /// @param encodedFunctionParameter Encoded function parameter to pass (e.g., abi.encode(vm.envAddress("TOKEN_ADDRESS")))
    /// @param expectedValue Expected return value

    function verifyContractStateValue(
        address deployedAddress,
        string memory functionSignature,
        bytes memory encodedFunctionParameter,
        bytes memory expectedValue
    ) public {
        // Call the function on the deployed contract
        (bool callSuccess, bytes memory returnData) = deployedAddress.call(
            abi.encodePacked(bytes4(keccak256(bytes(functionSignature))), encodedFunctionParameter)
        );
        require(callSuccess, string(abi.encodePacked("Function call failed: ", functionSignature)));

        // Check if values match
        require(keccak256(expectedValue) == keccak256(returnData), "Value validation failed");
    }

    /// @notice Verifies xReserve proxy state variables
    /// @param xReserveProxyAddress Address of the deployed xReserve proxy
    function verifyXReserveProxyState(address xReserveProxyAddress) public {
        console.log("Verifying xReserve proxy state...");

        EnvSelector envSelector = new EnvSelector();
        EnvConfig memory config = envSelector.getEnvironmentConfig();

        // Verify ownership state depending on whether two-step transfer was completed
        bool ownershipTransferCompleted = vm.envOr("X_RESERVE_OWNERSHIP_TRANSFER_COMPLETED", false);
        if (ownershipTransferCompleted) {
            // After completion: owner is final owner, pendingOwner is zero address
            verifyContractStateValue(
                xReserveProxyAddress, "owner()", "", abi.encode(vm.envAddress("X_RESERVE_OWNER_ADDRESS"))
            );
            verifyContractStateValue(
                xReserveProxyAddress, "pendingOwner()", "", abi.encode(address(0))
            );
        } else {
            // Before completion: owner is factory, pendingOwner is final owner
            verifyContractStateValue(xReserveProxyAddress, "owner()", "", abi.encode(config.factoryAddress));
            verifyContractStateValue(
                xReserveProxyAddress, "pendingOwner()", "", abi.encode(vm.envAddress("X_RESERVE_OWNER_ADDRESS"))
            );
        }

        // Verify pauser
        verifyContractStateValue(
            xReserveProxyAddress, "pauser()", "", abi.encode(vm.envAddress("X_RESERVE_PAUSER_ADDRESS"))
        );

        // Verify paused state is false
        verifyContractStateValue(
            xReserveProxyAddress, "paused()", "", abi.encode(false)
        );

        // Verify blocklister
        verifyContractStateValue(
            xReserveProxyAddress, "blocklister()", "", abi.encode(vm.envAddress("X_RESERVE_BLOCKLISTER_ADDRESS"))
        );

        // Verify domain
        verifyContractStateValue(xReserveProxyAddress, "domain()", "", abi.encode(vm.envUint("X_RESERVE_DOMAIN")));

        // Verify registration manager
        verifyContractStateValue(
            xReserveProxyAddress,
            "registrationManager()",
            "",
            abi.encode(vm.envAddress("X_RESERVE_REGISTRATION_MANAGER_ADDRESS"))
        );

        // Verify remote domain depositor implementation
        verifyContractStateValue(
            xReserveProxyAddress,
            "remoteDomainDepositorImplementation()",
            "",
            abi.encode(vm.envAddress("X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS"))
        );

        // Verify supported tokens
        uint256 tokenCount = 0;
        for (uint256 i = 1; i <= NUM_MAX_SUPPORTED_TOKENS; i++) {
            string memory key = string.concat("X_RESERVE_SUPPORTED_TOKEN_", vm.toString(i));
            try vm.envAddress(key) returns (address tokenAddress) {
                verifyContractStateValue(
                    xReserveProxyAddress, "isTokenSupported(address)", abi.encode(tokenAddress), abi.encode(true)
                );
                tokenCount++;
            } catch {
                // Stop when the first numbered token is not found
                break;
            }
        }

        console.log("Verified", tokenCount, "supported tokens");

        // Verify immutable addresses (constructor parameters)
        verifyContractStateValue(
            xReserveProxyAddress,
            "gatewayMinter()",
            "",
            abi.encode(vm.envAddress("X_RESERVE_GATEWAY_MINTER_ADDRESS"))
        );

        verifyContractStateValue(
            xReserveProxyAddress,
            "gatewayWallet()",
            "",
            abi.encode(vm.envAddress("X_RESERVE_GATEWAY_WALLET_ADDRESS"))
        );

        verifyContractStateValue(
            xReserveProxyAddress,
            "tokenMessenger()",
            "",
            abi.encode(vm.envAddress("X_RESERVE_TOKEN_MESSENGER_ADDRESS"))
        );

        verifyContractStateValue(
            xReserveProxyAddress,
            "tokenMessengerV2()",
            "",
            abi.encode(vm.envAddress("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS"))
        );

        console.log("[OK] xReserve proxy state verified");
    }

    /// @notice Verifies RemoteDomainDepositor implementation state
    /// @param remoteDomainDepositorImplAddress Address of the deployed RemoteDomainDepositor implementation
    function verifyRemoteDomainDepositorState(address remoteDomainDepositorImplAddress) public {
        console.log("Verifying RemoteDomainDepositor implementation state...");

        // RemoteDomainDepositor doesn't have many state variables to verify
        // It's mainly a factory contract for creating domain-specific depositor proxies
        // We can verify it has code and is a contract
        require(remoteDomainDepositorImplAddress.code.length > 0, "RemoteDomainDepositor implementation has no code");

        console.log("[OK] RemoteDomainDepositor implementation state verified");
    }

    /// @notice Verifies proxy implementation address matches expected implementation address
    /// @param proxyAddress Address of the proxy contract
    /// @param expectedImplAddress Expected implementation address
    function verifyProxyImplementation(address proxyAddress, address expectedImplAddress) public {
        console.log("Verifying proxy implementation address...");

        // Verify proxy implementation address matches expected implementation address
        bytes32 raw = vm.load(proxyAddress, bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        address actualImplAddress = address(uint160(uint256(raw)));
        require(actualImplAddress == expectedImplAddress, "Proxy implementation address validation failed");

        console.log("[OK] Proxy implementation address verified");
    }

    /// @notice Main verification function for the entire xReserve system
    /// @param xReserveProxyAddress Address of the deployed xReserve proxy
    /// @param xReserveImplAddress Address of the deployed xReserve implementation
    /// @param remoteDomainDepositorImplAddress Address of the deployed RemoteDomainDepositor implementation
    function verifyXReserveSystemState(
        address xReserveProxyAddress,
        address xReserveImplAddress,
        address remoteDomainDepositorImplAddress
    ) public {
        console.log("=== Verifying xReserve System State ===");

        // 1. Verify xReserve proxy state
        verifyXReserveProxyState(xReserveProxyAddress);

        // 2. Verify RemoteDomainDepositor implementation state
        verifyRemoteDomainDepositorState(remoteDomainDepositorImplAddress);

        // 3. Verify proxy implementation address
        verifyProxyImplementation(xReserveProxyAddress, xReserveImplAddress);

        // Note: Remote domains and tokens are registered dynamically after deployment
        // and are not part of the initial deployment configuration, so we don't verify them here

        console.log("=== xReserve System State Verification Complete ===");
    }

    /// @notice Main run function for comprehensive state validation
    function run() public {
        console.log("Starting comprehensive state validation...");

        // Load contract addresses from environment variables
        address xReserveProxyAddress = vm.envAddress("X_RESERVE_PROXY_ADDRESS");
        address xReserveImplAddress = vm.envAddress("X_RESERVE_IMPL_ADDRESS");
        address remoteDomainDepositorImplAddress = vm.envAddress("X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS");

        // Run all state validations
        verifyXReserveSystemState(xReserveProxyAddress, xReserveImplAddress, remoteDomainDepositorImplAddress);

        console.log("All state validations completed successfully!");
    }
}
