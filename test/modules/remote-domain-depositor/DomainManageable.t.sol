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
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";
import {UnauthorizedCaller, ZeroAddress} from "src/common/Errors.sol";
import {DomainManageable, DomainManageableStorage} from "src/modules/remote-domain-depositor/DomainManageable.sol";

contract DomainManageableHarness is DomainManageable {
    function initialize(address owner, address domainManager_, address domainPauser_) public initializer {
        __Ownable_init(owner);
        __DomainManageable_init(domainManager_, domainPauser_);
    }

    // Helper function to test the onlyDomainManager modifier
    function verifyOnlyDomainManagerModifier() public onlyDomainManager {}

    // Helper function to expose storage for testing
    function getStorageSlot() public pure returns (bytes32) {
        return DomainManageableStorage.SLOT;
    }

    // Helper function to get storage domain manager directly
    function getStorageDomainManager() public view returns (address) {
        return DomainManageableStorage.get().domainManager;
    }

    // Helper function to get storage domain pauser directly
    function getStorageDomainPauser() public view returns (address) {
        return DomainManageableStorage.get().domainPauser;
    }
}

contract DomainManageableTest is Test {
    DomainManageableHarness private domainManageable;

    address private owner = makeAddr("owner");
    address private domainManager = makeAddr("domainManager");
    address private newDomainManager = makeAddr("newDomainManager");
    address private domainPauser = makeAddr("domainPauser");
    address private newDomainPauser = makeAddr("newDomainPauser");
    address private unauthorized = makeAddr("unauthorized");

    function setUp() public {
        domainManageable = new DomainManageableHarness();
    }

    // ============ Initialization Tests ============

    function test_initialization_success() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        assertEq(domainManageable.owner(), owner);
        assertEq(domainManageable.domainManager(), domainManager);
        assertEq(domainManageable.domainPauser(), domainPauser);
    }

    function test_initialization_revertsIfAlreadyInitialized() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        domainManageable.initialize(owner, domainManager, domainPauser);
    }

    function test_initialization_revertsIfDomainManagerIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        domainManageable.initialize(owner, address(0), domainPauser);
    }

    function test_initialization_revertsIfDomainPauserIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        domainManageable.initialize(owner, domainManager, address(0));
    }

    function test_initialization_emitsDomainManagerUpdatedEvent() public {
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(address(0), domainManager);

        domainManageable.initialize(owner, domainManager, domainPauser);
    }

    function test_initialization_emitsDomainPauserUpdatedEvent() public {
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(address(0), domainPauser);

        domainManageable.initialize(owner, domainManager, domainPauser);
    }

    // ============ Domain Manager Getter Tests ============

    function test_domainManager_returnsCorrectAddress() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        assertEq(domainManageable.domainManager(), domainManager);
    }

    function test_domainManager_returnsZeroAddressWhenNotInitialized() public view {
        assertEq(domainManageable.domainManager(), address(0));
    }

    // ============ Domain Pauser Getter Tests ============

    function test_domainPauser_returnsCorrectAddress() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        assertEq(domainManageable.domainPauser(), domainPauser);
    }

    function test_domainPauser_returnsZeroAddressWhenNotInitialized() public view {
        assertEq(domainManageable.domainPauser(), address(0));
    }

    // ============ Update Domain Manager Tests ============

    function test_updateDomainManager_success() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager, newDomainManager);

        vm.startPrank(owner);
        domainManageable.updateDomainManager(newDomainManager);
        vm.stopPrank();

        assertEq(domainManageable.domainManager(), newDomainManager);
    }

    function test_updateDomainManager_revertsIfNotOwner() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));

        vm.startPrank(unauthorized);
        domainManageable.updateDomainManager(newDomainManager);
        vm.stopPrank();
    }

    function test_updateDomainManager_revertsIfNewDomainManagerIsZeroAddress() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.startPrank(owner);
        domainManageable.updateDomainManager(address(0));
        vm.stopPrank();
    }

    function test_updateDomainManager_isIdempotent() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager, domainManager);

        vm.startPrank(owner);
        domainManageable.updateDomainManager(domainManager);
        vm.stopPrank();

        assertEq(domainManageable.domainManager(), domainManager);
    }

    function test_updateDomainManager_allowsDomainManagerToUpdateSelf() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager, newDomainManager);

        vm.startPrank(owner);
        domainManageable.updateDomainManager(newDomainManager);
        vm.stopPrank();

        assertEq(domainManageable.domainManager(), newDomainManager);
    }

    // ============ Update Domain Pauser Tests ============

    function test_updateDomainPauser_success() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser, newDomainPauser);

        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(newDomainPauser);
        vm.stopPrank();

        assertEq(domainManageable.domainPauser(), newDomainPauser);
    }

    function test_updateDomainPauser_revertsIfNotDomainManager() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(unauthorized);
        domainManageable.updateDomainPauser(newDomainPauser);
        vm.stopPrank();
    }

    function test_updateDomainPauser_revertsIfOwnerCallsDirectly() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(owner);
        domainManageable.updateDomainPauser(newDomainPauser);
        vm.stopPrank();
    }

    function test_updateDomainPauser_revertsIfNewDomainPauserIsZeroAddress() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(address(0));
        vm.stopPrank();
    }

    function test_updateDomainPauser_isIdempotent() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser, domainPauser);

        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(domainPauser);
        vm.stopPrank();

        assertEq(domainManageable.domainPauser(), domainPauser);
    }

    function test_updateDomainPauser_allowsDomainManagerToSetNewPauser() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser, newDomainPauser);

        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(newDomainPauser);
        vm.stopPrank();

        assertEq(domainManageable.domainPauser(), newDomainPauser);
    }

    // ============ Modifier Tests ============

    function test_onlyDomainManager_allowsDomainManager() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.startPrank(domainManager);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function test_onlyDomainManager_revertsForUnauthorizedCaller() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(unauthorized);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function test_onlyDomainManager_revertsForOwner() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(owner);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function test_onlyDomainManager_revertsForDomainPauser() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(domainPauser);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function test_onlyDomainManager_revertsWhenNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(unauthorized);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    // ============ Storage Pattern Tests ============

    function test_storageSlot_isCorrect() public pure {
        assertEq(
            DomainManageableStorage.SLOT,
            keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.DomainManageable"))) - 1))
                & ~bytes32(uint256(0xff))
        );
    }

    function test_storageGet_returnsCorrectData() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        assertEq(domainManageable.getStorageDomainManager(), domainManager);
        assertEq(domainManageable.getStorageDomainPauser(), domainPauser);
    }

    function test_storageData_isIsolated() public {
        // Deploy two instances to verify storage isolation
        DomainManageableHarness domainManageable2 = new DomainManageableHarness();

        domainManageable.initialize(owner, domainManager, domainPauser);
        domainManageable2.initialize(owner, newDomainManager, newDomainPauser);

        assertEq(domainManageable.domainManager(), domainManager);
        assertEq(domainManageable2.domainManager(), newDomainManager);
        assertEq(domainManageable.domainPauser(), domainPauser);
        assertEq(domainManageable2.domainPauser(), newDomainPauser);
    }

    // ============ Edge Cases and Integration Tests ============

    function test_multipleUpdates_success() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        address domainManager2 = makeAddr("domainManager2");
        address domainManager3 = makeAddr("domainManager3");

        vm.startPrank(owner);

        // First update
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager, domainManager2);
        domainManageable.updateDomainManager(domainManager2);
        assertEq(domainManageable.domainManager(), domainManager2);

        // Second update
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager2, domainManager3);
        domainManageable.updateDomainManager(domainManager3);
        assertEq(domainManageable.domainManager(), domainManager3);

        // Back to original
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager3, domainManager);
        domainManageable.updateDomainManager(domainManager);
        assertEq(domainManageable.domainManager(), domainManager);

        vm.stopPrank();
    }

    function test_multipleDomainPauserUpdates_success() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        address domainPauser2 = makeAddr("domainPauser2");
        address domainPauser3 = makeAddr("domainPauser3");

        vm.startPrank(domainManager);

        // First update
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser, domainPauser2);
        domainManageable.updateDomainPauser(domainPauser2);
        assertEq(domainManageable.domainPauser(), domainPauser2);

        // Second update
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser2, domainPauser3);
        domainManageable.updateDomainPauser(domainPauser3);
        assertEq(domainManageable.domainPauser(), domainPauser3);

        // Back to original
        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser3, domainPauser);
        domainManageable.updateDomainPauser(domainPauser);
        assertEq(domainManageable.domainPauser(), domainPauser);

        vm.stopPrank();
    }

    function test_modifierAfterDomainManagerUpdate() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        // Original domain manager can call
        vm.startPrank(domainManager);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();

        // Update domain manager
        vm.startPrank(owner);
        domainManageable.updateDomainManager(newDomainManager);
        vm.stopPrank();

        // Old domain manager can no longer call
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.startPrank(domainManager);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();

        // New domain manager can call
        vm.startPrank(newDomainManager);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function test_domainPauserUpdateAfterDomainManagerChange() public {
        domainManageable.initialize(owner, domainManager, domainPauser);

        // Original domain manager can update domain pauser
        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(newDomainPauser);
        vm.stopPrank();
        assertEq(domainManageable.domainPauser(), newDomainPauser);

        // Update domain manager
        vm.startPrank(owner);
        domainManageable.updateDomainManager(newDomainManager);
        vm.stopPrank();

        // Old domain manager can no longer update domain pauser
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(domainPauser);
        vm.stopPrank();

        // New domain manager can update domain pauser
        vm.startPrank(newDomainManager);
        domainManageable.updateDomainPauser(domainPauser);
        vm.stopPrank();
        assertEq(domainManageable.domainPauser(), domainPauser);
    }

    // ============ Fuzz Tests ============

    function testFuzz_updateDomainManager_success(address newManager) public {
        vm.assume(newManager != address(0));

        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainManagerUpdated(domainManager, newManager);

        vm.startPrank(owner);
        domainManageable.updateDomainManager(newManager);
        vm.stopPrank();

        assertEq(domainManageable.domainManager(), newManager);
    }

    function testFuzz_updateDomainPauser_success(address newPauser) public {
        vm.assume(newPauser != address(0));

        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectEmit(true, true, false, false, address(domainManageable));
        emit DomainManageable.DomainPauserUpdated(domainPauser, newPauser);

        vm.startPrank(domainManager);
        domainManageable.updateDomainPauser(newPauser);
        vm.stopPrank();

        assertEq(domainManageable.domainPauser(), newPauser);
    }

    function testFuzz_onlyDomainManager_allowsCorrectManager(address manager) public {
        vm.assume(manager != address(0));

        domainManageable.initialize(owner, manager, domainPauser);

        vm.startPrank(manager);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function testFuzz_onlyDomainManager_revertsForWrongCaller(address manager, address caller) public {
        vm.assume(manager != address(0));
        vm.assume(caller != manager);

        domainManageable.initialize(owner, manager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(caller);
        domainManageable.verifyOnlyDomainManagerModifier();
        vm.stopPrank();
    }

    function testFuzz_updateDomainPauser_revertsForWrongCaller(address newPauser, address caller) public {
        vm.assume(newPauser != address(0));
        vm.assume(caller != domainManager);

        domainManageable.initialize(owner, domainManager, domainPauser);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));

        vm.startPrank(caller);
        domainManageable.updateDomainPauser(newPauser);
        vm.stopPrank();
    }
}
