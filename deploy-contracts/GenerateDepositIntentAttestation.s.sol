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

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DepositIntent, DepositIntentLib} from "../src/lib/DepositIntentLib.sol";

/**
 * @notice This script generates multiple DepositIntent attestations and saves them to a JSON file
 * @dev This script generates an arbitrary number of attestations with random values
 *
 * Configuration can be provided via environment variables:
 * - SIGNER_PRIVATE_KEY: Private key for signing (defaults to test key)
 * - DEPOSIT_REMOTE_DOMAIN: Remote domain ID (defaults to 10000)
 * - DEPOSIT_REMOTE_TOKEN: Remote token address as bytes32 (defaults to 0x000000000000000000000000a0B86a33e6F8ec61cc62f1B0CB2Ad6Dfe3C10e8B)
 * - DEPOSIT_LOCAL_TOKEN: Local token address as bytes32 (defaults to 0x000000000000000000000000A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
 * - ATTESTATION_COUNT: Number of attestations to generate (defaults to 1)
 * - OUTPUT_FILENAME: Custom output filename (defaults to current naming pattern)
 *
 * Example usage:
 * forge script script/GenerateDepositIntentAttestation.s.sol:GenerateDepositIntentAttestation
 *
 * With custom parameters:
 * ATTESTATION_COUNT=50 DEPOSIT_REMOTE_DOMAIN=1 forge script script/GenerateDepositIntentAttestation.s.sol:GenerateDepositIntentAttestation
 *
 * With custom output filename:
 * OUTPUT_FILENAME=my_custom_attestations.json forge script script/GenerateDepositIntentAttestation.s.sol:GenerateDepositIntentAttestation
 */
