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
import {RemoteDomainDepositor} from "src/RemoteDomainDepositor.sol";
import {xReserve} from "src/xReserve.sol";
import {DeployXReserve} from "test/utils/DeployXReserve.sol";
import {ForkTestUtils} from "test/utils/ForkTestUtils.sol";

contract XReserveUpdateDomainManagerTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");
    address private domainManager = makeAddr("domainManager");
    address private domainPauser = makeAddr("domainPauser");
    address private newDomainManager = makeAddr("newDomainManager");
    address private nonOwner = makeAddr("nonOwner");

    address[] private attesters;

    uint32 private domain;
    uint32 private constant REMOTE_DOMAIN = 10001;
    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum

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

    function test_updateDomainManager_success() public {
        // Register a remote domain
        address depositorAddress = _registerRemoteDomain();
        RemoteDomainDepositor depositor = RemoteDomainDepositor(depositorAddress);

        // Update domain manager through the reserve (which owns the depositor)
        vm.prank(owner);
        reserve.updateDomainManager(REMOTE_DOMAIN, newDomainManager);

        // Verify domain manager was updated
        assertEq(depositor.domainManager(), newDomainManager);
    }

    function test_updateDomainManager_revertsIfNotOwner() public {
        // Register a remote domain
        _registerRemoteDomain();

        // Try to update domain manager as non-owner through the reserve
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        reserve.updateDomainManager(REMOTE_DOMAIN, newDomainManager);
    }
}
