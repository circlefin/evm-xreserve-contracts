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

import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Attestable} from "src/modules/remote-domain-depositor/Attestable.sol";
import {RemoteDomainRegistration} from "src/modules/x-reserve/RemoteDomainRegistration.sol";
import {RemoteDomainDepositor} from "src/RemoteDomainDepositor.sol";
import {xReserve} from "src/xReserve.sol";
import {DeployXReserve} from "test/utils/DeployXReserve.sol";
import {ForkTestUtils} from "test/utils/ForkTestUtils.sol";

contract XReserveUpdatePersistentSignatureBufferDelayTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");
    address private domainManager = makeAddr("domainManager");
    address private domainPauser = makeAddr("domainPauser");
    address private nonOwner = makeAddr("nonOwner");

    address[] private attesters;

    uint32 private domain;
    uint32 private constant REMOTE_DOMAIN = 10001;
    uint32 private constant UNREGISTERED_DOMAIN = 99999;
    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum
    uint256 private constant NEW_DELAY = 100800; // ~14 days on Ethereum

    function setUp() public {
        // Get fork variables for contract addresses
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);

        reserve = deployXReserve(
            owner,
            domain,
            forkedVars.gatewayMinter,
            forkedVars.gatewayWallet,
            forkedVars.tokenMessenger,
            forkedVars.tokenMessengerV2
        );

        // Set up attesters array
        attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        // Add token as supported
        vm.prank(owner);
        reserve.addSupportedToken(address(token));
    }

    // ============ Helper Functions ============

    function _registerRemoteDomain() internal returns (address remoteDomainDepositor) {
        vm.prank(owner);
        remoteDomainDepositor = reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
    }

    // ============ Tests ============

    function test_setPersistentSignatureBufferDelay_success() public {
        // Register a remote domain
        address depositorAddress = _registerRemoteDomain();
        RemoteDomainDepositor depositor = RemoteDomainDepositor(depositorAddress);

        // Verify initial delay
        assertEq(depositor.persistentSignatureBufferDelayBlocks(), PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS);

        // Update delay through the reserve (which owns the depositor)
        vm.prank(owner);
        reserve.setPersistentSignatureBufferDelay(REMOTE_DOMAIN, NEW_DELAY);

        // Verify delay was updated
        assertEq(depositor.persistentSignatureBufferDelayBlocks(), NEW_DELAY);
    }

    function test_setPersistentSignatureBufferDelay_revertsIfNotOwner() public {
        // Register a remote domain
        _registerRemoteDomain();

        // Try to update delay as non-owner through the reserve
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        reserve.setPersistentSignatureBufferDelay(REMOTE_DOMAIN, NEW_DELAY);
    }

    function test_setPersistentSignatureBufferDelay_revertsIfDomainNotRegistered() public {
        // Try to update delay for unregistered domain
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, UNREGISTERED_DOMAIN)
        );
        reserve.setPersistentSignatureBufferDelay(UNREGISTERED_DOMAIN, NEW_DELAY);
    }

    function test_setPersistentSignatureBufferDelay_revertsIfDelayIsZero() public {
        // Register a remote domain
        _registerRemoteDomain();

        // Try to update delay to zero
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Attestable.PersistentSignatureBufferDelayZero.selector));
        reserve.setPersistentSignatureBufferDelay(REMOTE_DOMAIN, 0);
    }

    function test_setPersistentSignatureBufferDelay_revertsIfDelayAlreadySet() public {
        // Register a remote domain
        _registerRemoteDomain();

        // Try to update delay to the same value
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Attestable.PersistentSignatureBufferDelayAlreadySet.selector, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
            )
        );
        reserve.setPersistentSignatureBufferDelay(REMOTE_DOMAIN, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS);
    }

    function test_setPersistentSignatureBufferDelay_emitsEvent() public {
        // Register a remote domain
        address depositorAddress = _registerRemoteDomain();

        // Expect event to be emitted from the depositor contract
        vm.expectEmit(true, true, false, false, depositorAddress);
        emit Attestable.PersistentSignatureBufferDelayUpdated(PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS, NEW_DELAY);

        // Update delay through the reserve
        vm.prank(owner);
        reserve.setPersistentSignatureBufferDelay(REMOTE_DOMAIN, NEW_DELAY);
    }
}