contract GenerateDepositIntentAttestation is Script {
    // Default values - can be overridden via environment variables
    uint256 public constant DEFAULT_SIGNER_PRIVATE_KEY =
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdee;
    uint32 public constant DEFAULT_DEPOSIT_REMOTE_DOMAIN = 10000;
    bytes32 public constant DEFAULT_DEPOSIT_REMOTE_TOKEN =
        0x000000000000000000000000a0B86a33e6F8ec61cc62f1B0CB2Ad6Dfe3C10e8B;
    bytes32 public constant DEFAULT_DEPOSIT_LOCAL_TOKEN =
        0x000000000000000000000000A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 public constant DEFAULT_ATTESTATION_COUNT = 1;

    // Fixed constant parameters
    uint32 public constant DEPOSIT_VERSION = 1;

    // Runtime configuration variables - set in loadConfiguration()
    uint256 public signerPrivateKey;
    uint32 public depositRemoteDomain;
    bytes32 public depositRemoteToken;
    bytes32 public depositLocalToken;
    uint256 public attestationCount;
    string public outputFilename;

    // Struct to hold attestation data for JSON output
    struct AttestationData {
        // Input values
        uint32 version;
        uint256 amount;
        uint32 remoteDomain;
        bytes32 remoteToken;
        bytes32 remoteRecipient;
        bytes32 localToken;
        bytes32 localDepositor;
        uint256 maxFee;
        bytes32 nonce;
        bytes hookData;
        // Output values
        bytes encodedMessage;
        bytes32 messageHash;
        bytes signature;
    }

    /**
     * @notice Loads configuration from environment variables or uses defaults
     * @dev Environment variables:
     *      - SIGNER_PRIVATE_KEY: Private key for signing attestations
     *      - DEPOSIT_REMOTE_DOMAIN: Remote domain ID
     *      - DEPOSIT_REMOTE_TOKEN: Remote token address (bytes32)
     *      - DEPOSIT_LOCAL_TOKEN: Local token address (bytes32)
     *      - ATTESTATION_COUNT: Number of attestations to generate
     *      - OUTPUT_FILENAME: Custom output filename (optional)
     */
    function loadConfiguration() internal {
        // Load with fallbacks to defaults
        signerPrivateKey = vm.envOr("SIGNER_PRIVATE_KEY", DEFAULT_SIGNER_PRIVATE_KEY);
        depositRemoteDomain = uint32(vm.envOr("DEPOSIT_REMOTE_DOMAIN", uint256(DEFAULT_DEPOSIT_REMOTE_DOMAIN)));
        depositRemoteToken = vm.envOr("DEPOSIT_REMOTE_TOKEN", DEFAULT_DEPOSIT_REMOTE_TOKEN);
        depositLocalToken = vm.envOr("DEPOSIT_LOCAL_TOKEN", DEFAULT_DEPOSIT_LOCAL_TOKEN);
        attestationCount = vm.envOr("ATTESTATION_COUNT", DEFAULT_ATTESTATION_COUNT);

        // Load output filename (optional - empty string means use default naming)
        try vm.envString("OUTPUT_FILENAME") returns (string memory customFilename) {
            outputFilename = customFilename;
        } catch {
            outputFilename = "";
        }

        // Log the loaded configuration
        console.log("=== LOADED CONFIGURATION ===");
        console.log("SIGNER_PRIVATE_KEY: %s", signerPrivateKey == DEFAULT_SIGNER_PRIVATE_KEY ? "DEFAULT" : "CUSTOM");
        console.log(
            "DEPOSIT_REMOTE_DOMAIN: %d %s",
            depositRemoteDomain,
            depositRemoteDomain == DEFAULT_DEPOSIT_REMOTE_DOMAIN ? "(default)" : "(custom)"
        );
        console.log(
            "DEPOSIT_REMOTE_TOKEN: %s", depositRemoteToken == DEFAULT_DEPOSIT_REMOTE_TOKEN ? "DEFAULT" : "CUSTOM"
        );
        console.log("DEPOSIT_LOCAL_TOKEN: %s", depositLocalToken == DEFAULT_DEPOSIT_LOCAL_TOKEN ? "DEFAULT" : "CUSTOM");
        console.log(
            "ATTESTATION_COUNT: %d %s",
            attestationCount,
            attestationCount == DEFAULT_ATTESTATION_COUNT ? "(default)" : "(custom)"
        );
        console.log("OUTPUT_FILENAME: %s", bytes(outputFilename).length == 0 ? "DEFAULT" : outputFilename);
        console.log("=============================");
    }

    /**
     * @notice Generates a random amount between min and max input arguments
     */
    function generateRandomAmount(uint256 minAmount, uint256 maxAmount) internal returns (uint256) {
        return minAmount + (vm.randomUint() % (maxAmount - minAmount + 1));
    }

    /**
     * @notice Generates random hook data with length between 0-100 bytes
     */
    function generateRandomHookData() internal returns (bytes memory) {
        uint256 length = vm.randomUint() % 101; // 0 to 100 bytes
        bytes memory hookData = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            hookData[i] = bytes1(uint8(vm.randomUint()));
        }

        return hookData;
    }

    /**
     * @notice Creates a DepositIntent with random values for variable fields
     */
    function generateRandomDepositIntent() internal returns (DepositIntent memory) {
        uint256 amount = generateRandomAmount(1e6, 1000000e6); // between 1 USDC and 1M USDC
        uint256 maxFee = (amount * (1 + (vm.randomUint() % 10))) / 100; // between 1% and 10% of amount

        return DepositIntent({
            version: DEPOSIT_VERSION,
            amount: amount,
            remoteDomain: depositRemoteDomain,
            remoteToken: depositRemoteToken,
            remoteRecipient: bytes32(vm.randomUint()),
            localToken: depositLocalToken,
            localDepositor: bytes32(vm.randomUint()),
            maxFee: maxFee,
            nonce: bytes32(vm.randomUint()),
            hookData: generateRandomHookData()
        });
    }

    /**
     * @notice Generates a single attestation and returns the data structure
     */
    function generateSingleAttestation() internal returns (AttestationData memory) {
        DepositIntent memory intent = generateRandomDepositIntent();

        // Encode the deposit intent
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        // Hash the encoded deposit intent
        bytes32 intentHash = keccak256(encoded);

        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, intentHash);
        bytes memory packedSignature = abi.encodePacked(r, s, v);

        return AttestationData({
            version: intent.version,
            amount: intent.amount,
            remoteDomain: intent.remoteDomain,
            remoteToken: intent.remoteToken,
            remoteRecipient: intent.remoteRecipient,
            localToken: intent.localToken,
            localDepositor: intent.localDepositor,
            maxFee: intent.maxFee,
            nonce: intent.nonce,
            hookData: intent.hookData,
            encodedMessage: encoded,
            messageHash: intentHash,
            signature: packedSignature
        });
    }

    /**
     * @notice Writes attestation data to JSON using vm.writeJson with attestation_generation_input and attestations
     */
    function writeAttestationsToJson(AttestationData[] memory attestations) internal {
        // Create attestation generation input object with configuration information
        string memory metadataKey = "attestation_generation_input";
        vm.serializeAddress(metadataKey, "signerAddress", vm.addr(signerPrivateKey));
        string memory metadata = vm.serializeUint(metadataKey, "totalAttestations", attestations.length);

        // Write each attestation to separate JSON objects then combine them
        string[] memory attestationJsons = new string[](attestations.length);

        for (uint256 i = 0; i < attestations.length; i++) {
            AttestationData memory attestation = attestations[i];

            // Create individual attestation JSON
            string memory attestationKey = string.concat("attestation_", vm.toString(i));

            // Create inputs object
            string memory inputsKey = string.concat(attestationKey, "_inputs");
            vm.serializeUint(inputsKey, "version", attestation.version);
            vm.serializeUint(inputsKey, "amount", attestation.amount);
            vm.serializeUint(inputsKey, "remoteDomain", attestation.remoteDomain);
            vm.serializeBytes32(inputsKey, "remoteToken", attestation.remoteToken);
            vm.serializeBytes32(inputsKey, "remoteRecipient", attestation.remoteRecipient);
            vm.serializeBytes32(inputsKey, "localToken", attestation.localToken);
            vm.serializeBytes32(inputsKey, "localDepositor", attestation.localDepositor);
            vm.serializeUint(inputsKey, "maxFee", attestation.maxFee);
            vm.serializeBytes32(inputsKey, "nonce", attestation.nonce);
            string memory inputs = vm.serializeBytes(inputsKey, "hookData", attestation.hookData);

            // Create outputs object
            string memory outputsKey = string.concat(attestationKey, "_outputs");
            vm.serializeBytes(outputsKey, "encodedMessage", attestation.encodedMessage);
            vm.serializeBytes32(outputsKey, "messageHash", attestation.messageHash);
            string memory outputs = vm.serializeBytes(outputsKey, "signature", attestation.signature);

            // Combine into single attestation object
            vm.serializeString(attestationKey, "inputs", inputs);
            attestationJsons[i] = vm.serializeString(attestationKey, "outputs", outputs);
        }

        // Create root object with attestation generation input and attestations
        string memory rootKey = "root";
        vm.serializeString(rootKey, "attestation_generation_input", metadata);
        string memory finalJson = vm.serializeString(rootKey, "attestations", attestationJsons);

        // Create output directory if it doesn't exist (handle failure gracefully)
        vm.createDir("generated", true);

        // Create filename - use custom filename if provided, otherwise use default pattern
        string memory filename;
        if (bytes(outputFilename).length > 0) {
            // Use custom output filename
            filename = string.concat("generated/", outputFilename);
        } else {
            // Create unique filename with shortened random component (4 bytes)
            filename = string.concat("generated/attestations_", vm.toString(uint32(vm.randomUint())), ".json");
        }
        vm.writeJson(finalJson, filename);
    }

    /**
     * @notice Main execution function that generates multiple attestations
     */
    function run() external {
        console.log("=== GENERATING MULTIPLE DEPOSIT INTENT ATTESTATIONS ===");

        // Load configuration from environment variables or use defaults
        loadConfiguration();

        console.log("Generating %d attestations...", attestationCount);

        // Generate attestations
        AttestationData[] memory attestations = new AttestationData[](attestationCount);

        for (uint256 i = 0; i < attestationCount; i++) {
            attestations[i] = generateSingleAttestation();
            if ((i + 1) % 10 == 0) {
                console.log("Generated %d of %d attestations...", i + 1, attestationCount);
            }
        }

        console.log("All attestations generated successfully!");

        // Write attestations to JSON file using vm.writeJson
        writeAttestationsToJson(attestations);

        console.log("=== GENERATION COMPLETE ===");
        console.log("Total attestations generated: %d", attestationCount);
    }
}
