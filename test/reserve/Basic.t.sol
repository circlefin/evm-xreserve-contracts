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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {RemoteDomainDepositor} from "./../../src/RemoteDomainDepositor.sol";
import {UpgradeablePlaceholder} from "./../../src/UpgradeablePlaceholder.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";
import {ForkTestUtils} from "./../utils/ForkTestUtils.sol";

contract XReserveHarness is xReserve {
    constructor(
        address gatewayMinterAddress_,
        address gatewayWalletAddress_,
        address tokenMessengerAddress_,
        address tokenMessengerV2Address_
    ) xReserve(gatewayMinterAddress_, gatewayWalletAddress_, tokenMessengerAddress_, tokenMessengerV2Address_) {}

    // Helper function to expose the internal _getGatewayWallet function for testing
    function getGatewayWallet() external view returns (address) {
        return gatewayWallet;
    }
}

contract XReserveV2 is xReserve {
    constructor(
        address gatewayMinterAddress_,
        address gatewayWalletAddress_,
        address tokenMessengerAddress_,
        address tokenMessengerV2Address_
    ) xReserve(gatewayMinterAddress_, gatewayWalletAddress_, tokenMessengerAddress_, tokenMessengerV2Address_) {}

    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}

contract XReserveBasicTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private pauser = makeAddr("pauser");
    address private blocklister = makeAddr("blocklister");
    address private user = makeAddr("user");

    address private gatewayMinter;
    address private gatewayWallet;
    address private tokenMessenger;
    address private tokenMessengerV2;

    uint32 private domain;

    function setUp() public {
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        token = FiatTokenV2_2(forkedVars.usdc);
        domain = forkedVars.domain;
        gatewayMinter = forkedVars.gatewayMinter;
        gatewayWallet = forkedVars.gatewayWallet;
        tokenMessenger = forkedVars.tokenMessenger;
        tokenMessengerV2 = forkedVars.tokenMessengerV2;

        reserve = deployXReserve(owner, domain, gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);
    }

    // ============ Initialization Tests ============

    function test_initialize_success() public {
        // Deploy fresh contracts to test initialization
        xReserve newImplementation = new xReserve(gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);

        ERC1967Proxy newProxy = new ERC1967Proxy(
            address(new UpgradeablePlaceholder()), abi.encodeWithSignature("initialize(address)", owner)
        );

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(token);

        // Deploy RemoteDomainDepositor implementation for testing
        address remoteDomainDepositorImplementation = address(new RemoteDomainDepositor());

        vm.prank(owner);
        UpgradeablePlaceholder(address(newProxy)).upgradeToAndCall(
            address(newImplementation),
            abi.encodeWithSignature(
                "initialize(uint32,address,address,address,address[],address)",
                domain,
                pauser,
                blocklister,
                owner, // registrationManager
                supportedTokens,
                remoteDomainDepositorImplementation
            )
        );

        xReserve newReserve = xReserve(address(newProxy));

        // Verify initialization
        assertEq(newReserve.owner(), owner);
        assertEq(newReserve.gatewayMinter(), gatewayMinter);
        assertEq(newReserve.gatewayWallet(), gatewayWallet);
        assertEq(newReserve.tokenMessenger(), tokenMessenger);
        assertEq(newReserve.tokenMessengerV2(), tokenMessengerV2);
        assertEq(newReserve.domain(), domain);
    }

    function test_initialize_twice_reverts() public {
        address[] memory supportedTokens = new address[](0);

        // Deploy RemoteDomainDepositor implementation for testing
        address remoteDomainDepositorImplementation = address(new RemoteDomainDepositor());

        vm.expectRevert();
        reserve.initialize(domain, pauser, blocklister, owner, supportedTokens, remoteDomainDepositorImplementation);
    }

    // ============ Immutable State Tests ============

    function test_immutableAddresses() public view {
        assertEq(reserve.gatewayMinter(), gatewayMinter);
        assertEq(reserve.gatewayWallet(), gatewayWallet);
        assertEq(reserve.tokenMessenger(), tokenMessenger);
        assertEq(reserve.tokenMessengerV2(), tokenMessengerV2);
    }

    // ============ Upgrade Tests ============

    function test_upgrade_success() public {
        // Deploy new implementation
        XReserveV2 newImplementation = new XReserveV2(gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);

        // Upgrade as owner
        vm.prank(owner);
        reserve.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade
        XReserveV2 upgradedReserve = XReserveV2(address(reserve));
        assertEq(upgradedReserve.version(), "2.0.0");
    }

    function test_upgrade_revertsIfNotOwner() public {
        XReserveV2 newImplementation = new XReserveV2(gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);

        vm.prank(user);
        vm.expectRevert();
        reserve.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgrade_revertsWithReinitializer() public {
        // Deploy RemoteDomainDepositor implementation for testing
        address remoteDomainDepositorImplementation = address(new RemoteDomainDepositor());

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        reserve.initialize(domain, pauser, blocklister, owner, new address[](0), remoteDomainDepositorImplementation);
    }

    function test_remoteDomainRegistration_inherited() public {
        // Test that xReserve inherited RemoteDomainRegistration functionality
        // by checking that it has access to the methods

        // Create test data
        uint32 remoteDomain = 1;
        address domainManager = makeAddr("domainManager");
        address domainPauser = makeAddr("domainPauser");
        address[] memory attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        // Add a token to supported tokens first
        address localToken = address(token);
        vm.prank(owner);
        reserve.addSupportedToken(localToken);

        // Test registerRemoteDomain (should not revert due to missing function)
        vm.prank(owner);
        address depositorAddress =
            reserve.registerRemoteDomain(remoteDomain, domainManager, domainPauser, attesters, 2, 50400, address(0));

        // Verify the domain was registered
        assertTrue(depositorAddress != address(0));
        assertTrue(reserve.isRemoteDomainRegistered(remoteDomain));

        // Test registerRemoteToken
        bytes32 remoteToken = bytes32(uint256(0x123));
        vm.prank(owner);
        reserve.registerRemoteToken(localToken, remoteDomain, remoteToken);

        // Verify the token was registered
        assertTrue(reserve.isRemoteTokenRegistered(remoteDomain, remoteToken));

        // Test deregisterRemoteToken
        vm.prank(owner);
        reserve.deregisterRemoteToken(remoteDomain, remoteToken);

        // Verify the token was deregistered
        assertFalse(reserve.isRemoteTokenRegistered(remoteDomain, remoteToken));

        // Test deregisterRemoteDomain
        vm.prank(owner);
        reserve.deregisterRemoteDomain(remoteDomain);

        // Verify the domain was deregistered
        assertFalse(reserve.isRemoteDomainRegistered(remoteDomain));
    }

    function test_getGatewayWallet_returnsCorrectAddress() public {
        // Create a harness that exposes the internal _getGatewayWallet function
        xReserve testReserve = new xReserve(gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);

        // Test the override implementation
        assertEq(address(testReserve.gatewayWallet()), gatewayWallet);
    }
}
