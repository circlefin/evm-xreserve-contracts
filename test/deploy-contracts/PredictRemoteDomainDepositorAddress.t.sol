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
import {Test} from "forge-std/Test.sol";
import {PredictRemoteDomainDepositorAddress} from "./../../deploy-contracts/PredictRemoteDomainDepositorAddress.s.sol";
import {xReserve} from "./../../src/xReserve.sol";
import {DeployXReserve} from "./../utils/DeployXReserve.sol";
import {ForkTestUtils} from "./../utils/ForkTestUtils.sol";

/// @title PredictRemoteDomainDepositorAddressTest
/// @notice Tests that the PredictRemoteDomainDepositorAddress script correctly predicts addresses
contract PredictRemoteDomainDepositorAddressTest is Test, DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;
    PredictRemoteDomainDepositorAddress private predictor;

    address private owner = makeAddr("owner");
    address private domainManager = makeAddr("domainManager");
    address private domainPauser = makeAddr("domainPauser");

    address[] private attesters;

    uint32 private domain;
    uint32 private constant REMOTE_DOMAIN_1 = 10001;
    uint32 private constant REMOTE_DOMAIN_2 = 10002;
    uint32 private constant REMOTE_DOMAIN_3 = 7;
    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum

    function setUp() public {
        // Get fork variables for contract addresses
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);

        // Deploy xReserve
        reserve = deployXReserve(
            owner,
            domain,
            forkedVars.gatewayMinter,
            forkedVars.gatewayWallet,
            forkedVars.tokenMessenger,
            forkedVars.tokenMessengerV2
        );

        // Deploy the predictor script
        predictor = new PredictRemoteDomainDepositorAddress();

        // Set up attesters array
        attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        // Add token as supported
        vm.prank(owner);
        reserve.addSupportedToken(address(token));
    }

    /// @notice Test that predicted address matches actual deployed address for a single domain
    function test_predictAddress_matchesActualDeployment() public {
        // Get the RemoteDomainDepositor implementation address from xReserve
        address remoteDomainDepositorImpl = reserve.remoteDomainDepositorImplementation();

        // Predict the address using the script
        address predictedAddress =
            predictor.predictAddress(address(reserve), remoteDomainDepositorImpl, REMOTE_DOMAIN_1);

        // Actually register the remote domain
        vm.prank(owner);
        address actualAddress = reserve.registerRemoteDomain(
            REMOTE_DOMAIN_1,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Assert that predicted address matches actual address
        assertEq(predictedAddress, actualAddress, "Predicted address should match actual deployed address");

        // Verify the deployed contract is indeed at that address
        assertGt(actualAddress.code.length, 0, "Contract should be deployed at predicted address");

        // Verify it's the correct RemoteDomainDepositor by checking we can get the depositor
        assertEq(reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_1), actualAddress, "Should be registered");
    }

    /// @notice Test that predicted addresses are different for different domains
    function test_predictAddress_differentDomainsProduceDifferentAddresses() public view {
        address remoteDomainDepositorImpl = reserve.remoteDomainDepositorImplementation();

        // Predict addresses for different domains
        address predicted1 = predictor.predictAddress(address(reserve), remoteDomainDepositorImpl, REMOTE_DOMAIN_1);

        address predicted2 = predictor.predictAddress(address(reserve), remoteDomainDepositorImpl, REMOTE_DOMAIN_2);

        address predicted3 = predictor.predictAddress(address(reserve), remoteDomainDepositorImpl, REMOTE_DOMAIN_3);

        // Assert all addresses are different
        assertTrue(predicted1 != predicted2, "Domain 1 and 2 should have different addresses");
        assertTrue(predicted1 != predicted3, "Domain 1 and 3 should have different addresses");
        assertTrue(predicted2 != predicted3, "Domain 2 and 3 should have different addresses");
    }
}
