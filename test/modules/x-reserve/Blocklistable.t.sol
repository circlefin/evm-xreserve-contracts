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
import {UnauthorizedCaller, ZeroAddress} from "src/common/Errors.sol";
import {Blocklistable, BlocklistableStorage} from "src/modules/x-reserve/Blocklistable.sol";

contract BlocklistableHarness is Blocklistable {
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
    }

    // Helper function to test the onlyBlocklister modifier
    function verifyOnlyBlocklisterModifier() public onlyBlocklister {}
}

// Additional harness that calls __Blocklistable_init during initialization for coverage
contract BlocklistableHarnessWithInit is Blocklistable {
    function initialize(address owner, address blocklister_) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
        __Blocklistable_init(blocklister_);
    }

    // Helper function to test the onlyBlocklister modifier
    function verifyOnlyBlocklisterModifier() public onlyBlocklister {}
}

// Harness that supports reinitialization to call __Blocklistable_init again
contract BlocklistableHarnessWithReinit is Blocklistable {
    function initialize(address owner, address blocklister_) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
        __Blocklistable_init(blocklister_);
    }

    // Reinitializer to simulate an upgrade that re-runs the module init
    function reinit(address newBlocklister) public reinitializer(2) {
        __Blocklistable_init(newBlocklister);
    }

    function verifyOnlyBlocklisterModifier() public onlyBlocklister {}
}

