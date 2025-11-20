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

import {GatewayMinter} from "@gateway/src/GatewayMinter.sol";
import {GatewayWallet} from "@gateway/src/GatewayWallet.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RemoteDomainRegistration} from "./../../src/modules/x-reserve/RemoteDomainRegistration.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";
import {ForkTestUtils} from "./../utils/ForkTestUtils.sol";

contract XReserveBalanceOfNativeCollateralTest is DeployXReserve {
    uint32 private domain;
    xReserve private reserve;
    FiatTokenV2_2 private token;
    GatewayWallet private gatewayWallet;
    GatewayMinter private gatewayMinter;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");
    address private depositor = makeAddr("depositor");

    uint32 private constant REMOTE_DOMAIN = 10001;
    uint32 private constant UNREGISTERED_DOMAIN = 99999;

    // Remote domain configuration
    address private domainManager = makeAddr("domainManager");
    address private domainPauser = makeAddr("domainPauser");
    address[] private attesters;
    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum
    bytes32 private constant REMOTE_TOKEN = bytes32(uint256(0x123456));

    // Test amounts
    uint256 private constant INITIAL_TOKEN_BALANCE = 1000 * 10 ** 6; // 1000 USDC
    uint256 private constant DEPOSIT_AMOUNT = 500 * 10 ** 6; // 500 USDC

    function setUp() public {
        // Deploy token and gateway contracts
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);
        gatewayWallet = GatewayWallet(forkedVars.gatewayWallet);
        gatewayMinter = GatewayMinter(forkedVars.gatewayMinter);

        // Deploy reserve
        reserve = deployXReserve(
            owner,
            domain,
            address(gatewayMinter),
            address(gatewayWallet),
            forkedVars.tokenMessenger,
            forkedVars.tokenMessengerV2
        );

        // Setup attesters array
        attesters = new address[](3);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");
        attesters[2] = makeAddr("attester3");

        // Setup token as supported
        vm.prank(owner);
        reserve.addSupportedToken(address(token));

        // Give user some tokens
        deal(address(token), user, INITIAL_TOKEN_BALANCE);
        deal(address(token), depositor, INITIAL_TOKEN_BALANCE);
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

    function _registerRemoteToken() internal {
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, REMOTE_TOKEN);
    }

    function _makeDeposit(address from, uint256 amount) internal {
        vm.startPrank(from);
        IERC20(address(token)).approve(address(reserve), amount);
        reserve.depositToRemote(
            amount,
            REMOTE_DOMAIN,
            bytes32(uint256(uint160(from))), // remoteRecipient
            address(token),
            0, // maxFee
            "" // hookData
        );
        vm.stopPrank();
    }

    // ============ Success Tests ============

    function test_balanceOfNativeCollateral_returnsZeroWhenNoDeposits() public {
        address remoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        uint256 balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);

        assertEq(balance, 0, "Balance should be zero when no deposits made");

        // Verify this matches the gateway wallet directly
        uint256 directBalance = gatewayWallet.availableBalance(address(token), remoteDomainDepositor);
        assertEq(balance, directBalance, "Balance should match gateway wallet directly");
    }

    function test_balanceOfNativeCollateral_returnsCorrectBalanceAfterDeposit() public {
        address remoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        // Make a deposit
        _makeDeposit(user, DEPOSIT_AMOUNT);

        uint256 balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);

        assertEq(balance, DEPOSIT_AMOUNT, "Balance should match deposit amount");

        // Verify this matches the gateway wallet directly
        uint256 directBalance = gatewayWallet.availableBalance(address(token), remoteDomainDepositor);
        assertEq(balance, directBalance, "Balance should match gateway wallet directly");
    }

    function test_balanceOfNativeCollateral_returnsCorrectBalanceAfterMultipleDeposits() public {
        address remoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        // Make multiple deposits from different users
        uint256 firstDeposit = 200 * 10 ** 6;
        uint256 secondDeposit = 300 * 10 ** 6;
        uint256 totalExpected = firstDeposit + secondDeposit;

        _makeDeposit(user, firstDeposit);
        _makeDeposit(depositor, secondDeposit);

        uint256 balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);

        assertEq(balance, totalExpected, "Balance should match total deposits");

        // Verify this matches the gateway wallet directly
        uint256 directBalance = gatewayWallet.availableBalance(address(token), remoteDomainDepositor);
        assertEq(balance, directBalance, "Balance should match gateway wallet directly");
    }

    function test_balanceOfNativeCollateral_updatesCorrectlyAfterAdditionalDeposit() public {
        address remoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        // Initial deposit
        _makeDeposit(user, DEPOSIT_AMOUNT);
        uint256 initialBalance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        assertEq(initialBalance, DEPOSIT_AMOUNT);

        // Additional deposit
        uint256 additionalAmount = 250 * 10 ** 6;
        _makeDeposit(depositor, additionalAmount);

        uint256 newBalance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        uint256 expectedTotal = DEPOSIT_AMOUNT + additionalAmount;

        assertEq(newBalance, expectedTotal, "Balance should include both deposits");

        // Verify this matches the gateway wallet directly
        uint256 directBalance = gatewayWallet.availableBalance(address(token), remoteDomainDepositor);
        assertEq(newBalance, directBalance, "Balance should match gateway wallet directly");
    }

    function test_balanceOfNativeCollateral_handlesZeroBalanceCorrectly() public {
        address remoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        // Make a deposit and then verify balance
        _makeDeposit(user, DEPOSIT_AMOUNT);
        uint256 balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        assertEq(balance, DEPOSIT_AMOUNT, "Balance should match deposit amount");

        // Test with a different token that has no deposits but is registered
        FiatTokenV2_2 differentToken = deployMockFiatToken(owner);

        // First add the different token as supported and register it
        vm.startPrank(owner);
        reserve.addSupportedToken(address(differentToken));
        bytes32 differentRemoteToken = bytes32(uint256(0xABCDEF));
        reserve.registerRemoteToken(address(differentToken), REMOTE_DOMAIN, differentRemoteToken);
        vm.stopPrank();

        uint256 zeroBalance = reserve.balanceOfNativeCollateral(address(differentToken), REMOTE_DOMAIN);
        assertEq(zeroBalance, 0, "Balance should be zero for token with no deposits");

        // Verify this matches the gateway wallet directly for both cases
        uint256 directBalance = gatewayWallet.availableBalance(address(token), remoteDomainDepositor);
        uint256 directZeroBalance = gatewayWallet.availableBalance(address(differentToken), remoteDomainDepositor);

        assertEq(balance, directBalance, "First token balance should match gateway wallet directly");
        assertEq(zeroBalance, directZeroBalance, "Zero balance should match gateway wallet directly");
    }

    function test_balanceOfNativeCollateral_separateBalancesForDifferentDomains() public {
        // Register two remote domains
        uint32 secondRemoteDomain = 20002;
        address[] memory secondAttesters = new address[](2);
        secondAttesters[0] = makeAddr("secondAttester1");
        secondAttesters[1] = makeAddr("secondAttester2");

        address firstRemoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        vm.prank(owner);
        address secondRemoteDomainDepositor = reserve.registerRemoteDomain(
            secondRemoteDomain,
            makeAddr("secondDomainManager"),
            makeAddr("secondDomainPauser"),
            secondAttesters,
            2,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        bytes32 secondRemoteToken = bytes32(uint256(0xDEF123));
        vm.prank(owner);
        reserve.registerRemoteToken(address(token), secondRemoteDomain, secondRemoteToken);

        // Make deposits to both domains
        uint256 firstDomainDeposit = 200 * 10 ** 6;
        uint256 secondDomainDeposit = 400 * 10 ** 6;

        _makeDeposit(user, firstDomainDeposit);

        vm.startPrank(depositor);
        IERC20(address(token)).approve(address(reserve), secondDomainDeposit);
        reserve.depositToRemote(
            secondDomainDeposit, secondRemoteDomain, bytes32(uint256(uint160(depositor))), address(token), 0, ""
        );
        vm.stopPrank();

        // Check balances are separate for each domain
        uint256 firstDomainBalance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        uint256 secondDomainBalance = reserve.balanceOfNativeCollateral(address(token), secondRemoteDomain);

        assertEq(firstDomainBalance, firstDomainDeposit, "First domain balance should match its deposits");
        assertEq(secondDomainBalance, secondDomainDeposit, "Second domain balance should match its deposits");

        // Verify these match the gateway wallet directly
        assertEq(firstDomainBalance, gatewayWallet.availableBalance(address(token), firstRemoteDomainDepositor));
        assertEq(secondDomainBalance, gatewayWallet.availableBalance(address(token), secondRemoteDomainDepositor));
    }

    // ============ Failure Tests ============

    function test_balanceOfNativeCollateral_revertsWhenDomainNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, UNREGISTERED_DOMAIN)
        );
        reserve.balanceOfNativeCollateral(address(token), UNREGISTERED_DOMAIN);
    }

    function test_balanceOfNativeCollateral_revertsWhenDomainDeregistered() public {
        // Register and then deregister domain
        _registerRemoteDomain();
        _registerRemoteToken();

        vm.prank(owner);
        reserve.deregisterRemoteDomain(REMOTE_DOMAIN);

        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, REMOTE_DOMAIN)
        );
        reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
    }

    function test_balanceOfNativeCollateral_revertsWhenTokenNotRegistered() public {
        _registerRemoteDomain();
        // Note: not registering the token for this domain

        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.LocalTokenNotRegistered.selector, REMOTE_DOMAIN, address(token)
            )
        );
        reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
    }

    function test_balanceOfNativeCollateral_revertsWhenTokenDeregistered() public {
        _registerRemoteDomain();
        _registerRemoteToken();

        // Token should work initially
        uint256 balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        assertEq(balance, 0);

        // Deregister the token
        vm.prank(owner);
        reserve.deregisterRemoteToken(REMOTE_DOMAIN, REMOTE_TOKEN);

        // Now should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.LocalTokenNotRegistered.selector, REMOTE_DOMAIN, address(token)
            )
        );
        reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
    }

    function test_balanceOfNativeCollateral_worksAfterTokenReregistration() public {
        _registerRemoteDomain();
        _registerRemoteToken();

        // Should work initially
        uint256 balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        assertEq(balance, 0);

        // Deregister and reregister token
        vm.startPrank(owner);
        reserve.deregisterRemoteToken(REMOTE_DOMAIN, REMOTE_TOKEN);
        reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, REMOTE_TOKEN);
        vm.stopPrank();

        // Should work again
        balance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        assertEq(balance, 0);
    }

    // ============ Edge Case Tests ============

    function test_balanceOfNativeCollateral_revertsWithZeroAddressToken() public {
        _registerRemoteDomain();

        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.LocalTokenNotRegistered.selector, REMOTE_DOMAIN, address(0))
        );
        reserve.balanceOfNativeCollateral(address(0), REMOTE_DOMAIN);
    }

    function test_balanceOfNativeCollateral_revertsWithUnregisteredLocalToken() public {
        _registerRemoteDomain();

        // Create an unregistered token (not registered for this remote domain)
        address unregisteredToken = makeAddr("unregisteredToken");

        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.LocalTokenNotRegistered.selector, REMOTE_DOMAIN, unregisteredToken
            )
        );
        reserve.balanceOfNativeCollateral(unregisteredToken, REMOTE_DOMAIN);
    }

    function test_balanceOfNativeCollateral_consistentWithDirectGatewayWalletCall() public {
        address remoteDomainDepositor = _registerRemoteDomain();
        _registerRemoteToken();

        // Make some deposits
        _makeDeposit(user, DEPOSIT_AMOUNT);
        _makeDeposit(depositor, DEPOSIT_AMOUNT / 2);

        uint256 reserveBalance = reserve.balanceOfNativeCollateral(address(token), REMOTE_DOMAIN);
        uint256 directBalance = gatewayWallet.availableBalance(address(token), remoteDomainDepositor);

        assertEq(reserveBalance, directBalance, "Reserve balance should always match direct gateway wallet call");
    }
}
