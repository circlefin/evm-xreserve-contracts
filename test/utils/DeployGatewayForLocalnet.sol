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
import {UpgradeablePlaceholder} from "@gateway/src/UpgradeablePlaceholder.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DeployGateway} from "./DeployGateway.sol";

/**
 * @title DeployGatewayForLocalnet
 * @notice Lightweight deployment script that leverages the existing DeployGateway utility
 * @dev Adds broadcasting and environment variable handling to the existing test utility
 */
contract DeployGatewayForLocalnet is Script, DeployGateway {
    function run() external returns (address gatewayWallet, address gatewayMinter) {
        uint256 deployerPrivateKey = vm.envUint("LOCAL_DEPLOYER_KEY");
        address deployer = vm.envAddress("LOCAL_DEPLOYER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Use the existing utility, but override to remove vm.prank since broadcaster is already the owner
        (GatewayWallet wallet, GatewayMinter minter) = deployGatewayNoPrank(deployer, 1);

        vm.stopBroadcast();

        // Return the deployed addresses
        gatewayWallet = address(wallet);
        gatewayMinter = address(minter);

        console.log("GatewayWallet deployed at:", gatewayWallet);
        console.log("GatewayMinter deployed at:", gatewayMinter);

        return (gatewayWallet, gatewayMinter);
    }

    /// @notice Deploy gateway without vm.prank for use in broadcasting scripts
    function deployGatewayNoPrank(address owner, uint32 domain) public returns (GatewayWallet, GatewayMinter) {
        // Deploy both placeholders
        UpgradeablePlaceholder walletProxy = deployPlaceholder(owner);
        UpgradeablePlaceholder minterProxy = deployPlaceholder(owner);

        // Deploy both implementation contracts
        GatewayWallet walletImpl = new GatewayWallet();
        GatewayMinter minterImpl = new GatewayMinter();

        // Upgrade both placeholders (no vm.prank needed - broadcaster is already the owner)
        walletProxy.upgradeToAndCall(address(walletImpl), _walletInitializationCall(owner, domain));
        minterProxy.upgradeToAndCall(address(minterImpl), _minterInitializationCall(owner, domain));

        // Return the upgraded proxies
        GatewayWallet wallet = GatewayWallet(address(walletProxy));
        GatewayMinter minter = GatewayMinter(address(minterProxy));
        return (wallet, minter);
    }
}
