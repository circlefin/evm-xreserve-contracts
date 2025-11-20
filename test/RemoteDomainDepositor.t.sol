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
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {RemoteDomainDepositor} from "./../src/RemoteDomainDepositor.sol";
import {UpgradeablePlaceholder} from "./../src/UpgradeablePlaceholder.sol";
import {xReserve} from "./../src/xReserve.sol";
import {DeployXReserve} from "./utils/DeployXReserve.sol";
import {ForkTestUtils} from "./utils/ForkTestUtils.sol";

contract RemoteDomainDepositorTest is Test {
    RemoteDomainDepositor private remoteDomainDepositor;

    function _createAttesters() internal returns (address[] memory) {
        address[] memory attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");
        return attesters;
    }

    function setUp() public {
        address[] memory attesters = _createAttesters();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(new RemoteDomainDepositor()),
            abi.encodeWithSelector(
                RemoteDomainDepositor.initialize.selector,
                makeAddr("domainManager"),
                makeAddr("domainPauser"),
                attesters,
                2,
                100
            )
        );
        remoteDomainDepositor = RemoteDomainDepositor(address(proxy));
    }

    function test_upgrade_revertsIfNotOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        remoteDomainDepositor.upgradeToAndCall(makeAddr("notOwner"), new bytes(0));
    }

    function test_cannotUpgradeFromUpgradeablePlaceholderToRemoteDomainDepositor() public {
        // Deploy UpgradeablePlaceholder as implementation
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();

        // Deploy proxy with UpgradeablePlaceholder as implementation
        bytes memory initData = abi.encodeWithSelector(
            UpgradeablePlaceholder.initialize.selector,
            address(this) // Set test contract as owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(placeholder), initData);

        // Verify proxy is initialized with UpgradeablePlaceholder
        UpgradeablePlaceholder proxyAsPlaceholder = UpgradeablePlaceholder(address(proxy));
        assertEq(proxyAsPlaceholder.owner(), address(this), "Should be initialized with test as owner");

        // Deploy RemoteDomainDepositor implementation
        RemoteDomainDepositor newImpl = new RemoteDomainDepositor();

        // Create attesters for the RemoteDomainDepositor initialization
        address[] memory attesters = _createAttesters();

        // Try to upgrade to RemoteDomainDepositor and reinitialize
        // This should fail because RemoteDomainDepositor uses `initializer` modifier
        // which prevents reinitialization after the proxy was already initialized
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        proxyAsPlaceholder.upgradeToAndCall(
            address(newImpl),
            abi.encodeWithSelector(
                RemoteDomainDepositor.initialize.selector,
                makeAddr("domainManager"),
                makeAddr("domainPauser"),
                attesters,
                2,
                100
            )
        );

        // Verify the proxy is still using UpgradeablePlaceholder
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(address(proxy), implementationSlot))));
        assertEq(currentImpl, address(placeholder), "Implementation should remain as UpgradeablePlaceholder");
    }
}

// Integration tests using real xReserve
contract RemoteDomainDepositorIntegrationTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private domainManager = makeAddr("domainManager");
    address private domainPauser = makeAddr("domainPauser");
    address private newDomainPauser = makeAddr("newDomainPauser");
    address private unauthorized = makeAddr("unauthorized");

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

        // Register domain 1 (the shared implementation's domain) so depositors can manage its pauser
        vm.prank(owner);
        reserve.registerRemoteDomain(
            1, // The domain used by the shared implementation
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
    }

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
}
