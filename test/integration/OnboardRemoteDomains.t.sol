/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity ^0.8.29;

import {Create2Factory} from "@gateway/script/Create2Factory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployXReserve} from "deploy-contracts/001_DeployXReserve.sol";
import {OnboardRemoteDomains} from "deploy-contracts/005_OnboardRemoteDomains.s.sol";
import {Test} from "forge-std/Test.sol";
import {xReserve} from "src/xReserve.sol";

contract OnboardRemoteDomainIntegrationTest is Test {
    Create2Factory private factory;
    address private deployerAddress;

    function setUp() public {
        vm.setEnv("ENV", "LOCAL");

        // Deterministic deployer and factory
        deployerAddress = makeAddr("deployer");
        factory = new Create2Factory(deployerAddress);

        vm.setEnv("LOCAL_CREATE2_FACTORY_ADDRESS", vm.toString(address(factory)));
        vm.setEnv("LOCAL_DEPLOYER_ADDRESS", vm.toString(deployerAddress));

        // xReserve env
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);
        vm.setEnv("X_RESERVE_OWNER_ADDRESS", vm.toString(owner));
        vm.setEnv("X_RESERVE_PAUSER_ADDRESS", vm.toString(makeAddr("pauser")));
        vm.setEnv("X_RESERVE_BLOCKLISTER_ADDRESS", vm.toString(makeAddr("blocklister")));
        address registrationManager = makeAddr("registrationManager");
        vm.setEnv("X_RESERVE_REGISTRATION_MANAGER_ADDRESS", vm.toString(registrationManager));

        vm.setEnv("X_RESERVE_GATEWAY_MINTER_ADDRESS", vm.toString(makeAddr("gatewayMinter")));
        vm.setEnv("X_RESERVE_GATEWAY_WALLET_ADDRESS", vm.toString(makeAddr("gatewayWallet")));
        vm.setEnv("X_RESERVE_TOKEN_MESSENGER_ADDRESS", vm.toString(makeAddr("tokenMessenger")));
        vm.setEnv("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS", vm.toString(makeAddr("tokenMessengerV2")));

        // Deploy token and RemoteDomainDepositor impl for init
        ERC20Mock localToken = new ERC20Mock();
        vm.setEnv("X_RESERVE_SUPPORTED_TOKEN_1", vm.toString(address(localToken)));

        // Deploy and set RemoteDomainDepositor impl address
        // We rely on 001_DeployXReserve to deploy it and expose the address
        // But for completeness in tests, deploy a dummy implementation to ensure non-zero address
        // The actual value will be set by the deployment script run() return values
        vm.setEnv("X_RESERVE_DOMAIN", "1");
    }

    function test_onboardRemoteDomain_registersDomainAndToken() public {
        // Deploy the core system first
        DeployXReserve deployer = new DeployXReserve();
        (address remoteDomainDepositorImplAddress,,, address xReserveProxyAddress) = deployer.run();

        // Wire deployed addresses for the onboarding script
        vm.setEnv("X_RESERVE_PROXY_ADDRESS", vm.toString(xReserveProxyAddress));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS", vm.toString(remoteDomainDepositorImplAddress));

        // Configure a single domain (index 1) with required values
        uint32 remoteDomain = 7777;
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1", vm.toString(remoteDomain));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_MANAGER_ADDRESS", vm.toString(makeAddr("domainMgr")));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_PAUSER_ADDRESS", vm.toString(makeAddr("domainPauser")));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_HOOK_EXECUTOR_ADDRESS", vm.toString(address(0)));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_SIGNATURE_THRESHOLD", vm.toString(uint256(2)));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS", vm.toString(uint256(10)));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_ATTESTER_1", vm.toString(makeAddr("attester1")));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_ATTESTER_2", vm.toString(makeAddr("attester2")));

        // Token mapping required (single mapping per domain)
        address localToken = vm.envAddress("X_RESERVE_SUPPORTED_TOKEN_1");
        bytes32 remoteToken = bytes32(uint256(0xDEADBEEF));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_LOCAL_TOKEN", vm.toString(localToken));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_1_REMOTE_TOKEN", vm.toString(remoteToken));

        // Run onboarding
        OnboardRemoteDomains onboard = new OnboardRemoteDomains();
        onboard.run();

        // Assertions on xReserve state
        xReserve reserve = xReserve(xReserveProxyAddress);
        // Domain should be registered (depositor address non-zero)
        address depositor = reserve.getRemoteDomainDepositor(remoteDomain);
        assertTrue(depositor != address(0), "Remote domain depositor should be set");

        // Token mapping should be set
        bytes32 storedRemoteToken = reserve.getRemoteToken(remoteDomain, localToken);
        assertEq(storedRemoteToken, remoteToken, "Remote token mapping should be registered");
    }
}
