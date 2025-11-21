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
import {xReserve} from "src/xReserve.sol";

/// @title OnboardRemoteDomains
/// @notice Script to register remote domains on an existing xReserve proxy
/// @dev Broadcasts from the `registrationManager` address
contract OnboardRemoteDomains is Script {
    uint256 private constant NUM_MAX_ATTESTERS = 5;
    uint256 private constant NUM_MAX_DOMAINS = 5;

    function _registerRemoteToken(
        address xReserveProxyAddress,
        uint32 remoteDomain,
        string memory domainPrefix
    ) private {
        string memory localKey = string.concat(domainPrefix, "_LOCAL_TOKEN");
        string memory remoteKey = string.concat(domainPrefix, "_REMOTE_TOKEN");

        address localToken = vm.envAddress(localKey);
        bytes32 remoteToken = vm.envBytes32(remoteKey);

        console.log("  Registering remote token mapping:");
        console.log("    localToken:", localToken);
        console.log("    remoteDomain:", remoteDomain);
        console.logBytes32(remoteToken);

        xReserve(xReserveProxyAddress).registerRemoteToken(localToken, remoteDomain, remoteToken);
        console.log("    Remote token mapping registered.");
    }

    /// @dev Registers a single domain at the provided index using env vars.
    /// @return didRegister Returns false when the domain is not configured
    function _registerRemoteDomainAndToken(uint256 i, address xReserveProxyAddress) private returns (bool didRegister) {
        // Read required per-domain variables. Return false when domain is missing.
        uint32 remoteDomain;
        {
            string memory key = string.concat("X_RESERVE_REMOTE_DOMAIN_", vm.toString(i));
            try vm.envUint(key) returns (uint256 v) {
                remoteDomain = uint32(v);
            } catch {
                return false;
            }
        }

        string memory prefix = string.concat("X_RESERVE_REMOTE_DOMAIN_", vm.toString(i));

        address domainManager = vm.envAddress(string.concat(prefix, "_MANAGER_ADDRESS"));
        address domainPauser = vm.envAddress(string.concat(prefix, "_PAUSER_ADDRESS"));
        uint256 signatureThreshold = vm.envUint(string.concat(prefix, "_SIGNATURE_THRESHOLD"));
        uint256 persistentSignatureBufferDelayBlocks = vm.envUint(
            string.concat(prefix, "_PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS")
        );

        // Hook executor is optional, defaults to zero address
        address remoteDomainHookExecutor;
        try vm.envAddress(string.concat(prefix, "_HOOK_EXECUTOR_ADDRESS")) returns (address executor) {
            remoteDomainHookExecutor = executor;
        } catch {
            remoteDomainHookExecutor = address(0);
        }

        // Load attesters: X_RESERVE_REMOTE_DOMAIN_{i}_ATTESTER_1 ... N
        address[] memory attestersBuffer = new address[](NUM_MAX_ATTESTERS);
        uint256 attestersCount = 0;
        for (uint256 j = 1; j <= NUM_MAX_ATTESTERS; j++) {
            string memory key = string.concat(prefix, "_ATTESTER_", vm.toString(j));
            try vm.envAddress(key) returns (address attester) {
                attestersBuffer[attestersCount] = attester;
                attestersCount++;
            } catch {
                break;
            }
        }

        address[] memory attesters = new address[](attestersCount);
        for (uint256 j = 0; j < attestersCount; j++) {
            attesters[j] = attestersBuffer[j];
        }

        // Basic sanity checks before broadcasting for this domain
        require(signatureThreshold > 0, "Signature threshold must be > 0");
        require(attestersCount >= signatureThreshold, "Threshold exceeds number of attesters");

        console.log("Registering remote domain index:", i);
        console.log("  remoteDomain:", remoteDomain);
        console.log("  domainManager:", domainManager);
        console.log("  domainPauser:", domainPauser);
        console.log("  attestersCount:", attestersCount);
        console.log("  signatureThreshold:", signatureThreshold);
        console.log("  persistentSignatureBufferDelayBlocks:", persistentSignatureBufferDelayBlocks);
        console.log("  hookExecutor:", remoteDomainHookExecutor);

        address remoteDomainDepositor = xReserve(xReserveProxyAddress).registerRemoteDomain(
            remoteDomain,
            domainManager,
            domainPauser,
            attesters,
            signatureThreshold,
            persistentSignatureBufferDelayBlocks,
            remoteDomainHookExecutor
        );

        console.log("  RemoteDomain registered. Depositor proxy:", remoteDomainDepositor);

        // Register remote token mapping for this domain (required)
        _registerRemoteToken(xReserveProxyAddress, remoteDomain, prefix);
        return true;
    }

    function run() public {
        // Target xReserve proxy
        address xReserveProxyAddress = vm.envAddress("X_RESERVE_PROXY_ADDRESS");

        // Must broadcast from the registration manager
        address registrationManager = vm.envAddress("X_RESERVE_REGISTRATION_MANAGER_ADDRESS");

        console.log("xReserve proxy:", xReserveProxyAddress);
        console.log("broadcasting from registrationManager:", registrationManager);

        // This script emits two transactions per registered remote domain: registerRemoteDomain and registerRemoteToken
        vm.startBroadcast(registrationManager);

		uint256 numRegistered = 0;
		// Iterate X_RESERVE_REMOTE_DOMAIN_1 .. _N until a gap/missing var is encountered
		for (uint256 i = 1; i <= NUM_MAX_DOMAINS; i++) {
			bool didRegister = _registerRemoteDomainAndToken(i, xReserveProxyAddress);
			if (!didRegister) {
				break;
			}
			numRegistered++;
		}

		require(numRegistered > 0, "No remote domains registered");
		console.log("Total remote domains registered:", numRegistered);

		vm.stopBroadcast();
    }
}
