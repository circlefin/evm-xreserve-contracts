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
import {console} from "forge-std/console.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title PredictRemoteDomainDepositorAddress
/// @notice Script to predict the address of a RemoteDomainDepositor proxy for a new remote domain
/// @dev Uses the same CREATE2 logic as RemoteDomainRegistration to compute addresses deterministically
contract PredictRemoteDomainDepositorAddress is Script {
    /// @notice Predicts the RemoteDomainDepositor proxy address for a given remote domain
    /// @dev This uses the exact same logic as RemoteDomainRegistration.registerRemoteDomain()
    /// @param xReserveAddress The address of the xReserve contract (the deployer)
    /// @param remoteDomainDepositorImplementation The address of the RemoteDomainDepositor implementation
    /// @param remoteDomain The domain identifier for which to predict the address
    /// @return predictedAddress The predicted address of the RemoteDomainDepositor proxy
    function predictAddress(
        address xReserveAddress,
        address remoteDomainDepositorImplementation,
        uint32 remoteDomain
    ) public pure returns (address predictedAddress) {
        // Generate deterministic salt based on remote domain (same as in RemoteDomainRegistration)
        bytes32 salt = keccak256(abi.encode(remoteDomain));

        // Construct the creation code for ERC1967Proxy with RemoteDomainDepositor implementation
        // The proxy is initialized with empty initialization data (bytes(""))
        bytes memory creationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(remoteDomainDepositorImplementation, bytes(""))
        );

        // Compute the bytecode hash
        bytes32 bytecodeHash = keccak256(creationCode);

        // Compute the CREATE2 address
        predictedAddress = Create2.computeAddress(salt, bytecodeHash, xReserveAddress);
    }

    /// @notice Main entry point for the script
    /// @dev Reads configuration from environment variables and predicts the address
    function run() external view {
        // Read required parameters from environment variables
        address xReserveAddress = vm.envAddress("X_RESERVE_ADDRESS");
        address remoteDomainDepositorImplementation = vm.envAddress("REMOTE_DOMAIN_DEPOSITOR_IMPLEMENTATION");
        uint32 remoteDomain = uint32(vm.envUint("REMOTE_DOMAIN"));

        require(xReserveAddress != address(0), "xReserveAddress must not be zero");
        require(remoteDomainDepositorImplementation != address(0), "remoteDomainDepositorImplementation must not be zero");

        // Predict the address
        address predicted = predictAddress(
            xReserveAddress,
            remoteDomainDepositorImplementation,
            remoteDomain
        );

        // Log the results
        console.log("========================================");
        console.log("RemoteDomainDepositor Address Prediction");
        console.log("========================================");
        console.log("");
        console.log("Inputs:");
        console.log("  xReserve Address:                  ", xReserveAddress);
        console.log("  RemoteDomainDepositor Implementation:", remoteDomainDepositorImplementation);
        console.log("  Remote Domain:                     ", remoteDomain);
        console.log("");
        console.log("Computed Values:");
        console.log("  Salt (keccak256(abi.encode(domain))):");
        console.logBytes32(keccak256(abi.encode(remoteDomain)));
        console.log("");
        console.log("Result:");
        console.log("  Predicted RemoteDomainDepositor Address:", predicted);
        console.log("========================================");
    }
}
