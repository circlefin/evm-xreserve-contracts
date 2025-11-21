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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {ZeroAddress} from "./../src/common/Errors.sol";
import {UpgradeablePlaceholder} from "./../src/UpgradeablePlaceholder.sol";

contract ERC1967ProxyHarness is ERC1967Proxy {
    constructor(address impl, bytes memory data) ERC1967Proxy(impl, data) {}

    function implementation() public view returns (address) {
        return _implementation();
    }

    receive() external payable {}
}

contract UpgradeablePlaceholderTest is Test {
    address private owner = makeAddr("owner");

    UpgradeablePlaceholder private impl;
    UpgradeablePlaceholder private placeholder;
    ERC1967ProxyHarness private proxy;

    function setUp() public {
        impl = new UpgradeablePlaceholder();
        proxy = new ERC1967ProxyHarness(address(impl), abi.encodeCall(UpgradeablePlaceholder.initialize, (owner)));
        placeholder = UpgradeablePlaceholder(payable(address(proxy)));
    }

    function test_owner() public view {
        assertEq(placeholder.owner(), owner);
    }

    function test_initialize_revertWhenReInitialized() public {
        address random = makeAddr("random");
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        placeholder.initialize(random);
        vm.stopPrank();
    }

    function test_transferOwnership_success() public {
        address newOwner = makeAddr("new owner");

        vm.startPrank(owner);
        placeholder.transferOwnership(newOwner);
        vm.stopPrank();

        assertEq(placeholder.owner(), owner);
        assertEq(placeholder.pendingOwner(), newOwner);

        vm.startPrank(newOwner);
        placeholder.acceptOwnership();
        vm.stopPrank();

        assertEq(placeholder.owner(), newOwner);
        assertEq(placeholder.pendingOwner(), address(0));
    }

    function test_transferOwnership_idempotent() public {
        address newOwner = makeAddr("new_owner");

        vm.startPrank(owner);
        placeholder.transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(owner);
        placeholder.transferOwnership(newOwner);
        assertEq(placeholder.owner(), owner);
        assertEq(placeholder.pendingOwner(), newOwner);
    }

    function test_transferOwnership_revertIfNotOwner() public {
        address random = makeAddr("random");

        vm.startPrank(random);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));
        placeholder.transferOwnership(random);
        vm.stopPrank();
    }

    function test_initialize_revertIfOwnerIsZeroAddress() public {
        UpgradeablePlaceholder newImpl = new UpgradeablePlaceholder();

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new ERC1967ProxyHarness(address(newImpl), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(0))));
    }

    function test_upgradeToAndCall_success() public {
        address newImpl = address(new UpgradeablePlaceholder());

        vm.startPrank(owner);
        placeholder.upgradeToAndCall(newImpl, "");
        vm.stopPrank();

        assertEq(proxy.implementation(), newImpl);
    }

    function test_upgradeToAndCall_revertIfNotOwner() public {
        address random = makeAddr("random");
        address newImpl = address(new UpgradeablePlaceholder());

        vm.startPrank(random);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));
        placeholder.upgradeToAndCall(newImpl, "");
        vm.stopPrank();
    }
}
