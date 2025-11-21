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

import {stdJson} from "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";
import {GenerateDepositIntentAttestation} from "./../../deploy-contracts/GenerateDepositIntentAttestation.s.sol";
import {DepositIntent, DepositIntentLib} from "./../../src/lib/DepositIntentLib.sol";

/**
 * @notice Unit tests for GenerateDepositIntentAttestation script
 * @dev Verifies cryptographic operations, data integrity, and JSON output
 */
contract GenerateDepositIntentAttestationTest is Test {
    using stdJson for string;

    // Test configuration
    uint256 private constant TEST_SIGNER_KEY = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address private constant EXPECTED_SIGNER = 0x1Be31A94361a391bBaFB2a4CCd704F57dc04d4bb;
    uint32 private constant TEST_REMOTE_DOMAIN = 10001;
    uint256 private constant TEST_ATTESTATION_COUNT = 3;

    function setUp() public {
        // Pre-create the output directory for tests
        vm.createDir("generated", true);
    }

    /**
     * @notice Test script execution and JSON output validation
     */
    function test_runDepositIntentAttestation_succeeds() public {
        // Set environment variables for consistent testing
        vm.setEnv("SIGNER_PRIVATE_KEY", vm.toString(TEST_SIGNER_KEY));
        vm.setEnv("DEPOSIT_REMOTE_DOMAIN", vm.toString(TEST_REMOTE_DOMAIN));
        vm.setEnv("ATTESTATION_COUNT", vm.toString(TEST_ATTESTATION_COUNT));
        vm.setEnv("OUTPUT_FILENAME", "test_script_execution.json");

        // Run script
        GenerateDepositIntentAttestation testScript = new GenerateDepositIntentAttestation();
        testScript.run();

        // Read and verify the generated JSON file
        string memory jsonContent = vm.readFile("generated/test_script_execution.json");
        _verifyAttestations(jsonContent, TEST_REMOTE_DOMAIN);
    }

    /**
     * @notice Verify individual attestations for cryptographic correctness
     */
    function _verifyAttestations(string memory jsonContent, uint32 expectedRemoteDomain) internal view {
        // Get attestations array length
        uint256 attestationCount = jsonContent.readUint(".attestation_generation_input.totalAttestations");

        for (uint256 i = 0; i < attestationCount; i++) {
            string memory attestationPath = string.concat(".attestations[", vm.toString(i), "]");
            _verifyInputValues(jsonContent, attestationPath, expectedRemoteDomain);
            _verifyCryptographicProperties(jsonContent, attestationPath);
        }
    }

    /**
     * @notice Verify input value constraints
     */
    function _verifyInputValues(string memory jsonContent, string memory attestationPath, uint32 expectedRemoteDomain)
        internal
        pure
    {
        uint32 version = uint32(jsonContent.readUint(string.concat(attestationPath, ".inputs.version")));
        uint256 amount = jsonContent.readUint(string.concat(attestationPath, ".inputs.amount"));
        uint32 remoteDomain = uint32(jsonContent.readUint(string.concat(attestationPath, ".inputs.remoteDomain")));
        uint256 maxFee = jsonContent.readUint(string.concat(attestationPath, ".inputs.maxFee"));
        bytes memory hookData = jsonContent.readBytes(string.concat(attestationPath, ".inputs.hookData"));

        // Version should be 1
        assertEq(version, 1, "Version should be 1");

        // Amount should be between 1e6 and 1000000e6
        assertGe(amount, 1e6, "Amount should be at least 1e6");
        assertLe(amount, 1000000e6, "Amount should be at most 1000000e6");

        // Remote domain should match expected
        assertEq(remoteDomain, expectedRemoteDomain, "Remote domain mismatch");

        // MaxFee should be 1-10% of amount
        uint256 minFee = amount / 100; // 1%
        uint256 maxFeeAllowed = (amount * 10) / 100; // 10%
        assertGe(maxFee, minFee, "MaxFee should be at least 1% of amount");
        assertLe(maxFee, maxFeeAllowed, "MaxFee should be at most 10% of amount");

        // Hook data should be between 0-100 bytes
        assertLe(hookData.length, 100, "Hook data should be at most 100 bytes");
    }

    /**
     * @notice Verify cryptographic properties (hash and signature)
     */
    function _verifyCryptographicProperties(string memory jsonContent, string memory attestationPath) internal view {
        bytes memory encodedMessage = jsonContent.readBytes(string.concat(attestationPath, ".outputs.encodedMessage"));
        bytes32 messageHash = jsonContent.readBytes32(string.concat(attestationPath, ".outputs.messageHash"));
        bytes memory signature = jsonContent.readBytes(string.concat(attestationPath, ".outputs.signature"));

        // Get the expected signer address from JSON metadata
        address expectedSigner = jsonContent.readAddress(".attestation_generation_input.signerAddress");

        // Test 1: Verify hash is correct hash of encoded message
        bytes32 expectedHash = keccak256(encodedMessage);
        assertEq(messageHash, expectedHash, "Message hash does not match encoded message hash");

        // Test 2: Verify signature is valid for the hash
        _verifySignature(messageHash, signature, expectedSigner);

        // Test 3: Verify encoding by reconstructing the DepositIntent
        _verifyMessageEncoding(jsonContent, attestationPath, encodedMessage);
    }

    /**
     * @notice Verify signature validity using ECDSA recovery
     */
    function _verifySignature(bytes32 hash, bytes memory signature, address expectedSigner) internal pure {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        address recoveredSigner = ecrecover(hash, v, r, s);
        assertEq(recoveredSigner, expectedSigner, "Signature verification failed");
    }

    /**
     * @notice Verify message encoding by decoding and validating each field
     */
    function _verifyMessageEncoding(
        string memory jsonContent,
        string memory attestationPath,
        bytes memory encodedMessage
    ) internal view {
        // Decode the message from the JSON
        DepositIntent memory decodedIntent = DepositIntentLib.decodeDepositIntent(encodedMessage);

        // Extract expected values from JSON
        uint32 expectedVersion = uint32(jsonContent.readUint(string.concat(attestationPath, ".inputs.version")));
        uint256 expectedAmount = jsonContent.readUint(string.concat(attestationPath, ".inputs.amount"));
        uint32 expectedRemoteDomain =
            uint32(jsonContent.readUint(string.concat(attestationPath, ".inputs.remoteDomain")));
        bytes32 expectedRemoteToken = jsonContent.readBytes32(string.concat(attestationPath, ".inputs.remoteToken"));
        bytes32 expectedRemoteRecipient =
            jsonContent.readBytes32(string.concat(attestationPath, ".inputs.remoteRecipient"));
        bytes32 expectedLocalToken = jsonContent.readBytes32(string.concat(attestationPath, ".inputs.localToken"));
        bytes32 expectedLocalDepositor =
            jsonContent.readBytes32(string.concat(attestationPath, ".inputs.localDepositor"));
        uint256 expectedMaxFee = jsonContent.readUint(string.concat(attestationPath, ".inputs.maxFee"));
        bytes32 expectedNonce = jsonContent.readBytes32(string.concat(attestationPath, ".inputs.nonce"));
        bytes memory expectedHookData = jsonContent.readBytes(string.concat(attestationPath, ".inputs.hookData"));

        // Validate each field matches the expected values from JSON
        assertEq(decodedIntent.version, expectedVersion, "Decoded version mismatch");
        assertEq(decodedIntent.amount, expectedAmount, "Decoded amount mismatch");
        assertEq(decodedIntent.remoteDomain, expectedRemoteDomain, "Decoded remoteDomain mismatch");
        assertEq(decodedIntent.remoteToken, expectedRemoteToken, "Decoded remoteToken mismatch");
        assertEq(decodedIntent.remoteRecipient, expectedRemoteRecipient, "Decoded remoteRecipient mismatch");
        assertEq(decodedIntent.localToken, expectedLocalToken, "Decoded localToken mismatch");
        assertEq(decodedIntent.localDepositor, expectedLocalDepositor, "Decoded localDepositor mismatch");
        assertEq(decodedIntent.maxFee, expectedMaxFee, "Decoded maxFee mismatch");
        assertEq(decodedIntent.nonce, expectedNonce, "Decoded nonce mismatch");
        assertEq(decodedIntent.hookData, expectedHookData, "Decoded hookData mismatch");
    }
}
