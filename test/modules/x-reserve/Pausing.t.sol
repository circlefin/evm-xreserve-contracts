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
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {UnauthorizedCaller, ZeroAddress} from "src/common/Errors.sol";
import {Pausing, PausingStorage} from "src/modules/x-reserve/Pausing.sol";

contract PausingHarness is Pausing {
    function initialize(address owner, address pauser) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
        __Pausing_init(pauser);
    }

    // Helper function to specifically test the modifier whenNotPaused
    function verifyWhenNotPausedModifier() public whenNotPaused {}

    // Helper function to specifically test the modifier whenPaused
    function verifyWhenPausedModifier() public whenPaused {}
}

contract PausingTest is Test {
    PausingHarness private pausing;

    address private owner = makeAddr("owner");
    address private pauser = makeAddr("pauser");
    address private otherPauser = makeAddr("otherPauser");

    function setUp() public {
        pausing = new PausingHarness();
    }

    // ============ Initialization Tests ============

    function test_initialization_success() public {
        pausing.initialize(owner, pauser);

        assertEq(pausing.owner(), owner);
        assertEq(pausing.pauser(), pauser);
        assertFalse(pausing.paused());
    }

    function test_initialization_revertsIfAlreadyInitialized() public {
        pausing.initialize(owner, pauser);

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        pausing.initialize(owner, pauser);
    }

    // ============ Pauser Management Tests ============

    function test_updatePauser_success() public {
        pausing.initialize(owner, pauser);

        vm.expectEmit(true, true, false, false, address(pausing));
        emit Pausing.PauserUpdated(pauser, otherPauser);

        vm.startPrank(owner);
        pausing.updatePauser(otherPauser);
        vm.stopPrank();

        assertEq(pausing.pauser(), otherPauser);
    }

    function test_updatePauser_revertsIfNotOwner() public {
        pausing.initialize(owner, pauser);
        address unauthorized = makeAddr("unauthorized");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        vm.startPrank(unauthorized);
        pausing.updatePauser(otherPauser);
        vm.stopPrank();
    }

    function test_updatePauser_revertsIfZeroAddress() public {
        pausing.initialize(owner, pauser);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(owner);
        pausing.updatePauser(address(0));
    }

    // ============ Global Pause Tests ============

    function test_pause_success() public {
        pausing.initialize(owner, pauser);

        vm.expectEmit(false, false, false, true, address(pausing));
        emit PausableUpgradeable.Paused(pauser);

        vm.startPrank(pauser);
        pausing.pause();
        vm.stopPrank();

        assertTrue(pausing.paused());
    }

    function test_pause_revertsIfNotPauser() public {
        pausing.initialize(owner, pauser);
        address unauthorized = makeAddr("unauthorized");

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.startPrank(unauthorized);
        pausing.pause();
        vm.stopPrank();
    }

    function test_unpause_success() public {
        pausing.initialize(owner, pauser);

        vm.startPrank(pauser);
        pausing.pause();
        assertTrue(pausing.paused());

        vm.expectEmit(false, false, false, true, address(pausing));
        emit PausableUpgradeable.Unpaused(pauser);
        pausing.unpause();
        vm.stopPrank();

        assertFalse(pausing.paused());
    }

    function test_unpause_revertsIfNotPauser() public {
        pausing.initialize(owner, pauser);
        address unauthorized = makeAddr("unauthorized");

        vm.startPrank(pauser);
        pausing.pause();
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.startPrank(unauthorized);
        pausing.unpause();
        vm.stopPrank();
    }

    // ============ Storage Tests ============

    function test_storageSlot_correctlyCalculated() public pure {
        assertEq(
            PausingStorage.SLOT,
            keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Pausing"))) - 1)) & ~bytes32(uint256(0xff))
        );
    }

    // ============ Domain Pause State Tests ============

    function test_domainDepositsPaused_returnsFalseByDefault() public {
        pausing.initialize(owner, pauser);
        uint32 domain = 1;
        assertFalse(pausing.domainDepositsPaused(domain));
    }

    function test_domainWithdrawalsPaused_returnsFalseByDefault() public {
        pausing.initialize(owner, pauser);
        uint32 domain = 1;
        assertFalse(pausing.domainWithdrawalsPaused(domain));
    }

    // ============ Modifier Tests ============

    function test_whenNotPaused_allowsExecution() public {
        pausing.initialize(owner, pauser);
        pausing.verifyWhenNotPausedModifier();
    }

    function test_whenNotPaused_revertsWhenPaused() public {
        pausing.initialize(owner, pauser);

        vm.startPrank(pauser);
        pausing.pause();
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        pausing.verifyWhenNotPausedModifier();
    }

    function test_whenPaused_allowsExecution() public {
        pausing.initialize(owner, pauser);

        vm.startPrank(pauser);
        pausing.pause();
        vm.stopPrank();

        pausing.verifyWhenPausedModifier();
    }

    function test_whenPaused_revertsWhenNotPaused() public {
        pausing.initialize(owner, pauser);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.ExpectedPause.selector));
        pausing.verifyWhenPausedModifier();
    }
}
