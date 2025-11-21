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
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ZeroAddress} from "./../../src/common/Errors.sol";
import {Blocklistable} from "./../../src/modules/x-reserve/Blocklistable.sol";
import {DepositToRemote} from "./../../src/modules/x-reserve/DepositToRemote.sol";
import {Pausing} from "./../../src/modules/x-reserve/Pausing.sol";
import {RemoteDomainRegistration} from "./../../src/modules/x-reserve/RemoteDomainRegistration.sol";
import {TokenSupport} from "./../../src/modules/x-reserve/TokenSupport.sol";
import {xReserve} from "../../src/xReserve.sol";
import {
    AlwaysSucceedsRemoteDomainHookExecutor,
    AlwaysFailsRemoteDomainHookExecutor,
    ReentrantRemoteDomainHookExecutor
} from "./../mocks/MockRemoteDomainHookExecutor.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";
import {ForkTestUtils} from "./../utils/ForkTestUtils.sol";

contract XReserveDepositToRemoteTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private pauser = owner;
    address private blocklister = owner;
    address private user = makeAddr("user");
    address private gatewayWallet;
    address private gatewayMinter;

    // Remote domain setup
    address internal remoteRecipient;
    bytes32 internal remoteRecipientBytes32;

    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum
    uint256 internal constant MAX_FEE = 10e6; // 10 USDC
    bytes internal constant HOOK_DATA = "test integration hook data";
    uint32 private constant REMOTE_DOMAIN = 10001;

    uint32 private domain;
    address private domainManager;
    address private domainPauser;
    address[] private attesters;

    function setUp() public {
        // Get fork variables for contract addresses
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);
        gatewayWallet = forkedVars.gatewayWallet;
        gatewayMinter = forkedVars.gatewayMinter;
        reserve = deployXReserve(
            owner,
            domain,
            forkedVars.gatewayMinter,
            forkedVars.gatewayWallet,
            forkedVars.tokenMessenger,
            forkedVars.tokenMessengerV2
        );

        remoteRecipient = makeAddr("remoteRecipient");
        remoteRecipientBytes32 = bytes32(uint256(uint160(remoteRecipient)));

        domainManager = makeAddr("domainManager");
        domainPauser = makeAddr("domainPauser");
        attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        // Add token as supported
        vm.prank(owner);
        reserve.addSupportedToken(address(token));
    }

    function test_depositToRemote_revertsIfRemoteDomainNotRegistered() public {
        uint256 value = 1000;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";

        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, REMOTE_DOMAIN)
        );
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenZeroValue() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DepositToRemote.ZeroValue.selector));
        reserve.depositToRemote(0, REMOTE_DOMAIN, bytes32(uint256(uint160(remoteRecipient))), address(token), 0, "");
        vm.stopPrank();
    }

    function test_depositToRemote_revertsWhenUnsupportedToken() public {
        FiatTokenV2_2 unsupportedToken = deployMockFiatToken(owner);

        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        uint256 depositAmount = 1000e6;

        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, address(unsupportedToken)));
        reserve.depositToRemote(
            depositAmount, REMOTE_DOMAIN, bytes32(uint256(uint160(remoteRecipient))), address(unsupportedToken), 0, ""
        );
    }

    function test_depositToRemote_revertsWhenZeroAddressLocalToken() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        bytes32 remoteToken = bytes32(uint256(uint160(address(token))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        uint256 value = 1000;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "";

        vm.startPrank(user);
        vm.expectRevert(ZeroAddress.selector);
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(0), maxFee, hookData);
        vm.stopPrank();
    }

    function test_depositToRemote_revertsWhenInsufficientBalance() public {
        vm.startPrank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        bytes32 remoteToken = bytes32(uint256(uint160(address(token))));
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);
        vm.stopPrank();

        uint256 userBalance = 500; // User has 500 tokens
        uint256 depositAmount = 1000; // User tries to deposit 1000 tokens

        address masterMinter = token.masterMinter();
        vm.prank(masterMinter);
        token.configureMinter(address(this), type(uint256).max);

        token.mint(user, userBalance);

        vm.startPrank(user);
        token.approve(address(reserve), depositAmount);
        vm.stopPrank();

        // Attempt to deposit more than user balance should revert
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "";

        vm.startPrank(user);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        reserve.depositToRemote(depositAmount, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
        vm.stopPrank();
    }

    function test_depositToRemote_succeeds() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        bytes32 remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        // Setup user's token balance
        uint256 value = 1000;
        address masterMinter = token.masterMinter();
        vm.prank(masterMinter);
        token.configureMinter(address(this), type(uint256).max);

        token.mint(user, value);
        vm.prank(user);
        token.approve(address(reserve), value);

        // Test depositToRemote succeeds
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token), value, user, destinationRecipient, REMOTE_DOMAIN, remoteToken, maxFee, hookData
        );

        vm.prank(user);
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenDomainPaused() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Pause domain deposits using the reserve's pausing
        vm.prank(domainPauser);
        reserve.setDomainPauseState(REMOTE_DOMAIN, true, false);

        uint256 value = 1000;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "";

        vm.expectRevert(abi.encodeWithSelector(Pausing.DomainDepositsPaused.selector, REMOTE_DOMAIN));
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenGloballyPaused() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Pause globally
        vm.prank(pauser);
        reserve.pause();

        uint256 value = 1000;
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "";

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenRecipientBlocklisted() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Blocklist the recipient
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        vm.prank(blocklister);
        reserve.blocklist(REMOTE_DOMAIN, destinationRecipient);

        uint256 value = 1000;
        uint256 maxFee = 10;
        bytes memory hookData = "";

        vm.expectRevert(
            abi.encodeWithSelector(Blocklistable.AccountBlocklisted.selector, REMOTE_DOMAIN, destinationRecipient)
        );
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenRemoteTokenNotRegistered() public {
        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Setup user's token balance
        uint256 value = 1000;
        deal(address(token), user, value, true);

        vm.prank(user);
        token.approve(address(reserve), value);

        uint256 maxFee = 10;
        bytes memory hookData = "";
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.LocalTokenNotRegistered.selector, REMOTE_DOMAIN, address(token)
            )
        );
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenHookExecutorFails() public {
        address hookExecutor = address(new AlwaysFailsRemoteDomainHookExecutor());

        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            hookExecutor
        );

        bytes32 remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        // Setup user's token balance
        uint256 value = 1000;
        deal(address(token), user, value, true);

        vm.prank(user);
        token.approve(address(reserve), value);

        // Test depositToRemote succeeds
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(AlwaysFailsRemoteDomainHookExecutor.HookExecutionFailed.selector, hookData)
        );
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_revertsWhenHookExecutorReenters() public {
        address hookExecutor = address(new ReentrantRemoteDomainHookExecutor(reserve));

        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            hookExecutor
        );

        bytes32 remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        // Setup user's token balance
        uint256 value = 1000;
        deal(address(token), user, value, true);

        vm.prank(user);
        token.approve(address(reserve), value);

        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector));
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_succeedsWithHookExecutor() public {
        address hookExecutor = address(new AlwaysSucceedsRemoteDomainHookExecutor());

        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            hookExecutor
        );

        bytes32 remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        // Setup user's token balance
        uint256 value = 1000;
        deal(address(token), user, value, true);

        vm.prank(user);
        token.approve(address(reserve), value);

        // Test depositToRemote succeeds
        uint256 maxFee = 10;
        bytes memory hookData = "test hook data";
        bytes32 destinationRecipient = bytes32(uint256(uint160(user)));

        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token), value, user, destinationRecipient, REMOTE_DOMAIN, remoteToken, maxFee, hookData
        );

        vm.prank(user);
        reserve.depositToRemote(value, REMOTE_DOMAIN, destinationRecipient, address(token), maxFee, hookData);
    }

    function test_depositToRemote_multipleDeposits_succeeds() public {
        uint256 depositCount = 4;
        uint256 value = 1000e6;
        uint256 depositAmountEach = value / depositCount; // 1000e6 / 4 = 250e6

        vm.prank(owner);
        reserve.registerRemoteDomain(
            REMOTE_DOMAIN,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        bytes32 remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);

        // Setup user's token balance
        deal(address(token), user, value, true);

        // Approve total amount
        vm.prank(user);
        token.approve(address(reserve), value);

        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 gatewayBalanceBefore = token.balanceOf(address(gatewayWallet));

        // Execute multiple deposits
        for (uint256 i = 0; i < depositCount; i++) {
            vm.prank(user);
            reserve.depositToRemote(
                depositAmountEach, REMOTE_DOMAIN, remoteRecipientBytes32, address(token), MAX_FEE, HOOK_DATA
            );
        }

        // Verify total amount was deposited
        assertEq(token.balanceOf(user), userBalanceBefore - value, "User balance should decrease by total");
        assertEq(token.balanceOf(address(gatewayWallet)), gatewayBalanceBefore + value, "Gateway should receive total");
    }
}
