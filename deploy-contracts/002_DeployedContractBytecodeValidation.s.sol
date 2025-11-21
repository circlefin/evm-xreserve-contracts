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
import {ICreate2Factory} from "lib/evm-gateway-contracts/script/interface/ICreate2Factory.sol";
import {EnvSelector, EnvConfig} from "deploy-contracts/000_Constants.sol";

/// @title DeployedContractBytecodeValidation
/// @notice Script to verify deployed contract bytecode (both constructor and runtime) against compiled artifacts
/// @dev Supports validation of constructor bytecode, runtime bytecode with immutable references, and proxy contracts (bytecode validation only)
contract DeployedContractBytecodeValidation is Script {
    /// @notice Struct to hold immutable reference information
    /// @param start The byte position where the immutable value starts in the bytecode
    /// @param length The length of the immutable value in bytes
    struct ImmutableReference {
        uint256 start;
        uint256 length;
    }

    /// @notice Verifies constructor bytecode for factory-based CREATE2 deployment by recomputing address from init code
    /// @dev This avoids RPC tracing by proving that (initCode + constructorArgs) and the provided salt produce the deployed address via CREATE2
    /// @param factoryAddress The CREATE2 factory contract address used for deployment
    /// @param salt The CREATE2 salt used for deployment
    /// @param deployedAddress The deployed contract address to verify
    /// @param contractName Name of the contract artifact in deploy-contracts/compiled-contract-artifacts/
    /// @param constructorArgs The constructor arguments used during deployment
    /// @return success True if the computed CREATE2 address matches the deployed address
    function verifyConstructorBytecode(
        address factoryAddress,
        bytes32 salt,
        address deployedAddress,
        string memory contractName,
        bytes memory constructorArgs
    ) public view returns (bool success) {
        // Load creation (init) bytecode from the compiled artifact
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy-contracts/compiled-contract-artifacts/", contractName, ".json");
        string memory json = vm.readFile(path);
        bytes memory creationInitCode = abi.decode(vm.parseJson(json, ".bytecode.object"), (bytes));

        // Combine init code with constructor arguments
        bytes memory fullCreationBytecode = abi.encodePacked(creationInitCode, constructorArgs);

        // Check if factory address has code (is a contract)
        if (factoryAddress.code.length == 0) {
            console.log("[ERROR] Factory address has no code (not a contract):", factoryAddress);
            return false;
        }

        // Use the factory's computeAddress function to get the expected address
        // This approach verifies that the constructor arguments match what was expected during contract creation
        // because CREATE2 addresses are deterministically computed from the salt and the full creation bytecode
        // (which includes the constructor arguments). If the constructor arguments were different, the
        // computed address would be different, making this a robust verification method.
        // This is much easier and more reliable than trying to extract constructor bytecode from contracts
        // deployed via CREATE2 factories, which would require complex transaction tracing and bytecode
        // analysis that is error-prone and not as robust as this deterministic address recomputation.
        try ICreate2Factory(factoryAddress).computeAddress(salt, keccak256(fullCreationBytecode)) returns (
            address expectedAddress
        ) {
            bool addressesMatch = expectedAddress == deployedAddress;
            if (!addressesMatch) {
                console.log("[ERROR] CREATE2 address mismatch:");
                console.log("  Expected address:", expectedAddress);
                console.log("  Deployed address:", deployedAddress);
                console.log("  Salt:", vm.toString(salt));
                console.log("  Contract name:", contractName);
            }
            return addressesMatch;
        } catch {
            // If factory call fails, return false
            console.log("[ERROR] Factory computeAddress call failed for contract:", contractName);
            console.log("  Factory address:", factoryAddress);
            console.log("  Salt:", vm.toString(salt));
            return false;
        }
    }

    /// @notice Verifies runtime bytecode of a deployed contract against expected bytecode
    /// @param deployedAddress Address of the deployed contract to verify
    /// @param contractName Name of the contract artifact in deploy-contracts/compiled-contract-artifacts/
    /// @return success True if the runtime bytecode matches (after handling immutable references)
    function verifyRuntimeBytecode(address deployedAddress, string memory contractName)
        public
        view
        returns (bool success)
    {
        // Get the deployed runtime bytecode
        bytes memory actualRuntimeBytecode = deployedAddress.code;

        // Get the expected bytecode from the compiled artifact
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy-contracts/compiled-contract-artifacts/", contractName, ".json");
        string memory json = vm.readFile(path);
        bytes memory expectedRuntimeBytecode = abi.decode(vm.parseJson(json, ".deployedBytecode.object"), (bytes));

        // Handle UUPS upgradeable contracts with address(this) immutable fields
        // Replace any occurrence of the deployed address with zero bytes in the actual bytecode FIRST,
        // so that expected is patched using the same zeroed bytes where applicable.
        actualRuntimeBytecode = replaceAddressWithZeros(actualRuntimeBytecode, deployedAddress);

        // Handle immutable references by replacing expected values with (possibly zeroed) actual values
        expectedRuntimeBytecode = swapImmutableReferences(json, expectedRuntimeBytecode, actualRuntimeBytecode);

        // Compare the bytecode
        bool bytecodeMatches = keccak256(expectedRuntimeBytecode) == keccak256(actualRuntimeBytecode);
        if (!bytecodeMatches) {
            console.log("[ERROR] Runtime bytecode mismatch for contract:", contractName);
            console.log("  Deployed address:", deployedAddress);
            console.log("  Expected bytecode length:", expectedRuntimeBytecode.length);
            console.log("  Actual bytecode length:", actualRuntimeBytecode.length);
            console.log("  Expected bytecode hash:", vm.toString(keccak256(expectedRuntimeBytecode)));
            console.log("  Actual bytecode hash:", vm.toString(keccak256(actualRuntimeBytecode)));
        }
        return bytecodeMatches;
    }

    /// @notice Verifies both constructor (via CREATE2 recomputation) and runtime bytecode of a deployed contract
    /// @param factoryAddress The CREATE2 factory contract address
    /// @param salt The CREATE2 salt used to deploy the contract
    /// @param deployedAddress Address of the deployed contract to verify
    /// @param contractName Name of the contract artifact in deploy-contracts/compiled-contract-artifacts/
    /// @param constructorArgs The constructor arguments used during deployment
    /// @return constructorValid True if CREATE2 address recomputation matches deployed address
    /// @return runtimeValid True if runtime bytecode matches (after handling immutable references)
    function verifyFullContract(
        address factoryAddress,
        bytes32 salt,
        address deployedAddress,
        string memory contractName,
        bytes memory constructorArgs
    ) public view returns (bool constructorValid, bool runtimeValid) {
        constructorValid =
            verifyConstructorBytecode(factoryAddress, salt, deployedAddress, contractName, constructorArgs);
        runtimeValid = verifyRuntimeBytecode(deployedAddress, contractName);
    }

    /// @notice Verifies a proxy contract's constructor (via CREATE2), runtime bytecode and implementation address
    /// @param factoryAddress The CREATE2 factory contract address
    /// @param proxySalt The CREATE2 salt used to deploy the proxy
    /// @param proxyAddress Address of the proxy contract
    /// @param expectedImplAddress Expected implementation address
    /// @param proxyConstructorArgs Constructor arguments for the proxy
    /// @return bytecodeValid True if proxy constructor (CREATE2 recompute) and runtime bytecode match
    /// @return implValid True if implementation address matches
    function verifyProxy(
        address factoryAddress,
        bytes32 proxySalt,
        address proxyAddress,
        address expectedImplAddress,
        bytes memory proxyConstructorArgs
    ) public view returns (bool bytecodeValid, bool implValid) {
        // Verify proxy constructor via CREATE2 recomputation and runtime bytecode
        (bool constructorValid, bool runtimeValid) =
            verifyFullContract(factoryAddress, proxySalt, proxyAddress, "ERC1967Proxy", proxyConstructorArgs);
        bytecodeValid = constructorValid && runtimeValid;

        // Verify proxy implementation address matches expected implementation address
        bytes32 raw = vm.load(proxyAddress, bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        address actualImplAddress = address(uint160(uint256(raw)));
        implValid = actualImplAddress == expectedImplAddress;

        if (!implValid) {
            console.log("[ERROR] Proxy implementation address mismatch:");
            console.log("  Proxy address:", proxyAddress);
            console.log("  Expected implementation:", expectedImplAddress);
            console.log("  Actual implementation:", actualImplAddress);
        }
    }

    /// @notice Example verification for xReserve system
    /// @param factoryAddress The CREATE2 factory contract address used for all deployments
    /// @param reserveSalt CREATE2 salt for xReserve implementation
    /// @param reserveProxySalt CREATE2 salt for xReserve proxy
    /// @param remoteDomainDepositorSalt CREATE2 salt for RemoteDomainDepositor implementation
    /// @param reserveProxyAddress Address of the deployed xReserve proxy
    /// @param reserveImplAddress Address of the deployed xReserve implementation
    /// @param remoteDomainDepositorImplAddress Address of the deployed RemoteDomainDepositor implementation
    /// @param placeholderImplAddress Address of the deployed UpgradeablePlaceholder implementation
    function verifyXReserveContracts(
        address factoryAddress,
        bytes32 reserveSalt,
        bytes32 reserveProxySalt,
        bytes32 remoteDomainDepositorSalt,
        address reserveProxyAddress,
        address reserveImplAddress,
        address remoteDomainDepositorImplAddress,
        address placeholderImplAddress
    ) public view {
        console.log("=== Verifying xReserve Contracts ===");

        // 1. Verify xReserve implementation
        console.log("Verifying xReserve implementation...");
        bytes memory reserveConstructorArgs = prepareReserveConstructorArgs();
        (bool constructorValid, bool runtimeValid) =
            verifyFullContract(factoryAddress, reserveSalt, reserveImplAddress, "xReserve", reserveConstructorArgs);

        if (!constructorValid) {
            console.log("[ERROR] xReserve implementation constructor bytecode verification failed");
            console.log("  Factory address:", factoryAddress);
            console.log("  Reserve salt:", vm.toString(reserveSalt));
            console.log("  Reserve impl address:", reserveImplAddress);
        }
        if (!runtimeValid) {
            console.log("[ERROR] xReserve implementation runtime bytecode verification failed");
            console.log("  Reserve impl address:", reserveImplAddress);
        }

        require(constructorValid, "xReserve implementation constructor bytecode verification failed");
        require(runtimeValid, "xReserve implementation runtime bytecode verification failed");
        console.log("[OK] xReserve implementation verified");

        // 2. Verify RemoteDomainDepositor implementation
        console.log("Verifying RemoteDomainDepositor implementation...");
        (constructorValid, runtimeValid) = verifyFullContract(
            factoryAddress,
            remoteDomainDepositorSalt,
            remoteDomainDepositorImplAddress,
            "RemoteDomainDepositor",
            bytes("")
        );

        if (!constructorValid) {
            console.log("[ERROR] RemoteDomainDepositor implementation constructor bytecode verification failed");
            console.log("  Factory address:", factoryAddress);
            console.log("  Remote domain depositor salt:", vm.toString(remoteDomainDepositorSalt));
            console.log("  Remote domain depositor impl address:", remoteDomainDepositorImplAddress);
        }
        if (!runtimeValid) {
            console.log("[ERROR] RemoteDomainDepositor implementation runtime bytecode verification failed");
            console.log("  Remote domain depositor impl address:", remoteDomainDepositorImplAddress);
        }

        require(constructorValid, "RemoteDomainDepositor implementation constructor bytecode verification failed");
        require(runtimeValid, "RemoteDomainDepositor implementation runtime bytecode verification failed");
        console.log("[OK] RemoteDomainDepositor implementation verified");

        // 3. Verify UpgradeablePlaceholder implementation (runtime only, as we don't have creation tx)
        console.log("Verifying UpgradeablePlaceholder implementation...");
        runtimeValid = verifyRuntimeBytecode(placeholderImplAddress, "UpgradeablePlaceholder");

        if (!runtimeValid) {
            console.log("[ERROR] UpgradeablePlaceholder implementation runtime bytecode verification failed");
            console.log("  Placeholder impl address:", placeholderImplAddress);
        }

        require(runtimeValid, "UpgradeablePlaceholder implementation runtime bytecode verification failed");
        console.log("[OK] UpgradeablePlaceholder implementation verified");

        // 4. Verify xReserve proxy
        console.log("Verifying xReserve proxy...");
        bytes memory proxyConstructorArgs = prepareProxyConstructorArgs(placeholderImplAddress, factoryAddress);
        (bool proxyBytecodeValid, bool proxyImplValid) =
            verifyProxy(factoryAddress, reserveProxySalt, reserveProxyAddress, reserveImplAddress, proxyConstructorArgs);

        if (!proxyBytecodeValid) {
            console.log("[ERROR] xReserve proxy bytecode verification failed");
            console.log("  Factory address:", factoryAddress);
            console.log("  Reserve proxy salt:", vm.toString(reserveProxySalt));
            console.log("  Reserve proxy address:", reserveProxyAddress);
        }
        if (!proxyImplValid) {
            console.log("[ERROR] xReserve proxy implementation address verification failed");
            console.log("  Reserve proxy address:", reserveProxyAddress);
            console.log("  Expected implementation:", reserveImplAddress);
        }

        require(proxyBytecodeValid, "xReserve proxy bytecode verification failed");
        require(proxyImplValid, "xReserve proxy implementation address verification failed");
        console.log("[OK] xReserve proxy verified");

        console.log("=== xReserve System Verification Complete ===");
    }

    /// @notice Main run function for comprehensive bytecode validation
    function run() public {
        console.log("Starting comprehensive bytecode validation...");

        // Load contract addresses from environment variables
        address reserveProxyAddress = vm.envAddress("X_RESERVE_PROXY_ADDRESS");
        address reserveImplAddress = vm.envAddress("X_RESERVE_IMPL_ADDRESS");
        address remoteDomainDepositorImplAddress = vm.envAddress("X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS");
        address placeholderImplAddress = vm.envAddress("UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS");

        // Load factory and salts used for CREATE2 deployments from environment configuration
        EnvSelector envSelector = new EnvSelector();
        EnvConfig memory config = envSelector.getEnvironmentConfig();
        address factoryAddress = config.factoryAddress;
        bytes32 reserveSalt = config.reserveSalt;
        bytes32 reserveProxySalt = config.reserveProxySalt;
        bytes32 remoteDomainDepositorSalt = config.remoteDomainDepositorSalt;

        // Run all bytecode validations
        verifyXReserveContracts(
            factoryAddress,
            reserveSalt,
            reserveProxySalt,
            remoteDomainDepositorSalt,
            reserveProxyAddress,
            reserveImplAddress,
            remoteDomainDepositorImplAddress,
            placeholderImplAddress
        );

        console.log("All bytecode validations completed successfully!");
    }

    // ============ Internal Helper Functions ============

    /// @dev Replaces immutable references in expected bytecode with actual values from deployed bytecode
    /// @param artifactJson The JSON string of the compiled artifact
    /// @param expectedBytecode The expected runtime bytecode
    /// @return The expected bytecode with immutable references replaced
    function swapImmutableReferences(
        string memory artifactJson,
        bytes memory expectedBytecode,
        bytes memory actualBytecode
    ) internal pure returns (bytes memory) {
        // Parse immutable references from the artifact JSON
        try vm.parseJsonKeys(artifactJson, ".deployedBytecode.immutableReferences") returns (string[] memory keys) {
            if (keys.length == 0) {
                console.log("[DEBUG] No immutable references found in artifact");
                return expectedBytecode;
            }

            // Skip immutable reference swapping if actual bytecode is empty (e.g., address(0) or no code)
            if (actualBytecode.length == 0) {
                console.log("[WARNING] Actual bytecode is empty, skipping immutable reference swapping");
                return expectedBytecode;
            }

            // For each immutable reference entry, copy the actual bytes into expected at the specified offsets
            for (uint256 i = 0; i < keys.length; i++) {
                string memory path = string.concat(".deployedBytecode.immutableReferences.", keys[i]);
                bytes memory raw = vm.parseJson(artifactJson, path);

                // Decode as array of ImmutableReference {start,length}
                ImmutableReference[] memory refs = abi.decode(raw, (ImmutableReference[]));

                for (uint256 j = 0; j < refs.length; j++) {
                    uint256 start = refs[j].start;
                    uint256 length = refs[j].length;

                    // Bounds checks
                    if (start + length > expectedBytecode.length || start + length > actualBytecode.length) {
                        console.log("[WARNING] Immutable ref out of bounds, skipping:");
                        console.log("  start:", start);
                        console.log("  length:", length);
                        console.log("  expected length:", expectedBytecode.length);
                        console.log("  actual length:", actualBytecode.length);
                        continue;
                    }

                    // Copy bytes from actual into expected
                    for (uint256 k = 0; k < length; k++) {
                        expectedBytecode[start + k] = actualBytecode[start + k];
                    }
                }
            }

            return expectedBytecode;
        } catch {
            console.log("[WARNING] Failed to parse immutable references from artifact JSON");
            return expectedBytecode;
        }
    }

    /// @dev For a given address, find all occurrences of its 20-byte representation in actual bytecode
    ///      and write those 20 bytes into expected bytecode at the same offsets.
    function _patchExpectedWithAddressOccurrences(
        bytes memory expectedBytecode,
        bytes memory actualBytecode,
        address value
    ) internal pure returns (bytes memory) {
        if (expectedBytecode.length != actualBytecode.length) {
            // Conservative: do nothing if lengths differ
            console.log("[WARNING] Bytecode length mismatch during address patching:");
            console.log("  Expected length:", expectedBytecode.length);
            console.log("  Actual length:", actualBytecode.length);
            console.log("  Address:", value);
            return expectedBytecode;
        }

        bytes memory addrBytes = abi.encodePacked(value);
        uint256 lastStart = 0;
        while (lastStart + 20 <= actualBytecode.length) {
            // Search for next match
            (bool found, uint256 idx) = _indexOf(actualBytecode, addrBytes, lastStart);
            if (!found) {
                break;
            }

            // Copy into expected at the same offset
            for (uint256 k = 0; k < 20; k++) {
                expectedBytecode[idx + k] = addrBytes[k];
            }

            lastStart = idx + 20;
        }
        return expectedBytecode;
    }

    /// @dev Find the index of the first occurrence of "pattern" in "data" starting from fromIndex
    function _indexOf(bytes memory data, bytes memory pattern, uint256 fromIndex)
        internal
        pure
        returns (bool found, uint256 index)
    {
        if (pattern.length == 0 || data.length < pattern.length) {
            return (false, 0);
        }
        if (fromIndex > data.length - pattern.length) {
            return (false, 0);
        }
        for (uint256 i = fromIndex; i <= data.length - pattern.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < pattern.length; j++) {
                if (data[i + j] != pattern[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /// @dev Replaces occurrences of a specific address with zero bytes in bytecode
    /// @param bytecode The bytecode to modify
    /// @param targetAddress The address to replace with zeros
    /// @return The modified bytecode
    function replaceAddressWithZeros(bytes memory bytecode, address targetAddress)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory result = bytecode;

        // Return early if bytecode is too short to contain an address
        if (result.length < 20) {
            return result;
        }

        bytes memory targetBytes = abi.encodePacked(targetAddress);

        // Search for the address pattern and replace with zeros
        for (uint256 i = 0; i <= result.length - 20; i++) {
            bool matches = true;
            for (uint256 j = 0; j < 20; j++) {
                if (result[i + j] != targetBytes[j]) {
                    matches = false;
                    break;
                }
            }

            if (matches) {
                // Replace with zero bytes
                for (uint256 k = 0; k < 20; k++) {
                    result[i + k] = bytes1(0);
                }
            }
        }

        return result;
    }

    /// @dev Prepares constructor arguments for xReserve
    /// @return Encoded constructor arguments
    function prepareReserveConstructorArgs() internal view returns (bytes memory) {
        address gatewayMinterAddress = vm.envAddress("X_RESERVE_GATEWAY_MINTER_ADDRESS");
        address gatewayWalletAddress = vm.envAddress("X_RESERVE_GATEWAY_WALLET_ADDRESS");
        address tokenMessengerAddress = vm.envAddress("X_RESERVE_TOKEN_MESSENGER_ADDRESS");
        address tokenMessengerV2Address = vm.envAddress("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS");

        return abi.encode(gatewayMinterAddress, gatewayWalletAddress, tokenMessengerAddress, tokenMessengerV2Address);
    }

    /// @dev Prepares constructor arguments for ERC1967Proxy
    /// @param placeholderAddress The address of the placeholder implementation
    /// @return Encoded constructor arguments for the proxy
    function prepareProxyConstructorArgs(address placeholderAddress, address factoryAddress)
        internal
        pure
        returns (bytes memory)
    {
        // The proxy constructor takes (implementation, initData). We initialize the placeholder
        // with the factory address as the temporary owner (ownership is transferred later).
        bytes memory placeholderInitData = abi.encodeWithSignature("initialize(address)", factoryAddress);

        return abi.encode(placeholderAddress, placeholderInitData);
    }
}
