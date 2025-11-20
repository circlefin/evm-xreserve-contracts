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

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ICreate2Factory} from "@gateway/script/interface/ICreate2Factory.sol";

/// @title BaseBytecodeDeployScript
/// @notice Base contract for deploying xReserve contracts using CREATE2 factory with deterministic addresses
/// @dev Abstract contract that provides functionality for deploying contracts with predetermined addresses
abstract contract BaseBytecodeDeployScript is Script {
    /// @notice Deploys a contract and executes multiple calls on it using CREATE2 factory
    /// @dev Reads bytecode from compiled artifacts, deploys with CREATE2, and executes initialization calls
    /// @param factory The CREATE2 factory contract address
    /// @param contractFileName Name of the contract's compiled artifact file (e.g., "Contract.json")
    /// @param salt The salt used for CREATE2 deployment to generate deterministic address
    /// @param args The constructor arguments for the contract deployment
    /// @param data Array of calldata for post-deployment initialization calls
    function deployAndMultiCall(
        address factory,
        string memory contractFileName,
        bytes32 salt,
        bytes memory args,
        bytes[] memory data
    ) internal returns (address addr) {
        // Get project root directory and construct path to compiled contract artifact
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy-contracts/compiled-contract-artifacts/", contractFileName);
        string memory json = vm.readFile(path);

        // Extract bytecode from the compiled contract artifact.
        // Foundry compiled artifact file uses JSON format.
        // The bytecode is stored in a second-level key (".bytecode.object") in the json file.
        bytes memory initCode = abi.decode(vm.parseJson(json, ".bytecode.object"), (bytes));

        // Prepare the complete bytecode (contract bytecode + constructor arguments)
        bytes memory bytecode = abi.encodePacked(initCode, args);

        // Deploy contract and execute post-deployment calls using CREATE2 factory
        addr = ICreate2Factory(factory).deployAndMultiCall(0, salt, bytecode, data);

        if (keccak256(bytes(contractFileName)) == keccak256(bytes("ERC1967Proxy.json"))) {
            console.log("initCodeHash for proxy address", addr, "below:");
            console.logBytes32(keccak256(bytecode));
        }
    }

    /// @notice Deploys a contract without any post-deployment initialization calls
    /// @dev Wrapper around deployAndMultiCall that passes an empty array for post-deployment calls
    /// @param factory The CREATE2 factory contract address
    /// @param contractFileName Name of the contract's compiled artifact file (e.g., "Contract.json")
    /// @param salt The salt used for CREATE2 deployment to generate deterministic address
    /// @param args The constructor arguments for the contract deployment
    function deploy(address factory, string memory contractFileName, bytes32 salt, bytes memory args)
        internal
        returns (address addr)
    {
        addr = deployAndMultiCall(factory, contractFileName, salt, args, new bytes[](0));
    }
}
