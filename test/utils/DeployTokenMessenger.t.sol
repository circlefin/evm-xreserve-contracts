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

import {TokenMessenger} from "@cctp/TokenMessenger.sol";
import {TokenMinter} from "@cctp/TokenMinter.sol";
import {TokenMessengerV2} from "@cctp/v2/TokenMessengerV2.sol";
import {TokenMinterV2} from "@cctp/v2/TokenMinterV2.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {Test} from "forge-std/Test.sol";
import {DeployMockFiatToken} from "./DeployMockFiatToken.sol";
import {DeployTokenMessenger} from "./DeployTokenMessenger.sol";
import {ForkTestUtils} from "./ForkTestUtils.sol";

contract DeployTokenMessengerTest is Test {
    DeployTokenMessenger private deployer;
    FiatTokenV2_2 private fiatToken;
    address private owner = makeAddr("owner");
    address private user = makeAddr("user");
    uint256 private constant MAX_BURN_MESSAGE_SIZE = 1000;

    // Set up mock remote domain and remote token
    uint32 private destinationDomain = 1234;
    bytes32 private destinationToken = bytes32(uint256(uint160(makeAddr("destinationToken"))));
    bytes32 private destinationCaller = bytes32(uint256(uint160(makeAddr("destinationCaller"))));
    bytes32 private mintRecipient = bytes32(uint256(uint160(makeAddr("mintRecipient"))));
    bytes32 private destinationTokenMessenger = bytes32(uint256(uint160(makeAddr("destinationTokenMessenger"))));
    uint256 private burnAmount = 1000;

    function setUp() public {
        // Skip if not on local chain (redundant safety check)
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);

        deployer = new DeployTokenMessenger();
        fiatToken = new DeployMockFiatToken().deployMockFiatToken(owner);
    }

    function test_deployTokenMessengerAndMinterV1_succeedsAndCanExecuteDepositForBurn() public {
        // Skip if not on local chain (redundant safety check)
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);

        // Deploy mock TokenMessenger and TokenMinter
        (TokenMessenger messenger, TokenMinter minter) = deployer.deployTokenMessengerAndMinterV1(owner, 0);
        assertTrue(address(messenger) != address(0));
        assertTrue(address(minter) != address(0));
        assertEq(messenger.owner(), owner);
        assertEq(minter.owner(), owner);

        vm.startPrank(owner);
        {
            minter.linkTokenPair(address(fiatToken), destinationDomain, destinationToken);
            minter.setMaxBurnAmountPerMessage(address(fiatToken), MAX_BURN_MESSAGE_SIZE);
            messenger.addRemoteTokenMessenger(destinationDomain, destinationTokenMessenger);
        }
        vm.stopPrank();
        assertEq(
            minter.remoteTokensToLocalTokens(keccak256(abi.encodePacked(destinationDomain, destinationToken))),
            address(fiatToken)
        );
        assertEq(minter.burnLimitsPerMessage(address(fiatToken)), MAX_BURN_MESSAGE_SIZE);
        assertEq(messenger.remoteTokenMessengers(destinationDomain), destinationTokenMessenger);

        // Configure CCTP with fiatToken mint allowance
        vm.prank(fiatToken.masterMinter());
        fiatToken.configureMinter(address(minter), type(uint256).max);

        // Grant tokens to user
        deal(address(fiatToken), user, burnAmount, true);
        assertEq(fiatToken.balanceOf(user), burnAmount);
        assertEq(fiatToken.totalSupply(), burnAmount);

        // Approve tokens for burn
        vm.prank(user);
        fiatToken.approve(address(messenger), burnAmount);
        assertEq(fiatToken.allowance(user, address(messenger)), burnAmount);

        // Deposit tokens for burn
        vm.prank(user);
        messenger.depositForBurn(burnAmount, destinationDomain, mintRecipient, address(fiatToken));

        assertEq(fiatToken.balanceOf(user), 0);
        assertEq(fiatToken.totalSupply(), 0);
    }

    function test_deployTokenMessengerAndMinterV2_succeedsAndCanExecuteDepositForBurn() public {
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);

        // Deploy mock TokenMessenger and TokenMinter
        (TokenMessengerV2 messenger, TokenMinterV2 minter) = deployer.deployTokenMessengerAndMinterV2(owner, 0);
        assertTrue(address(messenger) != address(0));
        assertTrue(address(minter) != address(0));
        assertEq(messenger.owner(), owner);
        assertEq(minter.owner(), owner);

        vm.startPrank(owner);
        {
            minter.linkTokenPair(address(fiatToken), destinationDomain, destinationToken);
            minter.setMaxBurnAmountPerMessage(address(fiatToken), MAX_BURN_MESSAGE_SIZE);
            messenger.addRemoteTokenMessenger(destinationDomain, destinationTokenMessenger);
        }
        vm.stopPrank();
        assertEq(
            minter.remoteTokensToLocalTokens(keccak256(abi.encodePacked(destinationDomain, destinationToken))),
            address(fiatToken)
        );
        assertEq(minter.burnLimitsPerMessage(address(fiatToken)), MAX_BURN_MESSAGE_SIZE);
        assertEq(messenger.remoteTokenMessengers(destinationDomain), destinationTokenMessenger);

        // Configure CCTP with fiatToken mint allowance
        vm.prank(fiatToken.masterMinter());
        fiatToken.configureMinter(address(minter), type(uint256).max);

        // Grant tokens to user
        deal(address(fiatToken), user, burnAmount, true);
        assertEq(fiatToken.balanceOf(user), burnAmount);
        assertEq(fiatToken.totalSupply(), burnAmount);

        // Approve tokens for burn
        vm.prank(user);
        fiatToken.approve(address(messenger), burnAmount);
        assertEq(fiatToken.allowance(user, address(messenger)), burnAmount);

        // Deposit tokens for burn
        vm.prank(user);
        messenger.depositForBurn(
            burnAmount,
            destinationDomain,
            mintRecipient,
            address(fiatToken),
            destinationCaller,
            100, // maxFee
            1000 // minFinalityThreshold
        );

        assertEq(fiatToken.balanceOf(user), 0);
        assertEq(fiatToken.totalSupply(), 0);
    }
}
