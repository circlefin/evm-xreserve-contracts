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
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Test} from "forge-std/Test.sol";
import {UnauthorizedCaller, ZeroAddress, ZeroBytes32} from "src/common/Errors.sol";
import {Attestable} from "src/modules/remote-domain-depositor/Attestable.sol";
import {Immutables} from "src/modules/x-reserve/Immutables.sol";
import {Pausing} from "src/modules/x-reserve/Pausing.sol";
import {
    RemoteDomainRegistration,
    RemoteDomainRegistrationStorage
} from "src/modules/x-reserve/RemoteDomainRegistration.sol";
import {TokenSupport} from "src/modules/x-reserve/TokenSupport.sol";
import {RemoteDomainDepositor} from "src/RemoteDomainDepositor.sol";
import {DeployMockFiatToken} from "./../../utils/DeployMockFiatToken.sol";

contract RemoteDomainRegistrationHarness is Test, RemoteDomainRegistration {
    constructor()
        Immutables(
            makeAddr("gatewayMinter"),
            makeAddr("gatewayWallet"),
            makeAddr("tokenMessenger"),
            makeAddr("tokenMessengerV2")
        )
    {}

    function initialize(
        address owner,
        address registrationManager,
        address[] calldata supportedTokens,
        address remoteDomainDepositorImplementation
    ) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
        __TokenSupport_init(supportedTokens);

        // Deploy RemoteDomainDepositor implementation for testing
        __RemoteDomainRegistration_init(remoteDomainDepositorImplementation, registrationManager);
    }

    // Helper function to set the implementation address for testing
    function setRemoteDomainDepositorImplementation(address implementation) external {
        _getStorage().remoteDomainDepositorImplementation = implementation;
    }

    // Expose storage functions for testing
    function getStorageSlot() public pure returns (bytes32) {
        return RemoteDomainRegistrationStorage.SLOT;
    }

    function getStorageData(uint32 remoteDomain, bytes32 remoteToken) public view returns (address) {
        return RemoteDomainRegistrationStorage.get().remoteTokenToLocalTokenMapping[remoteDomain][remoteToken];
    }
}

// Mock contract for gateway wallet in RemoteDomainRegistration tests
contract MockGatewayWallet {
// Empty contract - forceApprove calls will succeed but do nothing meaningful
}

