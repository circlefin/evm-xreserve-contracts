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

import {DeployXReserve} from "deploy-contracts/001_DeployXReserve.sol";
import {DeployedContractBytecodeValidation} from "deploy-contracts/002_DeployedContractBytecodeValidation.s.sol";
import {DeployedContractStateValidation} from "deploy-contracts/003_DeployedContractStateValidation.s.sol";
import {Test} from "forge-std/Test.sol";
import {Create2Factory} from "lib/evm-gateway-contracts/script/Create2Factory.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

/// @title DeployAndValidateIntegrationTest
/// @notice Integration test that deploys xReserve system and validates bytecode
/// @dev Tests the complete flow: deploy -> validate constructor -> validate runtime -> validate proxy
contract DeployAndValidateIntegrationTest is Test {
    DeployXReserve public deployScript;
    DeployedContractBytecodeValidation public bytecodeValidationScript;
    DeployedContractStateValidation public stateValidationScript;

    // Test addresses (mock values for testing)
    address public constant TEST_GATEWAY_MINTER = address(0x1111111111111111111111111111111111111111);
    address public constant TEST_GATEWAY_WALLET = address(0x2222222222222222222222222222222222222222);
    address public constant TEST_TOKEN_MESSENGER = address(0x3333333333333333333333333333333333333333);
    address public constant TEST_TOKEN_MESSENGER_V2 = address(0x4444444444444444444444444444444444444444);
    address public constant TEST_PAUSER = address(0x5555555555555555555555555555555555555555);
    address public constant TEST_BLOCKLISTER = address(0x6666666666666666666666666666666666666666);
    address public constant TEST_REGISTRATION_MANAGER = address(0x7777777777777777777777777777777777777777);
    address public constant TEST_OWNER = address(0x8888888888888888888888888888888888888888);
    address public testSupportedToken;

    // Test configuration
    uint32 public constant TEST_DOMAIN = 1;

    // Salt constants for CREATE2 deployments
    bytes32 public constant LOCAL_RESERVE_SALT = bytes32(uint256(2));
    bytes32 public constant LOCAL_RESERVE_PROXY_SALT = bytes32(uint256(2));
    bytes32 public constant LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT = bytes32(uint256(1));

    // Deployed addresses
    address public factoryAddress;
    address public remoteDomainDepositorImplAddress;
    address public placeholderAddress;
    address public xReserveImplAddress;
    address public xReserveProxyAddress;

    function setUp() public {
        // Create script instances
        deployScript = new DeployXReserve();
        bytecodeValidationScript = new DeployedContractBytecodeValidation();
        stateValidationScript = new DeployedContractStateValidation();

        // Deploy the real CREATE2 factory for testing
        factoryAddress = _deployCreate2Factory();

        // Deploy mock ERC20 token for testing
        testSupportedToken = address(new ERC20Mock());

        // Set up test environment variables
        _setUpEnvironmentVariables();

        // Deploy the xReserve system for all tests to use
        (remoteDomainDepositorImplAddress, placeholderAddress, xReserveImplAddress, xReserveProxyAddress) =
            deployScript.run();

        // Expose deployed addresses to scripts that read from env
        vm.setEnv("X_RESERVE_PROXY_ADDRESS", vm.toString(xReserveProxyAddress));
        vm.setEnv("X_RESERVE_IMPL_ADDRESS", vm.toString(xReserveImplAddress));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS", vm.toString(remoteDomainDepositorImplAddress));
    }

    function test_deployxReserveSystem_success() public view {
        // Verify all addresses are non-zero (deployment happened in setUp)
        assertTrue(remoteDomainDepositorImplAddress != address(0), "RemoteDomainDepositor impl should be deployed");
        assertTrue(placeholderAddress != address(0), "Placeholder should be deployed");
        assertTrue(xReserveImplAddress != address(0), "xReserve impl should be deployed");
        assertTrue(xReserveProxyAddress != address(0), "xReserve proxy should be deployed");
    }

    // =========================
    // Bytecode validation tests
    // =========================

    function test_validateRemoteDomainDepositor_success() public view {
        // Test constructor validation (CREATE2 recomputation)
        bool constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            factoryAddress,
            LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT,
            remoteDomainDepositorImplAddress,
            "RemoteDomainDepositor",
            bytes("") // No constructor args
        );
        assertTrue(constructorValid, "RemoteDomainDepositor constructor validation should pass");

        // Test runtime validation
        bool runtimeValid =
            bytecodeValidationScript.verifyRuntimeBytecode(remoteDomainDepositorImplAddress, "RemoteDomainDepositor");
        assertTrue(runtimeValid, "RemoteDomainDepositor runtime validation should pass");
    }

    function test_validatePlaceholder_success() public view {
        // Test runtime validation (no constructor validation for placeholder)
        bool runtimeValid = bytecodeValidationScript.verifyRuntimeBytecode(placeholderAddress, "UpgradeablePlaceholder");
        assertTrue(runtimeValid, "UpgradeablePlaceholder runtime validation should pass");
    }

    function test_validatexReserveImplementation_success() public view {
        // Prepare constructor args
        bytes memory xReserveConstructorArgs =
            abi.encode(TEST_GATEWAY_MINTER, TEST_GATEWAY_WALLET, TEST_TOKEN_MESSENGER, TEST_TOKEN_MESSENGER_V2);

        // Test constructor validation (CREATE2 recomputation)
        bool constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            factoryAddress, LOCAL_RESERVE_SALT, xReserveImplAddress, "xReserve", xReserveConstructorArgs
        );
        assertTrue(constructorValid, "xReserve constructor validation should pass");

        // Test runtime validation
        bool runtimeValid = bytecodeValidationScript.verifyRuntimeBytecode(xReserveImplAddress, "xReserve");
        assertTrue(runtimeValid, "xReserve runtime validation should pass");
    }

    function test_validatexReserveProxy_success() public view {
        // Prepare proxy constructor args
        bytes memory placeholderInitData = abi.encodeWithSignature(
            "initialize(address)",
            factoryAddress // Temporary owner
        );
        bytes memory proxyConstructorArgs = abi.encode(placeholderAddress, placeholderInitData);

        // Test proxy validation
        (bool bytecodeValid, bool implValid) = bytecodeValidationScript.verifyProxy(
            factoryAddress,
            LOCAL_RESERVE_PROXY_SALT,
            xReserveProxyAddress,
            xReserveImplAddress, // Expected implementation
            proxyConstructorArgs
        );

        assertTrue(bytecodeValid, "Proxy bytecode validation should pass");
        assertTrue(implValid, "Proxy implementation address validation should pass");
    }

    function test_validateFullSystem_success() public view {
        // This will test all contracts together
        bytecodeValidationScript.verifyXReserveContracts(
            factoryAddress,
            LOCAL_RESERVE_SALT,
            LOCAL_RESERVE_PROXY_SALT,
            LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT,
            xReserveProxyAddress,
            xReserveImplAddress,
            remoteDomainDepositorImplAddress,
            placeholderAddress
        );
    }

    function test_validateWithWrongConstructorArgs_fails() public view {
        // Use wrong constructor arguments
        bytes memory wrongConstructorArgs = abi.encode(
            address(0xDEADBEEF), // Wrong gateway minter
            TEST_GATEWAY_WALLET,
            TEST_TOKEN_MESSENGER,
            TEST_TOKEN_MESSENGER_V2
        );

        // This should fail constructor validation
        bool constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            factoryAddress, LOCAL_RESERVE_SALT, xReserveImplAddress, "xReserve", wrongConstructorArgs
        );

        assertFalse(constructorValid, "Constructor validation should fail with wrong arguments");
    }

    function test_validateWithWrongSalt_fails() public view {
        // Use correct constructor args but wrong salt
        bytes memory correctConstructorArgs =
            abi.encode(TEST_GATEWAY_MINTER, TEST_GATEWAY_WALLET, TEST_TOKEN_MESSENGER, TEST_TOKEN_MESSENGER_V2);

        // This should fail constructor validation due to wrong salt
        bool constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            factoryAddress,
            bytes32(uint256(999)), // Wrong salt
            xReserveImplAddress,
            "xReserve",
            correctConstructorArgs
        );

        assertFalse(constructorValid, "Constructor validation should fail with wrong salt");
    }

    function test_validateWithWrongFactoryAddress_fails() public view {
        // Use correct args and salt but wrong factory address
        bytes memory correctConstructorArgs =
            abi.encode(TEST_GATEWAY_MINTER, TEST_GATEWAY_WALLET, TEST_TOKEN_MESSENGER, TEST_TOKEN_MESSENGER_V2);

        // This should fail constructor validation due to wrong factory
        bool constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            address(0xDEADBEEF), // Wrong factory address
            LOCAL_RESERVE_SALT,
            xReserveImplAddress,
            "xReserve",
            correctConstructorArgs
        );

        assertFalse(constructorValid, "Constructor validation should fail with wrong factory address");
    }

    function test_validateWithWrongProxyImplementation_fails() public view {
        // Prepare correct proxy constructor args
        bytes memory placeholderInitData = abi.encodeWithSignature("initialize(address)", factoryAddress);
        bytes memory proxyConstructorArgs = abi.encode(placeholderAddress, placeholderInitData);

        // Test proxy validation with wrong expected implementation
        (, bool implValid) = bytecodeValidationScript.verifyProxy(
            factoryAddress,
            LOCAL_RESERVE_SALT,
            xReserveProxyAddress,
            address(0xDEADBEEF), // Wrong expected implementation
            proxyConstructorArgs
        );

        // Implementation should be invalid
        assertFalse(implValid, "Proxy implementation validation should fail with wrong expected implementation");
    }

    function test_validateWithWrongSystemParameters_fails() public {
        // This should fail because we're using wrong salts
        vm.expectRevert("xReserve implementation constructor bytecode verification failed");
        bytecodeValidationScript.verifyXReserveContracts(
            factoryAddress,
            bytes32(uint256(999)), // Wrong xReserve salt
            LOCAL_RESERVE_SALT,
            LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT,
            xReserveProxyAddress,
            xReserveImplAddress,
            remoteDomainDepositorImplAddress,
            placeholderAddress
        );
    }

    function test_validateWithNonExistentContract_fails() public view {
        // Test with address(0) - should fail
        bool runtimeValid = bytecodeValidationScript.verifyRuntimeBytecode(address(0), "xReserve");

        assertFalse(runtimeValid, "Runtime validation should fail with address(0)");

        // Test with a random address that has no code
        address randomAddress = address(0x1234567890123456789012345678901234567890);
        runtimeValid = bytecodeValidationScript.verifyRuntimeBytecode(randomAddress, "xReserve");

        assertFalse(runtimeValid, "Runtime validation should fail with random address");
    }

    function test_validateWithMalformedConstructorArgs_fails() public view {
        // Test with too few constructor arguments
        bytes memory tooFewArgs = abi.encode(TEST_GATEWAY_MINTER, TEST_GATEWAY_WALLET);
        // Missing tokenMessenger and tokenMessengerV2

        bool constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            factoryAddress, LOCAL_RESERVE_SALT, xReserveImplAddress, "xReserve", tooFewArgs
        );

        assertFalse(constructorValid, "Constructor validation should fail with too few arguments");

        // Test with too many constructor arguments
        bytes memory tooManyArgs = abi.encode(
            TEST_GATEWAY_MINTER,
            TEST_GATEWAY_WALLET,
            TEST_TOKEN_MESSENGER,
            TEST_TOKEN_MESSENGER_V2,
            address(0xDEADBEEF) // Extra argument
        );

        constructorValid = bytecodeValidationScript.verifyConstructorBytecode(
            factoryAddress, LOCAL_RESERVE_SALT, xReserveImplAddress, "xReserve", tooManyArgs
        );

        assertFalse(constructorValid, "Constructor validation should fail with too many arguments");
    }

    // =========================
    // State validation tests
    // =========================

    function test_stateValidation_run_usesEnv_success() public {
        // run() reads deployed addresses and expected state from env; env is set in setUp
        stateValidationScript.run();
    }

    function test_verifyContractStateValue_wrongExpectedValue_fails() public {
        // Test verifyContractStateValue with wrong expected value
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyContractStateValue(
            xReserveProxyAddress,
            "owner()",
            "",
            abi.encode(address(0x9999999999999999999999999999999999999999)) // Wrong expected owner
        );
    }

    function test_verifyContractStateValue_wrongFunctionSignature_fails() public {
        // Test verifyContractStateValue with non-existent function
        vm.expectRevert(bytes("Function call failed: nonExistentFunction()"));
        stateValidationScript.verifyContractStateValue(
            xReserveProxyAddress,
            "nonExistentFunction()",
            "",
            abi.encode(address(0x9999999999999999999999999999999999999999))
        );
    }

    function test_verifyContractStateValue_wrongFunctionParameters_fails() public {
        // Test verifyContractStateValue with wrong function parameters
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyContractStateValue(
            xReserveProxyAddress,
            "isTokenSupported(address)",
            abi.encode(uint256(123)), // Wrong parameter type (uint256 instead of address)
            abi.encode(true)
        );
    }

    function test_verifyContractStateValue_zeroAddress_fails() public {
        // Test verifyContractStateValue with zero address
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyContractStateValue(address(0), "owner()", "", abi.encode(TEST_OWNER));
    }

    function test_verifyContractStateValue_nonExistentContract_fails() public {
        // Test verifyContractStateValue with non-existent contract
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyContractStateValue(
            address(0x9999999999999999999999999999999999999999), "owner()", "", abi.encode(TEST_OWNER)
        );
    }

    function test_verifyProxyImplementation_wrongExpectedImplementation_fails() public {
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidationScript.verifyProxyImplementation(xReserveProxyAddress, address(0xDEADBEEF));
    }

    function test_verifyXReserveProxyState_wrongProxyAddress_fails() public {
        // Test with wrong proxy address
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyXReserveProxyState(address(0x9999999999999999999999999999999999999999));
    }

    function test_verifyXReserveProxyState_zeroProxyAddress_fails() public {
        // Test with zero proxy address
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyXReserveProxyState(address(0));
    }

    function test_verifyRemoteDomainDepositorState_withNoCode_fails() public {
        // Test RemoteDomainDepositor implementation with no code
        vm.expectRevert(bytes("RemoteDomainDepositor implementation has no code"));
        stateValidationScript.verifyRemoteDomainDepositorState(address(0x9999999999999999999999999999999999999999));
    }

    function test_verifyRemoteDomainDepositorState_zeroAddress_fails() public {
        // Test RemoteDomainDepositor implementation with zero address
        vm.expectRevert(bytes("RemoteDomainDepositor implementation has no code"));
        stateValidationScript.verifyRemoteDomainDepositorState(address(0));
    }

    function test_verifyProxyImplementation_zeroExpectedImplementation_fails() public {
        // Test proxy implementation validation with zero expected implementation
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidationScript.verifyProxyImplementation(xReserveProxyAddress, address(0));
    }

    function test_verifyProxyImplementation_wrongProxyAddress_fails() public {
        // Test proxy implementation validation with wrong proxy address
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidationScript.verifyProxyImplementation(
            address(0x9999999999999999999999999999999999999999), xReserveImplAddress
        );
    }

    function test_verifyXReserveSystemState_wrongXReserveImpl_fails() public {
        // Test verifyXReserveSystemState with wrong xReserve implementation
        vm.expectRevert();
        stateValidationScript.verifyXReserveSystemState(
            xReserveProxyAddress,
            address(0xDEADBEEF), // Wrong implementation
            remoteDomainDepositorImplAddress
        );
    }

    function test_verifyXReserveSystemState_wrongXReserveProxy_fails() public {
        // Test verifyXReserveSystemState with wrong xReserve proxy address
        vm.expectRevert(bytes("Value validation failed"));
        stateValidationScript.verifyXReserveSystemState(
            address(0x9999999999999999999999999999999999999999), // Wrong proxy address
            xReserveImplAddress,
            remoteDomainDepositorImplAddress
        );
    }

    function test_verifyXReserveSystemState_wrongRemoteDomainDepositorImpl_fails() public {
        // Test verifyXReserveSystemState with wrong remote domain depositor implementation
        vm.expectRevert();
        stateValidationScript.verifyXReserveSystemState(
            xReserveProxyAddress,
            xReserveImplAddress,
            address(0x9999999999999999999999999999999999999999) // Wrong remote domain depositor impl
        );
    }

    // =========================
    // Helper functions
    // =========================

    function _setUpEnvironmentVariables() internal {
        // Set environment to LOCAL
        vm.setEnv("ENV", "LOCAL");

        // Set all required environment variables for deployment
        vm.setEnv("X_RESERVE_GATEWAY_MINTER_ADDRESS", vm.toString(TEST_GATEWAY_MINTER));
        vm.setEnv("X_RESERVE_GATEWAY_WALLET_ADDRESS", vm.toString(TEST_GATEWAY_WALLET));
        vm.setEnv("X_RESERVE_TOKEN_MESSENGER_ADDRESS", vm.toString(TEST_TOKEN_MESSENGER));
        vm.setEnv("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS", vm.toString(TEST_TOKEN_MESSENGER_V2));
        vm.setEnv("X_RESERVE_PAUSER_ADDRESS", vm.toString(TEST_PAUSER));
        vm.setEnv("X_RESERVE_BLOCKLISTER_ADDRESS", vm.toString(TEST_BLOCKLISTER));
        vm.setEnv("X_RESERVE_REGISTRATION_MANAGER_ADDRESS", vm.toString(TEST_REGISTRATION_MANAGER));
        vm.setEnv("X_RESERVE_OWNER_ADDRESS", vm.toString(TEST_OWNER));
        vm.setEnv("X_RESERVE_SUPPORTED_TOKEN_1", vm.toString(testSupportedToken));
        vm.setEnv("X_RESERVE_DOMAIN", vm.toString(TEST_DOMAIN));

        // Set LOCAL environment specific variables
        vm.setEnv("LOCAL_CREATE2_FACTORY_ADDRESS", vm.toString(factoryAddress));
        vm.setEnv("LOCAL_DEPLOYER_ADDRESS", vm.toString(address(this)));
    }

    function _deployCreate2Factory() internal returns (address) {
        // Deploy the real CREATE2 factory for testing
        Create2Factory factory = new Create2Factory(address(this));
        return address(factory);
    }
}