contract BlocklistableTest is Test {
    BlocklistableHarness private blocklistable;

    address private owner = makeAddr("owner");
    address private blocklister = makeAddr("blocklister");
    address private otherBlocklister = makeAddr("otherBlocklister");

    uint32 private constant REMOTE_DOMAIN = 123;
    uint32 private constant OTHER_DOMAIN = 456;
    bytes32 private constant REMOTE_ADDRESS = bytes32(uint256(0xdeadbeef));
    bytes32 private constant OTHER_ADDRESS = bytes32(uint256(0xcafebabe));

    function setUp() public {
        blocklistable = new BlocklistableHarness();
        blocklistable.initialize(owner);
    }

    function test_storageSlot_correctlyCalculated() public pure {
        // Calculate the expected storage slot
        bytes32 expectedSlot = keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Blocklistable"))) - 1))
            & ~bytes32(uint256(0xff));

        // Assert they match
        assertEq(BlocklistableStorage.SLOT, expectedSlot, "Storage slot should match the EIP-7201 calculation");
    }

    function test_blocklistableInit_setsBlocklisterDuringInitialization() public {
        // This test provides coverage for the __Blocklistable_init function
        // by using a separate harness that calls it during initialization
        BlocklistableHarnessWithInit blocklistableWithInit = new BlocklistableHarnessWithInit();

        // Initialize with both owner and blocklister
        blocklistableWithInit.initialize(owner, blocklister);

        // Verify blocklister is set correctly after initialization
        assertEq(blocklistableWithInit.blocklister(), blocklister, "Blocklister should be set during initialization");
        assertEq(blocklistableWithInit.owner(), owner, "Owner should be set during initialization");

        // Verify the blocklister can perform operations
        vm.prank(blocklister);
        blocklistableWithInit.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(
            blocklistableWithInit.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Blocklister should be able to blocklist addresses"
        );
    }

    function test_initialState() public {
        // Verify no blocklister is set initially
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(blocklister);
        blocklistable.verifyOnlyBlocklisterModifier();

        // Verify random domain+address pair is not blocklisted initially
        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should not be blocklisted by default"
        );

        // Verify owner is set correctly after initialization
        assertEq(blocklistable.owner(), owner, "Owner should be set after initialization");
    }

    function test_initialization_success() public view {
        assertEq(blocklistable.blocklister(), address(0), "Blocklister should be zero address after initialization");
        assertEq(blocklistable.owner(), owner, "Owner should be set after initialization");
    }

    function test_updateBlocklister_basicSuccess() public {
        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.BlocklisterUpdated(address(0), blocklister);

        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        // Verify blocklister can blocklist addresses
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted by blocklister"
        );
    }

    function test_updateBlocklister_changeBlocklister() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.BlocklisterUpdated(blocklister, otherBlocklister);

        // Update to new blocklister
        vm.prank(owner);
        blocklistable.updateBlocklister(otherBlocklister);

        // Verify new blocklister can blocklist addresses
        vm.prank(otherBlocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should be blocklisted by new blocklister"
        );

        // Verify old blocklister cannot blocklist addresses
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, OTHER_ADDRESS);
    }

    function test_updateBlocklister_isIdempotent() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        // Update blocklister to the same address - should emit event and work
        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.BlocklisterUpdated(blocklister, blocklister);

        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        // Verify blocklister still has permissions
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should be blocklisted after idempotent blocklister update"
        );
    }

    function test_reinitialize_emitsOldBlocklisterNonZero() public {
        // Deploy harness that uses __Blocklistable_init in both initialize and reinit
        BlocklistableHarnessWithReinit blk = new BlocklistableHarnessWithReinit();

        // First initialization sets a non-zero blocklister
        blk.initialize(owner, blocklister);
        assertEq(blk.blocklister(), blocklister, "initial blocklister should be set");

        // Reinitialize with a new blocklister; oldBlocklister should be non-zero in the event
        vm.expectEmit(true, true, false, false, address(blk));
        emit Blocklistable.BlocklisterUpdated(blocklister, otherBlocklister);
        blk.reinit(otherBlocklister);

        // New blocklister should now be active
        assertEq(blk.blocklister(), otherBlocklister, "blocklister should be updated during reinit");
    }

    function test_updateBlocklister_revertIfNotOwner() public {
        address random = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));

        vm.prank(random);
        blocklistable.updateBlocklister(otherBlocklister);
    }

    function test_updateBlocklister_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.prank(owner);
        blocklistable.updateBlocklister(address(0));
    }

    function test_onlyBlocklister_success() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.prank(blocklister);
        blocklistable.verifyOnlyBlocklisterModifier();
    }

    function test_onlyBlocklister_revertIfNotBlocklister() public {
        address random = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.prank(random);
        blocklistable.verifyOnlyBlocklisterModifier();
    }

    function test_isBlocklisted_returnsCorrectStatus() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted");
        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, OTHER_ADDRESS), "Other address should not be blocklisted"
        );
        assertFalse(
            blocklistable.isBlocklisted(OTHER_DOMAIN, REMOTE_ADDRESS),
            "Same address on different domain should not be blocklisted"
        );
    }

    function test_blocklist_success() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should not be blocklisted initially"
        );

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Blocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should be blocklisted after blocklist()"
        );
    }

    function test_blocklist_revertIfNotBlocklister() public {
        address random = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.prank(random);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);
    }

    function test_blocklist_isIdempotent() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Blocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted");

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Blocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        // Blocklist the same domain+address pair again
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should still be blocklisted after second call"
        );
    }

    function test_unblocklist_success() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        // First blocklist the address
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);
        assertTrue(blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted");

        // Then unblocklist it
        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Unblocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.prank(blocklister);
        blocklistable.unblocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should not be blocklisted after unblocklist()"
        );
    }

    function test_unblocklist_revertIfNotBlocklister() public {
        address random = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.prank(random);
        blocklistable.unblocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);
    }

    function test_unblocklist_allowWithoutFirstBlocklisting() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Unblocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.prank(blocklister);
        blocklistable.unblocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should still not be blocklisted after unblocklist"
        );
    }

    function test_unblocklist_isIdempotent() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Unblocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.prank(blocklister);
        blocklistable.unblocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);
        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should not be blocklisted after first unblocklist"
        );

        vm.expectEmit(true, true, false, false, address(blocklistable));
        emit Blocklistable.Unblocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.prank(blocklister);
        blocklistable.unblocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should still not be blocklisted after second unblocklist"
        );
    }

    // ============ Domain-Specific Tests ============

    function test_blocklist_domainSpecific_sameAddressDifferentDomains() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        // Blocklist address on one domain
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        // Verify it's blocklisted on that domain
        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS),
            "Address should be blocklisted on original domain"
        );

        // Verify it's NOT blocklisted on a different domain
        assertFalse(
            blocklistable.isBlocklisted(OTHER_DOMAIN, REMOTE_ADDRESS),
            "Same address should NOT be blocklisted on different domain"
        );

        // Different domain should not be affected by blocklisting
    }

    function test_blocklist_domainSpecific_differentAddressesSameDomain() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        // Blocklist one address on a domain
        vm.prank(blocklister);
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        // Verify it's blocklisted
        assertTrue(blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted");

        // Verify different address on same domain is NOT blocklisted
        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, OTHER_ADDRESS),
            "Different address on same domain should NOT be blocklisted"
        );

        // Different address on same domain should not be affected
    }

    function test_blocklist_domainSpecific_multipleDomainsMultipleAddresses() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.startPrank(blocklister);

        // Blocklist same address on multiple domains
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);
        blocklistable.blocklist(OTHER_DOMAIN, REMOTE_ADDRESS);

        // Blocklist different address on one domain
        blocklistable.blocklist(REMOTE_DOMAIN, OTHER_ADDRESS);

        vm.stopPrank();

        // Verify all combinations
        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted on domain 1"
        );
        assertTrue(
            blocklistable.isBlocklisted(OTHER_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted on domain 2"
        );
        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, OTHER_ADDRESS), "Other address should be blocklisted on domain 1"
        );
        assertFalse(
            blocklistable.isBlocklisted(OTHER_DOMAIN, OTHER_ADDRESS),
            "Other address should NOT be blocklisted on domain 2"
        );
    }

    function test_unblocklist_domainSpecific_independentDomains() public {
        vm.prank(owner);
        blocklistable.updateBlocklister(blocklister);

        vm.startPrank(blocklister);

        // Blocklist same address on two domains
        blocklistable.blocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);
        blocklistable.blocklist(OTHER_DOMAIN, REMOTE_ADDRESS);

        // Verify both are blocklisted
        assertTrue(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted on domain 1"
        );
        assertTrue(
            blocklistable.isBlocklisted(OTHER_DOMAIN, REMOTE_ADDRESS), "Address should be blocklisted on domain 2"
        );

        // Unblocklist from one domain only
        blocklistable.unblocklist(REMOTE_DOMAIN, REMOTE_ADDRESS);

        vm.stopPrank();

        // Verify only one domain is unblocklisted
        assertFalse(
            blocklistable.isBlocklisted(REMOTE_DOMAIN, REMOTE_ADDRESS), "Address should be unblocklisted on domain 1"
        );
        assertTrue(
            blocklistable.isBlocklisted(OTHER_DOMAIN, REMOTE_ADDRESS), "Address should still be blocklisted on domain 2"
        );
    }
}