contract RemoteDomainRegistrationTest is Test, DeployMockFiatToken {
    RemoteDomainRegistrationHarness private remoteDomainRegistration;

    address private owner = makeAddr("owner");
    address private nonOwner = makeAddr("nonOwner");
    address private registrationManager = makeAddr("registrationManager");
    FiatTokenV2_2 private localToken;
    address private domainManager = makeAddr("domainManager");
    address private domainPauser = makeAddr("domainPauser");
    uint32 private remoteDomain = 1;
    bytes32 private remoteToken = bytes32(uint256(0x123));
    address[] private attesters;
    uint256 private constant SIGNATURE_THRESHOLD = 2;
    uint256 private constant PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = 50400; // ~7 days on Ethereum

    function setUp() public {
        remoteDomainRegistration = new RemoteDomainRegistrationHarness();

        localToken = deployMockFiatToken(owner);

        // Initialize with empty supported tokens and then add token separately
        address[] memory supportedTokens = new address[](0);
        remoteDomainRegistration.initialize(owner, owner, supportedTokens, address(new RemoteDomainDepositor()));

        // Setup attesters array
        attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        // Add localToken to supported tokens by default
        vm.prank(owner);
        remoteDomainRegistration.addSupportedToken(address(localToken));

        // Set registrationManager for testing
        vm.prank(owner);
        remoteDomainRegistration.updateRegistrationManager(registrationManager);
    }

    // Helper function to register a domain with default parameters
    function _registerDomain() internal returns (address) {
        bytes32 salt = keccak256(abi.encode(remoteDomain));
        bytes memory creationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(remoteDomainRegistration.remoteDomainDepositorImplementation(), bytes(""))
        );
        address expectedDepositorContractAddress =
            Create2.computeAddress(salt, keccak256(creationCode), address(remoteDomainRegistration));

        vm.expectEmit(true, true, true, true);
        emit RemoteDomainRegistration.RemoteDomainRegistered(
            remoteDomain,
            domainManager,
            expectedDepositorContractAddress,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.prank(registrationManager);
        return remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
    }

    // Helper function to register a domain without prank (for use within existing prank contexts)
    function _registerDomainNoPrank() internal returns (address) {
        return remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
    }

    // Helper function to register a domain and token with default parameters
    function _registerDomainAndToken() internal returns (address) {
        address depositorAddress = _registerDomain();
        vm.prank(registrationManager);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
        return depositorAddress;
    }

    // Helper function to register a domain and token without prank (for use within existing prank contexts)
    function _registerDomainAndTokenNoPrank() internal returns (address) {
        address depositorAddress = _registerDomainNoPrank();
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
        return depositorAddress;
    }

    // ============ Domain Registration Tests ============

    function test_registerRemoteDomain_successfullyDeploys() public {
        address depositorAddress = _registerDomain();

        // Verify the depositor contract was deployed
        assertTrue(depositorAddress != address(0));

        // Verify the depositor is properly initialized
        RemoteDomainDepositor depositor = RemoteDomainDepositor(depositorAddress);
        assertEq(depositor.owner(), address(remoteDomainRegistration));

        // Verify the depositor is an ERC1967 proxy pointing to the shared implementation
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address actualImpl = address(uint160(uint256(vm.load(depositorAddress, implementationSlot))));
        assertEq(actualImpl, remoteDomainRegistration.remoteDomainDepositorImplementation());

        // Verify the registration was recorded
        assertTrue(remoteDomainRegistration.isRemoteDomainRegistered(remoteDomain));
    }

    function test_initialize_revertsWhenZeroImplementation() public {
        // Create a fresh, uninitialized contract instance for this test
        RemoteDomainRegistrationHarness freshContract = new RemoteDomainRegistrationHarness();

        vm.expectRevert(abi.encodeWithSelector(RemoteDomainRegistration.InvalidImplementation.selector));
        freshContract.initialize(owner, owner, new address[](0), address(0));
    }

    function test_initialize_revertsWhenZeroRegistrationManager() public {
        // Create a fresh, uninitialized contract instance for this test
        RemoteDomainRegistrationHarness freshContract = new RemoteDomainRegistrationHarness();

        // Zero registrationManager should revert via _setRegistrationManager
        address impl = address(new RemoteDomainDepositor());
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        freshContract.initialize(owner, address(0), new address[](0), impl);
    }

    function test_registerRemoteDomain_revertsWhenNotAuthorized() public {
        vm.expectRevert(UnauthorizedCaller.selector);

        vm.startPrank(nonOwner);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();
    }

    function test_registerRemoteDomain_revertsWhenZeroDomainManager() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            address(0),
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();
    }

    function test_registerRemoteDomain_revertsWhenZeroDomainPauser() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            address(0),
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();
    }

    function test_registerRemoteDomain_revertsWhenEmptyAttestersArray() public {
        address[] memory emptyAttesters = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdTooHigh.selector, SIGNATURE_THRESHOLD, 0));

        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            emptyAttesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();
    }

    function test_registerRemoteDomain_revertsWhenZeroAddressInAttesters() public {
        address[] memory badAttesters = new address[](2);
        badAttesters[0] = makeAddr("attester1");
        badAttesters[1] = address(0); // This should cause the revert

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            badAttesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();
    }

    function test_registerRemoteDomain_revertsWhenAlreadyRegistered() public {
        vm.startPrank(registrationManager);

        // First register the domain
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Now try to register the same domain again - this should revert
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainAlreadyRegistered.selector, remoteDomain)
        );
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        vm.stopPrank();
    }

    function test_registerRemoteDomain_revertsWhenSignatureThresholdBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(Attestable.SignatureThresholdBelowMinimum.selector, 1, 2));

        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            1,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();
    }

    // ============ Domain Deregistration Tests ============

    function test_deregisterRemoteDomain_revertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));

        vm.startPrank(nonOwner);
        remoteDomainRegistration.deregisterRemoteDomain(remoteDomain);
        vm.stopPrank();
    }

    function test_deregisterRemoteDomain_revertsWhenNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, remoteDomain)
        );

        vm.startPrank(owner);
        remoteDomainRegistration.deregisterRemoteDomain(remoteDomain);
        vm.stopPrank();
    }

    function test_deregisterRemoteDomain_successWhenRegistered() public {
        // Register domain using helper
        _registerDomain();
        assertNotEq(remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain), address(0));

        // Deregister and verify
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit RemoteDomainRegistration.RemoteDomainDeregistered(remoteDomain);
        remoteDomainRegistration.deregisterRemoteDomain(remoteDomain);

        assertEq(remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain), address(0));
    }

    function test_deregisterRemoteDomain_preventsReregistration() public {
        // Test that re-registration fails after deregistration since the same address would be used

        // First registration
        address depositor1 = _registerDomain();
        assertTrue(depositor1 != address(0), "First registration should succeed");

        // Deregister domain
        vm.prank(owner);
        remoteDomainRegistration.deregisterRemoteDomain(remoteDomain);
        assertEq(remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain), address(0));

        // Second registration should fail because CREATE2 would try to deploy to the same address
        // which already has code (the first proxy contract)
        vm.prank(registrationManager);
        vm.expectRevert();
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Verify first depositor still exists
        assertTrue(depositor1.code.length > 0, "First depositor contract should still exist");
    }

    // ============ Token Registration Tests ============

    function test_registerRemoteToken_successfullyRegisters() public {
        _registerDomain();

        vm.prank(registrationManager);
        vm.expectEmit(true, true, true, false);
        emit RemoteDomainRegistration.RemoteTokenRegistered(address(localToken), remoteDomain, remoteToken);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);

        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(localToken));
    }

    function test_registerRemoteToken_revertsWhenNotAuthorized() public {
        vm.expectRevert(UnauthorizedCaller.selector);

        vm.startPrank(nonOwner);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
        vm.stopPrank();
    }

    function test_registerRemoteToken_revertsWhenZeroLocalToken() public {
        _registerDomain();

        vm.prank(registrationManager);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        remoteDomainRegistration.registerRemoteToken(address(0), remoteDomain, remoteToken);
    }

    function test_registerRemoteToken_revertsWhenTokenNotSupported() public {
        _registerDomain();

        address unsupportedToken = makeAddr("unsupportedToken");
        vm.prank(registrationManager);
        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, unsupportedToken));
        remoteDomainRegistration.registerRemoteToken(unsupportedToken, remoteDomain, remoteToken);
    }

    function test_registerRemoteToken_revertsWhenRemoteTokenIsZeroBytes32() public {
        _registerDomain();

        vm.prank(registrationManager);
        vm.expectRevert(abi.encodeWithSelector(ZeroBytes32.selector));
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, bytes32(0));
    }

    function test_registerRemoteToken_revertsWhenDomainNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, remoteDomain)
        );

        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
        vm.stopPrank();
    }

    function test_registerRemoteToken_revertsWhenLocalTokenAlreadyRegistered() public {
        _registerDomainAndToken();

        bytes32 remoteToken2 = bytes32(uint256(0x456));

        vm.prank(registrationManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.LocalTokenAlreadyRegistered.selector, remoteDomain, address(localToken)
            )
        );
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken2);
    }

    function test_registerRemoteToken_revertsWhenTokenAlreadyRegistered() public {
        _registerDomainAndToken();

        vm.prank(registrationManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.RemoteTokenAlreadyRegistered.selector, remoteDomain, remoteToken
            )
        );
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
    }

    // ============ Token Deregistration Tests ============

    function test_deregisterRemoteToken_successfullyDeregisters() public {
        _registerDomainAndToken();

        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit RemoteDomainRegistration.RemoteTokenDeregistered(address(localToken), remoteDomain, remoteToken);
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);

        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(0));
    }

    function test_deregisterRemoteToken_revertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));

        vm.startPrank(nonOwner);
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);
        vm.stopPrank();
    }

    function test_deregisterRemoteToken_revertsWhenDomainNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, remoteDomain)
        );

        vm.prank(owner);
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);
    }

    function test_deregisterRemoteToken_revertsWhenTokenNotRegistered() public {
        _registerDomain();

        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.RemoteTokenNotRegistered.selector, remoteDomain, remoteToken
            )
        );
        vm.prank(owner);
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);
    }

    function test_deregisterRemoteToken_allowsReregistration() public {
        _registerDomainAndToken();

        // Deregister token
        vm.prank(owner);
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(0));

        // Re-register should work
        vm.prank(registrationManager);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(localToken));
    }

    // ============ Set Remote Domain Hook Executor Tests ============

    function test_setRemoteDomainHookExecutor_revertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        remoteDomainRegistration.setRemoteDomainHookExecutor(remoteDomain, makeAddr("hookExecutor"));
    }

    function test_setRemoteDomainHookExecutor_revertsWhenDomainNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, remoteDomain)
        );
        vm.prank(owner);
        remoteDomainRegistration.setRemoteDomainHookExecutor(remoteDomain, makeAddr("hookExecutor"));
    }

    function test_setRemoteDomainHookExecutor_succeedsWithNewHookExecutor() public {
        _registerDomain();

        address hookExecutor = makeAddr("hookExecutor");
        vm.expectEmit(true, true, true, false);
        emit RemoteDomainRegistration.RemoteDomainHookExecutorUpdated(remoteDomain, address(0), hookExecutor);

        vm.prank(owner);
        remoteDomainRegistration.setRemoteDomainHookExecutor(remoteDomain, hookExecutor);

        assertEq(remoteDomainRegistration.getRemoteDomainHookExecutor(remoteDomain), hookExecutor);
    }

    function test_setRemoteDomainHookExecutor_succeedsWithZeroAddress() public {
        address hookExecutor = makeAddr("hookExecutor");
        vm.prank(registrationManager);
        remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            hookExecutor
        );

        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit RemoteDomainRegistration.RemoteDomainHookExecutorUpdated(remoteDomain, hookExecutor, address(0));
        remoteDomainRegistration.setRemoteDomainHookExecutor(remoteDomain, address(0));

        assertEq(remoteDomainRegistration.getRemoteDomainHookExecutor(remoteDomain), address(0));
    }

    function test_setRemoteDomainHookExecutor_isIdempotent() public {
        _registerDomain();

        address hookExecutor = makeAddr("hookExecutor");
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, false);
        emit RemoteDomainRegistration.RemoteDomainHookExecutorUpdated(remoteDomain, address(0), hookExecutor);
        remoteDomainRegistration.setRemoteDomainHookExecutor(remoteDomain, hookExecutor);

        vm.expectEmit(true, true, true, false);
        emit RemoteDomainRegistration.RemoteDomainHookExecutorUpdated(remoteDomain, hookExecutor, hookExecutor);
        remoteDomainRegistration.setRemoteDomainHookExecutor(remoteDomain, hookExecutor);
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function test_fullWorkflow_domainAndTokenRegistration() public {
        // Register domain using registrationManager
        vm.startPrank(registrationManager);
        address depositorAddress = _registerDomainNoPrank();
        assertTrue(depositorAddress != address(0));
        vm.stopPrank();

        // Verify the depositor contract was initialized correctly
        RemoteDomainDepositor depositor = RemoteDomainDepositor(depositorAddress);
        assertEq(depositor.owner(), address(remoteDomainRegistration));

        // Verify the domain manager is valid
        assertTrue(domainManager != address(0));

        // Register multiple tokens
        FiatTokenV2_2 localToken2 = deployMockFiatToken(owner);
        bytes32 remoteToken2 = bytes32(uint256(0x456));

        // Add supported token using owner (owner permission required)
        vm.prank(owner);
        remoteDomainRegistration.addSupportedToken(address(localToken2));

        // Register tokens using registrationManager
        vm.startPrank(registrationManager);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);
        remoteDomainRegistration.registerRemoteToken(address(localToken2), remoteDomain, remoteToken2);
        vm.stopPrank();

        // Verify tokens are registered
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(localToken));
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken2), address(localToken2));

        // Deregister operations using owner (owner permission required)
        vm.startPrank(owner);

        // Deregister one token
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(0));
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken2), address(localToken2));

        // Deregister domain (preserves token mappings)
        remoteDomainRegistration.deregisterRemoteDomain(remoteDomain);
        assertEq(remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain), address(0));
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken2), address(localToken2));

        vm.stopPrank();
    }

    // ============ Storage and Utility Tests ============

    function test_getStorageData_returnsZeroWhenNotSet() public view {
        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(0));
    }

    function test_getStorageData_returnsCorrectTokenWhenRegistered() public {
        _registerDomainAndToken();

        assertEq(remoteDomainRegistration.getStorageData(remoteDomain, remoteToken), address(localToken));
        assertNotEq(remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain), address(0));
    }

    function test_getStorageSlot_returnsCorrectSlot() public view {
        bytes32 actualSlot = remoteDomainRegistration.getStorageSlot();
        assertEq(
            actualSlot,
            keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.RemoteDomainRegistration"))) - 1))
                & ~bytes32(uint256(0xff)),
            "Storage slot should match expected EIP-7201 slot."
        );
    }

    function testFuzz_getStorageData_handlesAnyValues(uint32 fuzzRemoteDomain, bytes32 fuzzRemoteToken) public view {
        // Should return zero address for any unregistered combination
        assertEq(remoteDomainRegistration.getStorageData(fuzzRemoteDomain, fuzzRemoteToken), address(0));
    }

    function test_sharedImplementation_multipleDomainsUseSameImplementation() public {
        vm.startPrank(registrationManager);

        // Register first domain
        address depositor1 = _registerDomainNoPrank();

        // Register second domain
        uint32 remoteDomain2 = 2;
        address domainManager2 = makeAddr("domainManager2");
        address[] memory attesters2 = new address[](2);
        attesters2[0] = makeAddr("attester2");
        attesters2[1] = makeAddr("attester3");

        address depositor2 = remoteDomainRegistration.registerRemoteDomain(
            remoteDomain2,
            domainManager2,
            makeAddr("domainPauser2"),
            attesters2,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Verify different proxies use same implementation
        assertTrue(depositor1 != depositor2);
        address implementation = remoteDomainRegistration.remoteDomainDepositorImplementation();
        assertTrue(implementation != address(0));

        // Verify both depositors are properly initialized
        assertEq(RemoteDomainDepositor(depositor1).owner(), address(remoteDomainRegistration));
        assertEq(RemoteDomainDepositor(depositor2).owner(), address(remoteDomainRegistration));

        // Verify the domain managers are valid
        assertTrue(domainManager != address(0));
        assertTrue(domainManager2 != address(0));

        vm.stopPrank();
    }

    function test_viewFunctions_workWhenUninitialized() public {
        RemoteDomainRegistrationHarness freshRegistration = new RemoteDomainRegistrationHarness();
        // Don't initialize

        assertEq(freshRegistration.getStorageData(remoteDomain, remoteToken), address(0));
        assertEq(freshRegistration.getRemoteDomainDepositor(remoteDomain), address(0));
    }

    // ============ View Function Tests ============

    function test_isRemoteDomainRegistered_returnsFalseWhenNotRegistered() public view {
        assertFalse(remoteDomainRegistration.isRemoteDomainRegistered(remoteDomain));
    }

    function test_isRemoteDomainRegistered_returnsTrueWhenRegistered() public {
        _registerDomain();
        assertTrue(remoteDomainRegistration.isRemoteDomainRegistered(remoteDomain));
    }

    function test_isRemoteDomainRegistered_returnsFalseAfterDeregistration() public {
        _registerDomain();
        assertTrue(remoteDomainRegistration.isRemoteDomainRegistered(remoteDomain));

        vm.prank(owner);
        remoteDomainRegistration.deregisterRemoteDomain(remoteDomain);
        assertFalse(remoteDomainRegistration.isRemoteDomainRegistered(remoteDomain));
    }

    function test_isRemoteTokenRegistered_returnsFalseWhenNotRegistered() public {
        _registerDomain();
        assertFalse(remoteDomainRegistration.isRemoteTokenRegistered(remoteDomain, remoteToken));
    }

    function test_isRemoteTokenRegistered_returnsTrueWhenRegistered() public {
        _registerDomainAndToken();
        assertTrue(remoteDomainRegistration.isRemoteTokenRegistered(remoteDomain, remoteToken));
    }

    function test_isRemoteTokenRegistered_returnsFalseAfterDeregistration() public {
        _registerDomainAndToken();
        assertTrue(remoteDomainRegistration.isRemoteTokenRegistered(remoteDomain, remoteToken));

        vm.prank(owner);
        remoteDomainRegistration.deregisterRemoteToken(remoteDomain, remoteToken);
        assertFalse(remoteDomainRegistration.isRemoteTokenRegistered(remoteDomain, remoteToken));
    }

    function test_isRemoteTokenRegistered_returnsFalseWhenDomainNotRegistered() public view {
        // Domain not registered, so token should return false even if we try to check
        assertFalse(remoteDomainRegistration.isRemoteTokenRegistered(remoteDomain, remoteToken));
    }

    function test_getRemoteToken() public {
        bytes32 retrievedRemoteToken = remoteDomainRegistration.getRemoteToken(remoteDomain, address(localToken));
        assertEq(retrievedRemoteToken, bytes32(0));

        // Register remote domain and token
        _registerDomainAndToken();

        // Test getRemoteToken returns correct token after registration
        retrievedRemoteToken = remoteDomainRegistration.getRemoteToken(remoteDomain, address(localToken));
        assertEq(retrievedRemoteToken, remoteToken);
    }

    function test_getRemoteDomainDepositor() public {
        address retrievedDepositor = remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain);
        assertEq(retrievedDepositor, address(0));

        // Register remote domain
        address expectedDepositor = _registerDomain();

        // Test getRemoteDomainDepositor returns correct depositor after registration
        retrievedDepositor = remoteDomainRegistration.getRemoteDomainDepositor(remoteDomain);
        assertEq(retrievedDepositor, expectedDepositor);
    }

    // ============ CREATE2 Implementation Tests ============

    function test_create2ImplementationDeployment() public {
        // Test that implementation deployment uses CREATE2 and works correctly

        // Deploy and initialize harness
        RemoteDomainRegistrationHarness test1 = new RemoteDomainRegistrationHarness();
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(localToken);

        vm.prank(owner);
        test1.initialize(owner, owner, supportedTokens, address(new RemoteDomainDepositor()));

        address implementation = test1.remoteDomainDepositorImplementation();
        assertTrue(implementation != address(0));

        // Verify the implementation is a valid RemoteDomainDepositor contract
        assertTrue(implementation.code.length > 0);

        // Test that multiple domain registrations use the same implementation
        vm.startPrank(owner);
        address depositor1 = test1.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        address depositor2 = test1.registerRemoteDomain(
            remoteDomain + 1,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );
        vm.stopPrank();

        // Both depositors should exist
        assertTrue(depositor1 != address(0));
        assertTrue(depositor2 != address(0));
        assertTrue(depositor1 != depositor2); // Different proxy addresses (due to different salts)

        // But both should point to the same implementation
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address actualImpl1 = address(uint160(uint256(vm.load(depositor1, implementationSlot))));
        address actualImpl2 = address(uint160(uint256(vm.load(depositor2, implementationSlot))));

        assertEq(actualImpl1, implementation);
        assertEq(actualImpl2, implementation);
        assertEq(actualImpl1, actualImpl2); // Same shared implementation

        // Verify both proxies are functional
        assertTrue(RemoteDomainDepositor(depositor1).owner() == address(test1));
        assertTrue(RemoteDomainDepositor(depositor2).owner() == address(test1));
    }

    // ============ CEI Pattern & Failure Recovery Tests ============

    function test_deploymentFailure_rollsBackTransaction() public {
        // This test shows that if deployment fails, the entire transaction rolls back

        RemoteDomainRegistrationHarness testHarness = new RemoteDomainRegistrationHarness();
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(localToken);

        vm.prank(owner);
        testHarness.initialize(owner, owner, supportedTokens, address(new RemoteDomainDepositor()));

        // Set implementation to zero to force deployment failure
        testHarness.setRemoteDomainDepositorImplementation(address(0));

        // Attempt to register domain - should fail due to zero implementation
        vm.prank(owner);
        vm.expectRevert(); // CREATE2 will fail with zero-length bytecode
        testHarness.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Verify domain was NOT registered (transaction rolled back)
        assertFalse(
            testHarness.isRemoteDomainRegistered(remoteDomain),
            "Domain should not be registered after failed deployment"
        );

        // Fix the implementation and try again - should work
        testHarness.setRemoteDomainDepositorImplementation(address(new RemoteDomainDepositor()));

        vm.prank(owner);
        address depositor = testHarness.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Domain should now be registered
        assertTrue(testHarness.isRemoteDomainRegistered(remoteDomain));
        assertTrue(depositor != address(0));
    }

    // ============ Role Management Tests ============

    function test_updateRegistrationManager_success() public {
        address newManager = makeAddr("newManager");
        address oldManager = remoteDomainRegistration.registrationManager();

        vm.expectEmit(true, true, false, false);
        emit RemoteDomainRegistration.RegistrationManagerUpdated(oldManager, newManager);

        vm.prank(owner);
        remoteDomainRegistration.updateRegistrationManager(newManager);

        assertEq(remoteDomainRegistration.registrationManager(), newManager);
    }

    function test_updateRegistrationManager_revertsWhenNotOwner() public {
        address newManager = makeAddr("newManager");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));

        vm.prank(nonOwner);
        remoteDomainRegistration.updateRegistrationManager(newManager);
    }

    function test_updateRegistrationManager_revertsWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.prank(owner);
        remoteDomainRegistration.updateRegistrationManager(address(0));
    }

    function test_registrationManager_returnsCorrectAddress() public {
        // Test with current manager
        assertEq(remoteDomainRegistration.registrationManager(), registrationManager);

        // Test after update
        address newManager = makeAddr("newManager");
        vm.prank(owner);
        remoteDomainRegistration.updateRegistrationManager(newManager);

        assertEq(remoteDomainRegistration.registrationManager(), newManager);
    }

    function test_registerRemoteDomain_successWithRole() public {
        // Verify that registrationManager can register domains
        vm.prank(registrationManager);
        address depositor = remoteDomainRegistration.registerRemoteDomain(
            2,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        assertTrue(depositor != address(0));
        assertTrue(remoteDomainRegistration.isRemoteDomainRegistered(2));
    }

    function test_registerRemoteToken_successWithRole() public {
        _registerDomain();

        // Verify that registrationManager can register tokens
        vm.prank(registrationManager);
        remoteDomainRegistration.registerRemoteToken(address(localToken), remoteDomain, remoteToken);

        assertTrue(remoteDomainRegistration.isRemoteTokenRegistered(remoteDomain, remoteToken));
    }

    // ============ Domain Pause State Tests ============

    function test_setDomainPauseState_revertsWhenCallerIsNotDomainPauser() public {
        // Register a remote domain with a valid domain pauser
        vm.prank(registrationManager);
        address depositor = remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Verify that the depositor was created
        assertTrue(depositor != address(0), "Depositor should be created");

        // Attempt to set domain pause state with owner (should fail - only domain pauser allowed)
        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.UnauthorizedDomainPauser.selector, remoteDomain, owner)
        );
        vm.prank(owner);
        remoteDomainRegistration.setDomainPauseState(remoteDomain, true, false);

        // Attempt to set domain pause state with registrationManager (should fail - only domain pauser allowed)
        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.UnauthorizedDomainPauser.selector, remoteDomain, registrationManager
            )
        );
        vm.prank(registrationManager);
        remoteDomainRegistration.setDomainPauseState(remoteDomain, true, false);
    }

    function test_setDomainPauseState_successWhenCalledByDomainPauser() public {
        // Register a remote domain
        vm.prank(registrationManager);
        address depositor = remoteDomainRegistration.registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            SIGNATURE_THRESHOLD,
            PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
            address(0)
        );

        // Verify that the depositor was created
        assertTrue(depositor != address(0), "Depositor should be created");

        // Initially, both deposits and withdrawals should not be paused
        assertFalse(
            remoteDomainRegistration.domainDepositsPaused(remoteDomain), "Deposits should not be paused initially"
        );
        assertFalse(
            remoteDomainRegistration.domainWithdrawalsPaused(remoteDomain), "Withdrawals should not be paused initially"
        );

        // Set domain pause state as authorized domain pauser
        vm.expectEmit(true, false, false, true);
        emit Pausing.DomainPauseStateUpdated(remoteDomain, true, false);
        vm.prank(domainPauser);
        remoteDomainRegistration.setDomainPauseState(remoteDomain, true, false);

        // Verify pause state was updated
        assertTrue(remoteDomainRegistration.domainDepositsPaused(remoteDomain), "Deposits should be paused");
        assertFalse(remoteDomainRegistration.domainWithdrawalsPaused(remoteDomain), "Withdrawals should not be paused");
    }

    function test_setDomainPauseState_revertsWhenDomainNotRegistered() public {
        uint32 unregisteredDomain = 99999;

        vm.expectRevert(
            abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, unregisteredDomain)
        );
        vm.prank(domainPauser);
        remoteDomainRegistration.setDomainPauseState(unregisteredDomain, true, false);
    }

    // ============ Initialization Protection Tests ============

    function test_remoteDomainDepositor_cannotBeReinitializedAfterRegistration() public {
        // Register a remote domain which will deploy and initialize the RemoteDomainDepositor
        address depositorAddress = _registerDomain();

        // Verify the depositor was deployed and initialized
        assertTrue(depositorAddress != address(0), "Depositor should be deployed");
        RemoteDomainDepositor depositor = RemoteDomainDepositor(depositorAddress);

        // Try to reinitialize the depositor - should fail since it's using `initializer` modifier
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        vm.prank(owner);
        depositor.initialize(
            domainManager, domainPauser, attesters, SIGNATURE_THRESHOLD, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Also try as the actual owner of the depositor (which is the remoteDomainRegistration contract)
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        vm.prank(address(remoteDomainRegistration));
        depositor.initialize(
            domainManager, domainPauser, attesters, SIGNATURE_THRESHOLD, PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS
        );

        // Verify the depositor is still functional with original settings
        assertEq(depositor.owner(), address(remoteDomainRegistration), "Owner should remain unchanged");
    }
}
