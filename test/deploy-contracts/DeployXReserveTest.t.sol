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

import {Create2Factory} from "@gateway/script/Create2Factory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployXReserve} from "deploy-contracts/001_DeployXReserve.sol";
import {Test} from "forge-std/Test.sol";
import {RemoteDomainDepositor} from "src/RemoteDomainDepositor.sol";

contract DeployXReserveTest is Test {
    Create2Factory private factory;
    address private deployerAddress;

    function setUp() public {
        // Setup test environment variables
        vm.setEnv("ENV", "LOCAL");

        // Create a factory for deterministic deployments
        deployerAddress = makeAddr("deployer");
        factory = new Create2Factory(deployerAddress);

        // Set required environment variables for LOCAL environment
        vm.setEnv("LOCAL_CREATE2_FACTORY_ADDRESS", vm.toString(address(factory)));
        vm.setEnv("LOCAL_DEPLOYER_ADDRESS", vm.toString(deployerAddress));

        // Set xReserve-specific environment variables (owner must be EOA)
        // Use vm.addr to create a proper EOA from a private key
        uint256 xReserveOwnerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address xReserveOwner = vm.addr(xReserveOwnerPrivateKey);
        vm.setEnv("X_RESERVE_OWNER_ADDRESS", vm.toString(xReserveOwner));
        vm.setEnv("X_RESERVE_PAUSER_ADDRESS", vm.toString(makeAddr("xReservePauser")));
        vm.setEnv("X_RESERVE_BLOCKLISTER_ADDRESS", vm.toString(makeAddr("xReserveBlocklister")));
        vm.setEnv("X_RESERVE_REGISTRATION_MANAGER_ADDRESS", vm.toString(makeAddr("registrationManager")));

        // Set constructor dependencies (immutable addresses)
        vm.setEnv("X_RESERVE_GATEWAY_MINTER_ADDRESS", vm.toString(makeAddr("gatewayMinter")));
        vm.setEnv("X_RESERVE_GATEWAY_WALLET_ADDRESS", vm.toString(makeAddr("gatewayWallet")));
        vm.setEnv("X_RESERVE_TOKEN_MESSENGER_ADDRESS", vm.toString(makeAddr("tokenMessenger")));
        vm.setEnv("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS", vm.toString(makeAddr("tokenMessengerV2")));

        // Deploy actual contracts that need to have code
        RemoteDomainDepositor remoteDomainDepositorImpl = new RemoteDomainDepositor();
        ERC20Mock token1 = new ERC20Mock();

        // Set configuration parameters
        vm.setEnv("X_RESERVE_DOMAIN", "1");
        vm.setEnv("X_RESERVE_SUPPORTED_TOKEN_1", vm.toString(address(token1)));
        vm.setEnv("X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS", vm.toString(address(remoteDomainDepositorImpl)));
    }

    /// @notice Calculate CREATE2 address for deterministic deployment
    /// @dev Implements the CREATE2 address calculation as specified in EIP-1014
    /// @dev Reference: https://eips.ethereum.org/EIPS/eip-1014
    /// @dev Formula: keccak256(0xff + factory_address + salt + keccak256(init_code))[12:]
    /// @param factoryAddress The address of the CREATE2 factory contract
    /// @param salt The salt value used for deterministic deployment
    /// @param bytecode The complete bytecode (init code + constructor arguments)
    /// @return The deterministic address where the contract will be deployed
    function calculateCreate2Address(address factoryAddress, bytes32 salt, bytes memory bytecode)
        internal
        pure
        returns (address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), // 0xff prefix as specified in EIP-1014
                factoryAddress, // Address of the CREATE2 factory
                salt, // Salt for deterministic deployment
                keccak256(bytecode) // Hash of the init code
            )
        );
        return address(uint160(uint256(hash)));
    }

    /// @notice Prepare constructor arguments for RemoteDomainDepositor (empty for this contract)
    function prepareRemoteDomainDepositorConstructorArgs() internal pure returns (bytes memory) {
        return hex"";
    }

    /// @notice Prepare constructor arguments for xReserve
    function prepareConstructorArgs() internal view returns (bytes memory) {
        address gatewayMinterAddress = vm.envAddress("X_RESERVE_GATEWAY_MINTER_ADDRESS");
        address gatewayWalletAddress = vm.envAddress("X_RESERVE_GATEWAY_WALLET_ADDRESS");
        address tokenMessengerAddress = vm.envAddress("X_RESERVE_TOKEN_MESSENGER_ADDRESS");
        address tokenMessengerV2Address = vm.envAddress("X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS");

        // Encode constructor arguments
        return abi.encode(gatewayMinterAddress, gatewayWalletAddress, tokenMessengerAddress, tokenMessengerV2Address);
    }

    /// @notice Test that contracts deploy to deterministic addresses using CREATE2 (EIP-1014)
    /// @dev This test verifies that our deployment script produces predictable addresses,
    ///      which is crucial for:
    ///      - Cross-chain deployments (same addresses on different chains)
    ///      - Upgradeable proxy patterns (predictable proxy addresses)
    ///      - Integration testing (reliable address expectations)
    ///      - Security auditing (known deployment addresses)
    function test_deployXReserve_deterministicAddresses() public {
        // Execute the deployment script and verify deterministic addresses
        DeployXReserve deployer = new DeployXReserve();
        (
            address remoteDomainDepositorImplAddress,
            address placeholderAddress,
            address implAddress,
            address proxyAddress
        ) = deployer.run();

        // Calculate expected addresses using CREATE2 formula (EIP-1014)
        // CREATE2 enables deterministic contract deployment - the same bytecode + salt + factory
        // will always result in the same address, regardless of when it's deployed
        // Salt values from Constants.sol: LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT = 1, LOCAL_XRESERVE_SALT = 2, LOCAL_XRESERVE_PROXY_SALT = 2
        bytes32 remoteDomainDepositorSalt = bytes32(uint256(1));
        bytes32 xReserveSalt = bytes32(uint256(2));
        bytes32 xReserveProxySalt = bytes32(uint256(2));

        // Get the actual bytecode for each contract from compiled artifacts
        string memory root = vm.projectRoot();

        // Read bytecode from compiled artifacts
        string memory remoteDomainDepositorPath =
            string.concat(root, "/deploy-contracts/compiled-contract-artifacts/RemoteDomainDepositor.json");
        string memory remoteDomainDepositorJson = vm.readFile(remoteDomainDepositorPath);
        bytes memory remoteDomainDepositorInitCode =
            abi.decode(vm.parseJson(remoteDomainDepositorJson, ".bytecode.object"), (bytes));

        string memory placeholderPath =
            string.concat(root, "/deploy-contracts/compiled-contract-artifacts/UpgradeablePlaceholder.json");
        string memory placeholderJson = vm.readFile(placeholderPath);
        bytes memory placeholderInitCode = abi.decode(vm.parseJson(placeholderJson, ".bytecode.object"), (bytes));

        string memory xReservePath = string.concat(root, "/deploy-contracts/compiled-contract-artifacts/xReserve.json");
        string memory xReserveJson = vm.readFile(xReservePath);
        bytes memory xReserveInitCode = abi.decode(vm.parseJson(xReserveJson, ".bytecode.object"), (bytes));

        string memory proxyPath = string.concat(root, "/deploy-contracts/compiled-contract-artifacts/ERC1967Proxy.json");
        string memory proxyJson = vm.readFile(proxyPath);
        bytes memory proxyInitCode = abi.decode(vm.parseJson(proxyJson, ".bytecode.object"), (bytes));

        // Prepare constructor arguments exactly as the deployment script does
        bytes memory remoteDomainDepositorConstructorArgs = prepareRemoteDomainDepositorConstructorArgs();
        bytes memory placeholderConstructorArgs = hex""; // Empty constructor args for placeholder
        bytes memory xReserveConstructorArgs = prepareConstructorArgs();

        // For proxy, we need to calculate the placeholder address first, then use it in proxy constructor
        bytes32 placeholderSalt = keccak256(abi.encodePacked(xReserveSalt, "placeholder"));
        bytes memory placeholderBytecode = abi.encodePacked(placeholderInitCode, placeholderConstructorArgs);
        address expectedPlaceholder = calculateCreate2Address(address(factory), placeholderSalt, placeholderBytecode);

        // Now calculate proxy constructor args with the placeholder address
        bytes memory placeholderInitData = abi.encodeWithSignature("initialize(address)", address(factory));
        bytes memory proxyConstructorArgs = abi.encode(expectedPlaceholder, placeholderInitData);

        // Construct complete bytecode with constructor arguments
        bytes memory remoteDomainDepositorBytecode =
            abi.encodePacked(remoteDomainDepositorInitCode, remoteDomainDepositorConstructorArgs);
        bytes memory xReserveBytecode = abi.encodePacked(xReserveInitCode, xReserveConstructorArgs);
        bytes memory proxyBytecode = abi.encodePacked(proxyInitCode, proxyConstructorArgs);

        // Calculate expected addresses
        address expectedRemoteDomainDepositor =
            calculateCreate2Address(address(factory), remoteDomainDepositorSalt, remoteDomainDepositorBytecode);
        address expectedXReserve = calculateCreate2Address(address(factory), xReserveSalt, xReserveBytecode);
        address expectedProxy = calculateCreate2Address(address(factory), xReserveProxySalt, proxyBytecode);

        // Assert the deterministic addresses match calculated values
        assertEq(
            remoteDomainDepositorImplAddress,
            expectedRemoteDomainDepositor,
            "RemoteDomainDepositor should deploy to deterministic address"
        );
        assertEq(placeholderAddress, expectedPlaceholder, "Placeholder should deploy to deterministic address");
        assertEq(implAddress, expectedXReserve, "Implementation should deploy to deterministic address");
        assertEq(proxyAddress, expectedProxy, "Proxy should deploy to deterministic address");

        // Verify contracts are deployed (have bytecode)
        assertTrue(remoteDomainDepositorImplAddress.code.length > 0, "RemoteDomainDepositor should have bytecode");
        assertTrue(placeholderAddress.code.length > 0, "Placeholder should have bytecode");
        assertTrue(implAddress.code.length > 0, "Implementation should have bytecode");
        assertTrue(proxyAddress.code.length > 0, "Proxy should have bytecode");

        // Check exact expected values to catch bytecode drift
        assertEq(
            remoteDomainDepositorImplAddress,
            0x38Bca52301441A3E162D7013e6cBA18782101c23,
            "RemoteDomainDepositor should deploy to deterministic address"
        );
        assertEq(
            placeholderAddress,
            0xFb78713930E7492a819BB79D62D4Ff7AfaD2D110,
            "Placeholder should deploy to deterministic address"
        );
        assertEq(
            implAddress,
            0x7212D3C3F5824aF25F12fd8b3941ED3Db66D280E,
            "Implementation should deploy to deterministic address"
        );
        assertEq(
            proxyAddress, 0x9e6EE0Ff5Ebe553f511FAF6CE38e839B0670AD00, "Proxy should deploy to deterministic address"
        );
    }
}
