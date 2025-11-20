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

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {
    EIP1271_VALID_SIGNATURE_MAGIC,
    EIP1271_INVALID_SIGNATURE_MAGIC,
    VALID_PERSISTENT_SIGNATURE_MAGIC
} from "../../../src/common/Constants.sol";
import {UnauthorizedCaller, ZeroAddress} from "../../../src/common/Errors.sol";
import {Attestable, AttestableStorage} from "../../../src/modules/remote-domain-depositor/Attestable.sol";

contract AttestableHarness is Attestable {
    function initialize(
        address owner,
        address domainManager,
        address domainPauser,
        address[] memory attesters,
        uint256 signatureThreshold,
        uint256 persistentSignatureBufferDelayBlocks
    ) external initializer {
        __Ownable_init(owner);
        __DomainManageable_init(domainManager, domainPauser);
        __Attestable_init(attesters, signatureThreshold, persistentSignatureBufferDelayBlocks);
    }
}

contract AttestableTest is Test {
    AttestableHarness private attestable;

    address private owner = makeAddr("owner");
    address private domainManager = makeAddr("domainManager");
    address private newDomainManager = makeAddr("newDomainManager");
    address private attester1 = makeAddr("attester1");
    address private attester2 = makeAddr("attester2");
    address private attester3 = makeAddr("attester3");
    address private nonAttester = makeAddr("nonAttester");

    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum

    function setUp() public {
        attestable = new AttestableHarness();

        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        attestable.initialize(
            owner,
            domainManager,
            makeAddr("domainPauser"),
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );
    }

    /// @notice Helper function to generate attestation from an array of private keys
    /// @param privateKeys Array of private keys to sign with
    /// @param digest The message digest to sign
    /// @return attestation The concatenated signature bytes
    function generateAttestation(uint256[] memory privateKeys, bytes32 digest) internal pure returns (bytes memory) {
        bytes memory attestation;

        for (uint256 i = 0; i < privateKeys.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeys[i], digest);
            bytes memory sig = abi.encodePacked(r, s, v);
            attestation = bytes.concat(attestation, sig);
        }

        return attestation;
    }

    function generateAttestation(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = privateKey;
        return generateAttestation(privateKeys, digest);
    }

    // ============ Storage Slot Tests ============

    function test_storageSlot_correctlyCalculated() public pure {
        // Calculate the expected storage slot
        bytes32 expectedSlot =
            keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Attestable"))) - 1)) & ~bytes32(uint256(0xff));

        // Assert they match
        assertEq(AttestableStorage.SLOT, expectedSlot, "Storage slot should match the EIP-7201 calculation");
    }

    // ============ Initialization Tests ============

    function test_initialization_success() public view {
        // Verify initial state
        assertEq(attestable.owner(), owner, "Owner should be set correctly");
        assertEq(attestable.domainManager(), domainManager, "Domain manager should be set correctly");
        assertEq(attestable.signatureThreshold(), SIGNATURE_THRESHOLD, "Signature threshold should be set correctly");
        assertEq(attestable.numPersistentEnabledAttesters(), 3, "Should have 3 enabled attesters");

        // Verify all attesters are enabled
        assertTrue(attestable.isAttesterEnabled(attester1), "Attester1 should be enabled");
        assertTrue(attestable.isAttesterEnabled(attester2), "Attester2 should be enabled");
        assertTrue(attestable.isAttesterEnabled(attester3), "Attester3 should be enabled");

        // Verify non-attester is not enabled
        assertFalse(attestable.isAttesterEnabled(nonAttester), "Non-attester should not be enabled");
    }

    function test_initialization_minimumAttesters() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory twoAttesters = new address[](2);
        twoAttesters[0] = attester1;
        twoAttesters[1] = attester2;

        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), twoAttesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        assertEq(newAttestable.numPersistentEnabledAttesters(), 2, "Should have 2 enabled attesters");
        assertTrue(newAttestable.isAttesterEnabled(attester1), "Attester1 should be enabled");
        assertTrue(newAttestable.isAttesterEnabled(attester2), "Attester2 should be enabled");
        assertEq(newAttestable.signatureThreshold(), 2, "Signature threshold should be 2");
    }

    function test_initialization_multipleAttesters() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory attesters = new address[](5);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");
        attesters[4] = makeAddr("attester5");

        uint256 threshold = 3;
        newAttestable.initialize(
            owner,
            domainManager,
            makeAddr("domainPauser"),
            attesters,
            threshold,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        assertEq(newAttestable.numPersistentEnabledAttesters(), 5, "Should have 5 enabled attesters");
        assertTrue(newAttestable.isAttesterEnabled(attester1), "Attester1 should be enabled");
        assertTrue(newAttestable.isAttesterEnabled(attester2), "Attester2 should be enabled");
        assertTrue(newAttestable.isAttesterEnabled(attester3), "Attester3 should be enabled");
        assertTrue(newAttestable.isAttesterEnabled(attesters[3]), "Attester4 should be enabled");
        assertTrue(newAttestable.isAttesterEnabled(attesters[4]), "Attester5 should be enabled");
        assertEq(newAttestable.signatureThreshold(), threshold, "Signature threshold should be set correctly");
    }

    function test_initialization_revertIfZeroAddress() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory attesters = new address[](1);
        attesters[0] = address(0);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        newAttestable.initialize(
            owner,
            domainManager,
            makeAddr("domainPauser"),
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );
    }

    function test_initialization_revertIfDuplicateAttester() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory attesters = new address[](2);
        attesters[0] = attester1;
        attesters[1] = attester1;

        vm.expectRevert(abi.encodeWithSelector(Attestable.AttesterAlreadyEnabled.selector, attester1));
        newAttestable.initialize(
            owner,
            domainManager,
            makeAddr("domainPauser"),
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );
    }

    function test_initialization_revertIfSignatureThresholdTooHigh() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory attesters = new address[](1);
        attesters[0] = attester1;

        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdTooHigh.selector, 4, 1));
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 4, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );
    }

    function test_initialization_revertIfSignatureThresholdZero() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory attesters = new address[](1);
        attesters[0] = attester1;

        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdZero.selector));
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 0, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );
    }

    function test_initialization_revertIfSignatureThresholdBelowMinimum() public {
        AttestableHarness newAttestable = new AttestableHarness();
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdBelowMinimum.selector, 1, 2));
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 1, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );
    }

    // ============ View Functions Tests ============

    function test_signatureThreshold_returnsCorrectValue() public view {
        assertEq(attestable.signatureThreshold(), SIGNATURE_THRESHOLD, "Should return correct signature threshold");
    }

    function test_domainManager_returnsCorrectValue() public view {
        assertEq(attestable.domainManager(), domainManager, "Should return correct domain manager");
    }

    function test_numEnabledAttesters_returnsCorrectCount() public view {
        assertEq(attestable.numPersistentEnabledAttesters(), 3, "Should return correct number of enabled attesters");
    }

    function test_isAttesterEnabled_returnsCorrectStatus() public view {
        assertTrue(attestable.isAttesterEnabled(attester1), "Attester1 should be enabled");
        assertTrue(attestable.isAttesterEnabled(attester2), "Attester2 should be enabled");
        assertTrue(attestable.isAttesterEnabled(attester3), "Attester3 should be enabled");
        assertFalse(attestable.isAttesterEnabled(nonAttester), "Non-attester should not be enabled");
    }

    function test_getEnabledAttesters_returnsAllAttesters() public view {
        address[] memory enabledAttesters = attestable.persistentEnabledAttesters();
        assertEq(enabledAttesters.length, 3, "Should return all 3 enabled attesters");

        // Check that all initial attesters are in the returned array
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;

        for (uint256 i = 0; i < enabledAttesters.length; i++) {
            if (enabledAttesters[i] == attester1) found1 = true;
            if (enabledAttesters[i] == attester2) found2 = true;
            if (enabledAttesters[i] == attester3) found3 = true;
        }

        assertTrue(found1, "Attester1 should be in the enabled attesters array");
        assertTrue(found2, "Attester2 should be in the enabled attesters array");
        assertTrue(found3, "Attester3 should be in the enabled attesters array");
    }

    function test_nextSignatureThreshold_returnsCorrectValue() public view {
        assertEq(
            attestable.nextSignatureThreshold(),
            SIGNATURE_THRESHOLD,
            "Should return correct next scheduled signature threshold"
        );
    }

    function test_nextSignatureThreshold_duringThresholdUpdate() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initially, next scheduled threshold should equal current threshold
        assertEq(delayAttestable.nextSignatureThreshold(), 2, "Initial scheduled threshold should be 2");
        assertEq(delayAttestable.signatureThreshold(), 2, "Initial current threshold should be 2");

        // Increase threshold - should trigger delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Next scheduled threshold should show the new value (3)
        assertEq(delayAttestable.nextSignatureThreshold(), 3, "Scheduled threshold should be 3 during delay");
        // Current threshold should remain 2 during delay
        assertEq(delayAttestable.signatureThreshold(), 2, "Current threshold should remain 2 during delay");
    }

    function test_nextSignatureThreshold_afterDelayExpires() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold - triggers delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Fast forward past delay
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        // Both should return the new threshold (3)
        assertEq(delayAttestable.nextSignatureThreshold(), 3, "Scheduled threshold should be 3 after delay");
        assertEq(delayAttestable.signatureThreshold(), 3, "Current threshold should be 3 after delay");
    }

    function test_nextSignatureThreshold_decreaseWithDelay() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 3, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Decrease threshold - now also has a delay to allow signature regeneration
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(2);

        // During buffer period, old threshold is still active
        assertEq(delayAttestable.signatureThreshold(), 3, "Current threshold should still be 3 during buffer");
        assertEq(delayAttestable.nextSignatureThreshold(), 2, "Next threshold should be 2");
        assertNotEq(delayAttestable.signatureThresholdValidUntilBlock(), 0, "Delay should be applied for decrease");

        // After buffer period, new threshold is active
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);
        assertEq(delayAttestable.signatureThreshold(), 2, "Current threshold should be 2 after buffer");
    }

    // ============ Enable Attester Tests ============

    function test_enableAttester_success() public {
        // Remove an attester first
        vm.prank(domainManager);
        attestable.disableAttester(attester1);

        // Advance past the delay to actually disable the attester
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);
        assertFalse(attestable.isAttesterEnabled(attester1), "Attester1 should be disabled");

        // Re-enable the attester
        vm.expectEmit(true, false, false, false, address(attestable));
        emit Attestable.AttesterEnabled(attester1);

        vm.prank(domainManager);
        attestable.enableAttester(attester1);

        assertTrue(attestable.isAttesterEnabled(attester1), "Attester1 should be enabled again");
        assertEq(attestable.numPersistentEnabledAttesters(), 3, "Should have 3 enabled attesters");
    }

    function test_enableAttester_newAttester() public {
        address newAttester = makeAddr("newAttester");

        assertFalse(attestable.isAttesterEnabled(newAttester), "New attester should not be enabled initially");

        vm.expectEmit(true, false, false, false, address(attestable));
        emit Attestable.AttesterEnabled(newAttester);

        vm.prank(domainManager);
        attestable.enableAttester(newAttester);

        assertTrue(attestable.isAttesterEnabled(newAttester), "New attester should be enabled");
        assertEq(attestable.numPersistentEnabledAttesters(), 4, "Should have 4 enabled attesters");
    }

    function test_enableAttester_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.prank(domainManager);
        attestable.enableAttester(address(0));
    }

    function test_enableAttester_revertIfAlreadyEnabled() public {
        vm.expectRevert(abi.encodeWithSelector(Attestable.AttesterAlreadyEnabled.selector, attester1));

        vm.prank(domainManager);
        attestable.enableAttester(attester1); // Already enabled
    }

    function test_enableAttester_revertIfNotDomainManager() public {
        address newAttester = makeAddr("newAttester");

        // Test that non-attester-manager cannot enable attesters
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.prank(owner); // owner is not the domain manager
        attestable.enableAttester(newAttester);
    }

    // ============ Disable Attester Tests ============

    function test_disableAttester_success() public {
        assertTrue(attestable.isAttesterEnabled(attester1), "Attester1 should be enabled initially");

        vm.expectEmit(true, false, false, false, address(attestable));
        emit Attestable.AttesterDisabled(attester1, block.number);

        vm.prank(domainManager);
        attestable.disableAttester(attester1);

        // With buffer delay, attester should still be enabled but marked for removal
        assertTrue(attestable.isAttesterEnabled(attester1), "Attester1 should still be enabled during delay");
        assertEq(attestable.numPersistentEnabledAttesters(), 2, "Should have 2 persistent attesters after removal");
        assertEq(
            attestable.attesterValidUntilBlock(attester1),
            block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            "Should have expiry block set correctly"
        );
    }

    function test_disableAttester_revertIfWouldBelowThreshold() public {
        vm.prank(domainManager);
        attestable.setSignatureThreshold(3);

        // At this point, we have 3 attesters and threshold is 3
        vm.expectRevert(abi.encodeWithSelector(Attestable.NotEnoughAttestersForSigThreshold.selector, 3, 3));
        vm.prank(domainManager);
        attestable.disableAttester(attester1);
    }

    function test_disableAttester_revertIfNotEnabled() public {
        // Add a new attester so we have 4 total
        address newAttester = makeAddr("newAttester");
        vm.prank(domainManager);
        attestable.enableAttester(newAttester);

        // Disable one attester (leaving 3)
        vm.prank(domainManager);
        attestable.disableAttester(attester1);

        // Try to disable the already disabled attester - should get "Attester not enabled"
        // because we still have >1 attesters and >threshold
        vm.expectRevert(abi.encodeWithSelector(Attestable.AttesterAlreadyDisabled.selector, attester1));
        vm.prank(domainManager);
        attestable.disableAttester(attester1); // Already disabled
    }

    function test_disableAttester_revertIfNeverEnabled() public {
        vm.expectRevert(abi.encodeWithSelector(Attestable.AttesterAlreadyDisabled.selector, nonAttester));
        vm.prank(domainManager);
        attestable.disableAttester(nonAttester);
    }

    function test_disableAttester_revertIfNotDomainManager() public {
        // Test that non-attester-manager cannot disable attesters
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.prank(owner); // owner is not the domain manager
        attestable.disableAttester(attester1);
    }

    // ============ Set Signature Threshold Tests ============

    function test_setSignatureThreshold_success() public {
        // Enable a fourth attester so we can increase beyond 3
        vm.prank(domainManager);
        attestable.enableAttester(makeAddr("attester4"));

        // Test increasing threshold
        uint256 newThreshold = 3;
        uint256 oldThreshold = attestable.signatureThreshold();
        assertEq(oldThreshold, 2, "Initial threshold should be 2");

        vm.expectEmit(true, true, false, false, address(attestable));
        emit Attestable.SignatureThresholdUpdated(oldThreshold, newThreshold);

        vm.prank(domainManager);
        attestable.setSignatureThreshold(newThreshold);

        // During buffer period, old threshold is still active
        assertEq(attestable.signatureThreshold(), oldThreshold, "Old threshold should be active during buffer");
        assertEq(attestable.nextSignatureThreshold(), newThreshold, "Next threshold should be scheduled");

        // After buffer period, new threshold is active
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);
        assertEq(attestable.signatureThreshold(), newThreshold, "New threshold should be active after buffer");
    }

    function test_setSignatureThreshold_revertIfZero() public {
        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdZero.selector));

        vm.prank(domainManager);
        attestable.setSignatureThreshold(0);
    }

    function test_setSignatureThreshold_revertIfBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdBelowMinimum.selector, 1, 2));

        vm.prank(domainManager);
        attestable.setSignatureThreshold(1);
    }

    function test_setSignatureThreshold_revertIfTooHigh() public {
        uint256 tooHighThreshold = 5; // We only have 3 attesters

        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdTooHigh.selector, 5, 3));

        vm.prank(domainManager);
        attestable.setSignatureThreshold(tooHighThreshold);
    }

    function test_setSignatureThreshold_revertIfSameValue() public {
        uint256 currentThreshold = attestable.signatureThreshold();

        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdAlreadySet.selector, 2));

        vm.prank(domainManager);
        attestable.setSignatureThreshold(currentThreshold);
    }

    function test_setSignatureThreshold_revertIfNotDomainManager() public {
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.prank(owner); // owner is not the domain manager
        attestable.setSignatureThreshold(3);
    }

    // ============ Is Valid Signature Tests ============

    function test_isValidSignature_happyPath_twoValidSignatures() public {
        // Use the default threshold of 2
        // Prepare message
        bytes memory message = abi.encodePacked("hello world");

        // Prepare signatures from attester1 and attester2 (use makeAddrAndKey to get consistent addresses)
        (, uint256 privKey1) = makeAddrAndKey("attester1");
        (, uint256 privKey2) = makeAddrAndKey("attester2");

        bytes32 digest = keccak256(message);

        // Generate attestation with 2 signatures in order
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;
        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = attestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );
    }

    function test_isValidSignature_happyPath_threeValidSignatures() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate three different attester addresses with their private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer2");
        (address addr2, uint256 privKey2) = makeAddrAndKey("signer1");
        (address addr3, uint256 privKey3) = makeAddrAndKey("signer3");

        // Initialize with sorted attesters
        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 3, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation
        uint256[] memory privateKeys = new uint256[](3);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;
        privateKeys[2] = privKey3;

        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );
    }

    function test_isValidSignature_happyPath_dualValidity_thresholdIncrease() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate three different attester addresses with their private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer2");
        (address addr2, uint256 privKey2) = makeAddrAndKey("signer1");
        (address addr3, uint256 privKey3) = makeAddrAndKey("signer3");

        // Initialize with the attesters
        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold
        vm.prank(domainManager);
        newAttestable.setSignatureThreshold(3);

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;
        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );

        // Use helper function to generate attestation with the third private key
        uint256[] memory privateKeys2 = new uint256[](3);
        privateKeys2[0] = privKey1;
        privateKeys2[1] = privKey2;
        privateKeys2[2] = privKey3;
        attestation = generateAttestation(privateKeys2, digest);

        result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );
    }

    function test_isValidSignature_happyPath_dualValidity_thresholdDecrease() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate three different attester addresses with their private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer2");
        (address addr2, uint256 privKey2) = makeAddrAndKey("signer1");
        (address addr3, uint256 privKey3) = makeAddrAndKey("signer3");

        // Initialize with the attesters
        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 3, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Decrease threshold
        vm.prank(domainManager);
        newAttestable.setSignatureThreshold(2);

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;
        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );

        // Use helper function to generate attestation with the third private key
        uint256[] memory privateKeys2 = new uint256[](3);
        privateKeys2[0] = privKey1;
        privateKeys2[1] = privKey2;
        privateKeys2[2] = privKey3;
        attestation = generateAttestation(privateKeys2, digest);

        result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );
    }

    function test_isValidSignature_happyPath_dualValidity_attesterDisabled() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate three different attester addresses with their private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer2");
        (address addr2, uint256 privKey2) = makeAddrAndKey("signer1");
        (address addr3,) = makeAddrAndKey("signer3");

        // Initialize with the attesters
        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Disable one attester
        vm.prank(domainManager);
        newAttestable.disableAttester(addr1);

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;
        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_VALID_SIGNATURE_MAGIC, "Should return EIP1271_VALID_SIGNATURE_MAGIC for valid signatures"
        );
    }

    function test_isValidSignature_invalidNumberOfSignaturesDuringDelay() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate three different attester addresses with their private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer2");
        (address addr2,) = makeAddrAndKey("signer1");
        (address addr3,) = makeAddrAndKey("signer3");

        // Initialize with the attesters
        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 3, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Set threshold to 2
        vm.prank(domainManager);
        newAttestable.setSignatureThreshold(2);

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = privKey1;
        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC for invalid number of signatures"
        );
    }

    function test_isValidSignature_invalidLength() public view {
        bytes memory message = "test message";
        bytes memory attestation = "test"; // Too short

        bytes4 result = attestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result, EIP1271_INVALID_SIGNATURE_MAGIC, "Should return EIP1271_INVALID_SIGNATURE_MAGIC for invalid length"
        );
    }

    function test_isValidSignature_emptyAttestation() public view {
        bytes memory message = "test message";
        bytes memory attestation = ""; // Empty

        bytes4 result = attestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC for empty attestation"
        );
    }

    function test_isValidSignature_moreSigsThanNeeded() public {
        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate three different attester addresses with their private keys
        (, uint256 privKey1) = makeAddrAndKey("attester1");
        (, uint256 privKey2) = makeAddrAndKey("attester2");
        (, uint256 privKey3) = makeAddrAndKey("attester3");

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation with 3 signatures (more than threshold of 2)
        uint256[] memory privateKeys = new uint256[](3);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;
        privateKeys[2] = privKey3;

        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = attestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC when more signatures provided than threshold (exact count required)"
        );
    }

    function test_isValidSignature_invalidSignatureOrderOrDuplicate_wrongOrder() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate two different attester addresses with out of order private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("signer2");

        // Initialize with sorted attesters
        address[] memory attesters = new address[](2);
        attesters[0] = addr1;
        attesters[1] = addr2;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation with signatures in wrong order
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;

        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC when signatures are in wrong order"
        );
    }

    function test_isValidSignature_invalidSignatureOrderOrDuplicate_duplicateSignature() public {
        // Create a new instance to avoid InvalidInitialization error
        AttestableHarness newAttestable = new AttestableHarness();

        // Prepare message
        bytes memory message = abi.encodePacked("three signers test");

        // Generate two different attester addresses with out of order private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("signer1");
        (address addr2,) = makeAddrAndKey("foo");

        // Initialize with sorted attesters
        address[] memory attesters = new address[](2);
        attesters[0] = addr1;
        attesters[1] = addr2;
        newAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes32 digest = keccak256(message);

        // Use helper function to generate attestation with duplicate private key
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey1; // Duplicate private key - creates duplicate signature

        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = newAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC when there are duplicate signatures"
        );
    }

    function test_isValidSignature_signerIsNotAttester() public {
        (, uint256 enabledPrivKey) = makeAddrAndKey("attester1");
        (, uint256 privKey) = makeAddrAndKey("non-attestor"); // This won't be an enabled attester

        bytes memory message = abi.encodePacked("non-attester test");
        bytes32 digest = keccak256(message);

        // Generate attestation with one valid and one invalid signer
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = enabledPrivKey; // Valid attester
        privateKeys[1] = privKey; // Invalid attester

        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = attestable.isValidSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC for non-attester signer"
        );
    }

    function test_isValidSignature_revertIfThresholdZero() public {
        AttestableHarness newAttestable = new AttestableHarness();

        // If the contract is not initialized, signature threshold will be zero
        bytes4 result = newAttestable.isValidSignature(keccak256("test message"), "test");
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should return EIP1271_INVALID_SIGNATURE_MAGIC for non-attester signer"
        );
    }

    // ============ Mixed Operations ============

    function test_multipleOperations_scenario() public {
        // Start with 3 attesters, threshold 2
        assertEq(attestable.numPersistentEnabledAttesters(), 3, "Should start with 3 attesters");

        // Add a new attester
        address newAttester = makeAddr("newAttester");
        vm.prank(domainManager);
        attestable.enableAttester(newAttester);
        assertEq(attestable.numPersistentEnabledAttesters(), 4, "Should have 4 attesters after adding");

        // Disable two attesters (leaving 2, which meets threshold)
        vm.startPrank(domainManager);
        attestable.disableAttester(attester1);
        attestable.disableAttester(attester2);
        vm.stopPrank();

        assertEq(attestable.numPersistentEnabledAttesters(), 2, "Should have 2 attesters after disabling");
        assertTrue(attestable.isAttesterEnabled(attester3), "Attester3 should still be enabled");
        assertTrue(attestable.isAttesterEnabled(newAttester), "New attester should still be enabled");

        // Change domain manager
        vm.prank(owner);
        attestable.updateDomainManager(newDomainManager);

        // New domain manager should be able to add attesters
        address anotherAttester = makeAddr("anotherAttester");
        vm.prank(newDomainManager);
        attestable.enableAttester(anotherAttester);

        assertEq(attestable.numPersistentEnabledAttesters(), 3, "Should have 3 attesters after new manager adds one");
        assertTrue(attestable.isAttesterEnabled(anotherAttester), "Another attester should be enabled");
    }

    function test_enableDisable_sameAttesterMultipleTimes() public {
        // Disable attester1
        vm.prank(domainManager);
        attestable.disableAttester(attester1);
        // Advance past the delay to actually disable the attester
        uint256 blockAfterFirstDisable = block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1;
        vm.roll(blockAfterFirstDisable);
        assertFalse(attestable.isAttesterEnabled(attester1), "Should be disabled");

        // Enable attester1
        vm.prank(domainManager);
        attestable.enableAttester(attester1);
        assertTrue(attestable.isAttesterEnabled(attester1), "Should be enabled");

        // Disable attester1 again
        vm.prank(domainManager);
        attestable.disableAttester(attester1);
        // Advance past the delay to actually disable the attester again
        uint256 blockAfterSecondDisable = blockAfterFirstDisable + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1;
        vm.roll(blockAfterSecondDisable);
        assertFalse(attestable.isAttesterEnabled(attester1), "Should be disabled again");

        // Enable attester1 again
        vm.prank(domainManager);
        attestable.enableAttester(attester1);
        assertTrue(attestable.isAttesterEnabled(attester1), "Should be enabled again");
    }

    // ============ Time Delay Functionality Tests ============

    function test_setPersistentSignatureBufferDelay() public {
        uint256 newDelay = 200;

        vm.prank(owner);
        attestable.setPersistentSignatureBufferDelay(newDelay);

        assertEq(attestable.persistentSignatureBufferDelayBlocks(), newDelay, "Should update delay");
    }

    function test_setPersistentSignatureBufferDelay_revertUnauthorized() public {
        address unauthorizedCaller = makeAddr("unauthorizedCaller");
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedCaller)
        );
        vm.prank(unauthorizedCaller);
        attestable.setPersistentSignatureBufferDelay(PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS);
    }

    function test_setPersistentSignatureBufferDelay_revertSameValue() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Attestable.PersistentSignatureBufferDelayAlreadySet.selector, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
            )
        );
        attestable.setPersistentSignatureBufferDelay(PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS);
    }

    function test_setPersistentSignatureBufferDelay_revertZeroDelay() public {
        // Try to set delay to zero - should revert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Attestable.PersistentSignatureBufferDelayZero.selector));
        attestable.setPersistentSignatureBufferDelay(0);
    }

    function test_disableAttesterWithDelay() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Attester should be enabled initially
        assertTrue(delayAttestable.isAttesterEnabled(attester1), "Attester1 should be enabled");
        assertEq(delayAttestable.attesterValidUntilBlock(attester1), 0, "Should have no expiry initially");

        // Initiate disable
        vm.prank(domainManager);
        delayAttestable.disableAttester(attester1);

        // Should still be considered enabled due to delay
        assertTrue(delayAttestable.isAttesterEnabled(attester1), "Attester1 should still be enabled during delay");
        assertEq(
            delayAttestable.attesterValidUntilBlock(attester1),
            block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            "Should have correct expiry block"
        );

        // Should be removed from persistent set immediately
        assertEq(delayAttestable.numPersistentEnabledAttesters(), 2, "Should have 2 persistent attesters after removal");
    }

    function test_attesterExpiry() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initiate disable
        vm.prank(domainManager);
        delayAttestable.disableAttester(attester1);

        // Fast forward past expiry
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        // Should now be considered disabled
        assertFalse(delayAttestable.isAttesterEnabled(attester1), "Attester1 should be disabled after expiry");
        assertTrue(delayAttestable.isAttesterEnabled(attester2), "Attester2 should still be enabled");
    }

    function test_disableAttester_revertAlreadyDisabled() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initiate disable
        vm.prank(domainManager);
        delayAttestable.disableAttester(attester1);

        // Try to disable again - should revert
        vm.prank(domainManager);
        vm.expectRevert(abi.encodeWithSelector(Attestable.AttesterAlreadyDisabled.selector, attester1));
        delayAttestable.disableAttester(attester1);
    }

    function test_enableAttester_clearsPendingDisable() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initiate disable
        vm.prank(domainManager);
        delayAttestable.disableAttester(attester1);

        assertGt(delayAttestable.attesterValidUntilBlock(attester1), 0, "Should have pending disable");

        // Re-enable attester
        vm.prank(domainManager);
        delayAttestable.enableAttester(attester1);

        assertEq(delayAttestable.attesterValidUntilBlock(attester1), 0, "Should clear pending disable");
        assertTrue(delayAttestable.isAttesterEnabled(attester1), "Should be enabled again");
    }

    // ============ Persistent Signature Validation Tests ============

    function test_isValidPersistentSignature_validSignature() public {
        AttestableHarness delayAttestable = new AttestableHarness();

        // Create attesters with known private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("persistentSigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("persistentSigner2");
        address addr3 = makeAddr("persistentSigner3");

        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes memory message = "test message";
        bytes32 digest = keccak256(message);

        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey1;
        privateKeys[1] = privKey2;

        bytes memory attestation = generateAttestation(privateKeys, digest);

        bytes4 result = delayAttestable.isValidPersistentSignature(keccak256(message), attestation);
        assertEq(result, VALID_PERSISTENT_SIGNATURE_MAGIC, "Should return valid persistent signature magic");
    }

    function test_isValidPersistentSignature_withPendingDisable() public {
        AttestableHarness delayAttestable = new AttestableHarness();

        // Create attesters with known private keys
        address addr1 = makeAddr("pendingSigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("pendingSigner3");
        (address addr3, uint256 privKey3) = makeAddrAndKey("pendingSigner2");

        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initiate disable for addr1
        vm.prank(domainManager);
        delayAttestable.disableAttester(addr1);

        bytes memory message = "test message";
        bytes32 digest = keccak256(message);

        // Ensure signatures are in ascending order
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = privKey2;
        privateKeys[1] = privKey3;

        bytes memory attestation = generateAttestation(privateKeys, digest);

        // Standard validation should work (addr2 and addr3 still valid)
        bytes4 result1 = delayAttestable.isValidSignature(keccak256(message), attestation);
        assertEq(result1, EIP1271_VALID_SIGNATURE_MAGIC, "Should be valid with standard validation");

        // Persistent validation should also work (addr2 and addr3 still in persistent set)
        bytes4 result2 = delayAttestable.isValidPersistentSignature(keccak256(message), attestation);
        assertEq(result2, VALID_PERSISTENT_SIGNATURE_MAGIC, "Should be valid with persistent validation");
    }

    function test_isValidPersistentSignature_afterExpiry() public {
        AttestableHarness delayAttestable = new AttestableHarness();

        // Create attesters with known private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("expirySigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("expirySigner2");
        (address addr3, uint256 privKey3) = makeAddrAndKey("expirySigner3");

        address[] memory attesters = new address[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initiate disable for addr1
        vm.prank(domainManager);
        delayAttestable.disableAttester(addr1);

        // Fast forward past expiry
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        bytes memory message = "test message";
        bytes32 messageHash = keccak256(message);

        // Test with disabled attester - should fail
        {
            uint256[] memory keys = new uint256[](2);
            keys[0] = privKey1;
            keys[1] = privKey2;
            bytes memory sig = generateAttestation(keys, messageHash);

            bytes4 result = delayAttestable.isValidPersistentSignature(messageHash, sig);
            assertEq(result, EIP1271_INVALID_SIGNATURE_MAGIC, "Should be invalid with disabled attester");
        }

        // Test with valid attesters - should work
        {
            uint256[] memory keys = new uint256[](2);
            keys[0] = privKey3;
            keys[1] = privKey2;
            bytes memory sig = generateAttestation(keys, messageHash);

            bytes4 result = delayAttestable.isValidPersistentSignature(messageHash, sig);
            assertEq(result, VALID_PERSISTENT_SIGNATURE_MAGIC, "Should be valid with non-disabled attesters");
        }
    }

    function test_isValidPersistentSignature_moreSigsThanThreshold() public {
        AttestableHarness delayAttestable = new AttestableHarness();

        // Create attesters with known private keys - need to ensure ascending address order
        (address addr1, uint256 privKey1) = makeAddrAndKey("morePersistentSigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("morePersistentSigner2");
        (address addr3, uint256 privKey3) = makeAddrAndKey("morePersistentSigner3");

        // Sort addresses and corresponding private keys
        address[] memory sortedAddrs = new address[](3);
        uint256[] memory sortedKeys = new uint256[](3);
        sortedAddrs[0] = addr1;
        sortedAddrs[1] = addr3;
        sortedAddrs[2] = addr2;
        sortedKeys[0] = privKey1;
        sortedKeys[1] = privKey3;
        sortedKeys[2] = privKey2;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), sortedAddrs, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes memory message = "test message";
        bytes32 digest = keccak256(message);

        bytes memory attestation = generateAttestation(sortedKeys, digest);

        bytes4 result = delayAttestable.isValidPersistentSignature(keccak256(message), attestation);
        assertEq(
            result,
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "Should reject more signatures than threshold (exact count required)"
        );
    }

    // ============ Signature Threshold Time Delay Tests ============

    function test_setSignatureThreshold_increaseTriggersDelay() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Initially, current threshold should be set
        assertEq(delayAttestable.signatureThreshold(), 2, "Initial current threshold should be 2");
        assertEq(delayAttestable.signatureThresholdValidUntilBlock(), 0, "Initial threshold should be persistent");

        // Increase threshold - should trigger delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Current threshold should remain 2 during delay
        assertEq(delayAttestable.signatureThreshold(), 2, "Current threshold should remain 2 during delay");
        assertNotEq(
            delayAttestable.signatureThresholdValidUntilBlock(), 0, "Threshold should not be persistent during delay"
        );
        assertEq(
            delayAttestable.signatureThresholdValidUntilBlock(),
            block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            "Should have correct validity block"
        );
    }

    function test_setSignatureThreshold_decreaseWithDelay() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 3, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Decrease threshold - now also has a delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(2);

        // During buffer period, old threshold is still active
        assertEq(delayAttestable.signatureThreshold(), 3, "Old threshold should remain during buffer");
        assertNotEq(delayAttestable.signatureThresholdValidUntilBlock(), 0, "Delay should be applied for decrease");
        assertEq(delayAttestable.nextSignatureThreshold(), 2, "Next threshold should be 2");

        // After buffer period, new threshold is active
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);
        assertEq(delayAttestable.signatureThreshold(), 2, "Current threshold should be 2 after buffer");
        assertLe(delayAttestable.signatureThresholdValidUntilBlock(), block.number, "Delay should have expired");
    }

    function test_setSignatureThreshold_revertUpdateInProgress() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold - triggers delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Try to update again while update is in progress
        vm.prank(domainManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                Attestable.SignatureThresholdUpdateInProgress.selector,
                3,
                block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
            )
        );
        delayAttestable.setSignatureThreshold(4);
    }

    function test_setSignatureThreshold_delayExpires() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold - triggers delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Fast forward past delay
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        // Now threshold should be updated (but not marked as persistent until next state change)
        assertEq(delayAttestable.signatureThreshold(), 3, "Current threshold should be 3 after delay");

        // The threshold is not marked as persistent until a state-changing operation occurs
        assertNotEq(
            delayAttestable.signatureThresholdValidUntilBlock(),
            0,
            "Threshold not marked persistent until next state change"
        );

        // Trigger a successful state change to mark it as persistent
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(4); // This will trigger the lazy update and set a new threshold

        // Now the old threshold should have been made persistent and a new delay started
        assertEq(delayAttestable.signatureThreshold(), 3, "Current threshold should still be 3 during new delay");
        assertNotEq(delayAttestable.signatureThresholdValidUntilBlock(), 0, "Should be in new delay period");
    }

    function test_setSignatureThreshold_refreshBeforeNewUpdate() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](5);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");
        attesters[4] = makeAddr("attester5");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold - triggers delay
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Fast forward past delay
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        // Set a new threshold - should refresh the previous one first
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(4);

        // Should be able to set another increase now
        assertEq(delayAttestable.signatureThreshold(), 3, "Current threshold should be 3");
        assertNotEq(delayAttestable.signatureThresholdValidUntilBlock(), 0, "Should be in delay again");
    }

    // ============ Signature Validation During Threshold Transitions ============

    function test_isValidSignature_duringThresholdIncrease() public {
        AttestableHarness delayAttestable = new AttestableHarness();

        (address addr1, uint256 privKey1) = makeAddrAndKey("thresholdSigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("thresholdSigner2");
        (address addr3, uint256 privKey3) = makeAddrAndKey("thresholdSigner3");

        // Sort addresses and keys properly
        address[] memory sortedAddrs = new address[](3);
        uint256[] memory sortedKeys = new uint256[](3);
        sortedAddrs[0] = addr3;
        sortedAddrs[1] = addr1;
        sortedAddrs[2] = addr2;
        sortedKeys[0] = privKey3;
        sortedKeys[1] = privKey1;
        sortedKeys[2] = privKey2;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), sortedAddrs, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes32 digest = keccak256("test message");

        // Test with 2 signatures initially (first two in sorted order)
        {
            uint256[] memory twoKeys = new uint256[](2);
            twoKeys[0] = sortedKeys[0];
            twoKeys[1] = sortedKeys[1];
            bytes memory twoSigAttestation = generateAttestation(twoKeys, digest);

            bytes4 result1 = delayAttestable.isValidSignature(digest, twoSigAttestation);
            assertEq(result1, EIP1271_VALID_SIGNATURE_MAGIC, "Should be valid with 2 sigs initially");
        }

        // Increase threshold to 3
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Test 2 signatures during delay period
        {
            uint256[] memory twoKeys = new uint256[](2);
            twoKeys[0] = sortedKeys[0];
            twoKeys[1] = sortedKeys[1];
            bytes memory twoSigAttestation = generateAttestation(twoKeys, digest);

            bytes4 result2 = delayAttestable.isValidSignature(digest, twoSigAttestation);
            assertEq(result2, EIP1271_VALID_SIGNATURE_MAGIC, "Should still be valid with 2 sigs during delay");
        }

        // Fast forward past delay
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        // Test 2 signatures after delay
        {
            uint256[] memory twoKeys = new uint256[](2);
            twoKeys[0] = sortedKeys[0];
            twoKeys[1] = sortedKeys[1];
            bytes memory twoSigAttestation = generateAttestation(twoKeys, digest);

            bytes4 result3 = delayAttestable.isValidSignature(digest, twoSigAttestation);
            assertEq(result3, EIP1271_INVALID_SIGNATURE_MAGIC, "Should be invalid with 2 sigs after delay");
        }

        // Test 3 signatures after delay
        {
            bytes memory threeSigAttestation = generateAttestation(sortedKeys, digest);

            bytes4 result4 = delayAttestable.isValidSignature(digest, threeSigAttestation);
            assertEq(result4, EIP1271_VALID_SIGNATURE_MAGIC, "Should be valid with 3 sigs after delay");
        }
    }

    function test_isValidPersistentSignature_duringThresholdIncrease() public {
        AttestableHarness delayAttestable = new AttestableHarness();

        (address addr1, uint256 privKey1) = makeAddrAndKey("persistentThresholdSigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("persistentThresholdSigner2");
        (address addr3, uint256 privKey3) = makeAddrAndKey("persistentThresholdSigner3");

        // Sort addresses and keys properly
        address[] memory sortedAddrs = new address[](3);
        uint256[] memory sortedKeys = new uint256[](3);

        sortedAddrs[0] = addr3;
        sortedAddrs[1] = addr1;
        sortedAddrs[2] = addr2;
        sortedKeys[0] = privKey3;
        sortedKeys[1] = privKey1;
        sortedKeys[2] = privKey2;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), sortedAddrs, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes32 digest = keccak256("test message");

        // Test with 2 signatures initially
        {
            uint256[] memory twoKeys = new uint256[](2);
            twoKeys[0] = sortedKeys[0];
            twoKeys[1] = sortedKeys[1];
            bytes memory twoSigAttestation = generateAttestation(twoKeys, digest);

            bytes4 result1 = delayAttestable.isValidPersistentSignature(digest, twoSigAttestation);
            assertEq(result1, VALID_PERSISTENT_SIGNATURE_MAGIC, "Should be valid with 2 sigs initially");
        }

        // Increase threshold to 3
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Test 2 signatures after threshold increase
        {
            uint256[] memory twoKeys = new uint256[](2);
            twoKeys[0] = sortedKeys[0];
            twoKeys[1] = sortedKeys[1];
            bytes memory twoSigAttestation = generateAttestation(twoKeys, digest);

            bytes4 result2 = delayAttestable.isValidPersistentSignature(digest, twoSigAttestation);
            assertEq(
                result2, EIP1271_INVALID_SIGNATURE_MAGIC, "Should be invalid with 2 sigs for persistent validation"
            );
        }

        // Test 3 signatures after threshold increase
        {
            bytes memory threeSigAttestation = generateAttestation(sortedKeys, digest);

            bytes4 result3 = delayAttestable.isValidPersistentSignature(digest, threeSigAttestation);
            assertEq(result3, VALID_PERSISTENT_SIGNATURE_MAGIC, "Should be valid with 3 sigs for persistent validation");
        }
    }

    // ============ Attester Disabling During Threshold Transitions ============

    function test_disableAttester_duringThresholdIncrease() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold to 3 (triggers delay)
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Try to disable an attester - should fail because 3 <= 3 (persistent threshold)
        vm.prank(domainManager);
        vm.expectRevert(abi.encodeWithSelector(Attestable.NotEnoughAttestersForSigThreshold.selector, 3, 3));
        delayAttestable.disableAttester(attester1);
    }

    function test_disableAttester_withCurrentAndPersistentThresholds() public {
        AttestableHarness delayAttestable = new AttestableHarness();
        address[] memory attesters = new address[](4);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        attesters[3] = makeAddr("attester4");

        delayAttestable.initialize(
            owner, domainManager, makeAddr("domainPauser"), attesters, 2, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Increase threshold to 3 (triggers delay)
        vm.prank(domainManager);
        delayAttestable.setSignatureThreshold(3);

        // Should be able to disable one attester (4 > 3)
        vm.prank(domainManager);
        delayAttestable.disableAttester(attester1);

        assertEq(delayAttestable.numPersistentEnabledAttesters(), 3, "Should have 3 persistent attesters");

        // Should not be able to disable another (3 <= 3)
        vm.prank(domainManager);
        vm.expectRevert(abi.encodeWithSelector(Attestable.NotEnoughAttestersForSigThreshold.selector, 3, 3));
        delayAttestable.disableAttester(attester2);
    }

    // ============ Validate Magic Values ============

    function test_validatePersistentSignatureMagicValue() public pure {
        assertEq(VALID_PERSISTENT_SIGNATURE_MAGIC, bytes4(keccak256("isValidPersistentSignature(bytes32,bytes)")));
    }

    function test_validateSignatureMagicValue() public pure {
        assertEq(EIP1271_VALID_SIGNATURE_MAGIC, bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    // ============ Threshold Decrease Behavior Tests ============
    // These tests document the IMPORTANT behavior that signatures must have EXACTLY
    // the threshold number of attesters - not more, not less.

    function test_thresholdDecrease_invalidatesSignaturesWithMoreAttesters() public {
        // This test documents the behavior where decreasing threshold invalidates
        // signatures with more attesters than the new threshold
        AttestableHarness testAttestable = new AttestableHarness();

        // Setup with 5 attesters and threshold of 4
        address[] memory attesters = new address[](5);
        uint256[] memory keys = new uint256[](5);

        // Create attesters with their private keys and sort them
        for (uint256 i = 0; i < 5; i++) {
            (address addr, uint256 key) = makeAddrAndKey(string.concat("decreaseSigner", vm.toString(i)));
            attesters[i] = addr;
            keys[i] = key;
        }

        // Bubble sort addresses and corresponding keys
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                if (attesters[i] > attesters[j]) {
                    (attesters[i], attesters[j]) = (attesters[j], attesters[i]);
                    (keys[i], keys[j]) = (keys[j], keys[i]);
                }
            }
        }

        testAttestable.initialize(
            owner,
            domainManager,
            makeAddr("domainPauser"),
            attesters,
            4, // Initial threshold of 4
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        bytes32 digest = keccak256("test message");

        // Create signatures with 4 attesters (matching threshold)
        uint256[] memory fourKeys = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            fourKeys[i] = keys[i];
        }
        bytes memory fourSigAttestation = generateAttestation(fourKeys, digest);

        // Initially, 4 signatures are valid
        assertEq(
            testAttestable.isValidSignature(digest, fourSigAttestation),
            EIP1271_VALID_SIGNATURE_MAGIC,
            "4 signatures should be valid with threshold of 4"
        );

        // Decrease threshold to 2
        vm.prank(domainManager);
        testAttestable.setSignatureThreshold(2);

        // During buffer period, 4 signatures are still valid (old threshold accepted)
        assertEq(
            testAttestable.isValidSignature(digest, fourSigAttestation),
            EIP1271_VALID_SIGNATURE_MAGIC,
            "4 signatures should remain valid during buffer period"
        );

        // After buffer period expires
        vm.roll(block.number + PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS + 1);

        // Now 4 signatures are INVALID (more than new threshold of 2)
        assertEq(
            testAttestable.isValidSignature(digest, fourSigAttestation),
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "4 signatures should be INVALID after buffer - exceeds new threshold of 2"
        );

        // Only exactly 2 signatures are valid now
        uint256[] memory twoKeys = new uint256[](2);
        twoKeys[0] = keys[0];
        twoKeys[1] = keys[1];
        assertEq(
            testAttestable.isValidSignature(digest, generateAttestation(twoKeys, digest)),
            EIP1271_VALID_SIGNATURE_MAGIC,
            "Exactly 2 signatures should be valid with threshold of 2"
        );
    }

    function test_documentExactThresholdRequirement() public {
        // This test explicitly documents that the number of signatures must
        // EXACTLY match the threshold - not more, not less

        // Create a new attestable with known attester keys so we can sign properly
        AttestableHarness testAttestable = new AttestableHarness();

        // Create attesters with known private keys
        (address addr1, uint256 privKey1) = makeAddrAndKey("exactThresholdSigner1");
        (address addr2, uint256 privKey2) = makeAddrAndKey("exactThresholdSigner2");
        (address addr3, uint256 privKey3) = makeAddrAndKey("exactThresholdSigner3");

        // Sort addresses and corresponding private keys
        address[] memory attesters = new address[](3);
        uint256[] memory sortedKeys = new uint256[](3);
        attesters[0] = addr1;
        attesters[1] = addr2;
        attesters[2] = addr3;
        sortedKeys[0] = privKey1;
        sortedKeys[1] = privKey2;
        sortedKeys[2] = privKey3;

        // Bubble sort attesters and keys by address
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (attesters[i] > attesters[j]) {
                    (attesters[i], attesters[j]) = (attesters[j], attesters[i]);
                    (sortedKeys[i], sortedKeys[j]) = (sortedKeys[j], sortedKeys[i]);
                }
            }
        }

        testAttestable.initialize(
            owner,
            domainManager,
            makeAddr("domainPauser"),
            attesters,
            2, // Threshold of 2
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Test with threshold of 2
        assertEq(testAttestable.signatureThreshold(), 2, "Initial threshold should be 2");

        bytes32 digest = keccak256("exact threshold test");

        // 1 signature: INVALID (too few)
        assertEq(
            testAttestable.isValidSignature(digest, generateAttestation(sortedKeys[0], digest)),
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "1 signature is invalid when threshold is 2 (too few)"
        );

        // 2 signatures: VALID (exact match) - use first two sorted keys
        uint256[] memory twoKeys = new uint256[](2);
        twoKeys[0] = sortedKeys[0];
        twoKeys[1] = sortedKeys[1];
        assertEq(
            testAttestable.isValidSignature(digest, generateAttestation(twoKeys, digest)),
            EIP1271_VALID_SIGNATURE_MAGIC,
            "2 signatures are valid when threshold is 2 (exact match)"
        );

        // 3 signatures: INVALID (too many) - use all three sorted keys
        uint256[] memory threeKeys = new uint256[](3);
        threeKeys[0] = sortedKeys[0];
        threeKeys[1] = sortedKeys[1];
        threeKeys[2] = sortedKeys[2];
        assertEq(
            testAttestable.isValidSignature(digest, generateAttestation(threeKeys, digest)),
            EIP1271_INVALID_SIGNATURE_MAGIC,
            "3 signatures are invalid when threshold is 2 - MUST BE EXACT MATCH (too many)"
        );
    }
}
