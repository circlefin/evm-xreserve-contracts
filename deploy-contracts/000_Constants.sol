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

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title Constants
 * @notice Library containing environment-specific constants for deployment
 * @dev Defines constants for three environments: TESTNET_STAGING, TESTNET_PROD and MAINNET_PROD
 */
library Constants {
    // Local environment constants
    bytes32 internal constant LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT = bytes32(uint256(1));
    bytes32 internal constant LOCAL_RESERVE_SALT = bytes32(uint256(2));
    bytes32 internal constant LOCAL_RESERVE_PROXY_SALT = bytes32(uint256(2));

    // Testnet staging environment constants
    bytes32 internal constant TESTNET_STAGING_REMOTE_DOMAIN_DEPOSITOR_SALT = bytes32(uint256(1));
    bytes32 internal constant TESTNET_STAGING_RESERVE_SALT = bytes32(uint256(2));
    bytes32 internal constant TESTNET_STAGING_RESERVE_PROXY_SALT =
        0x186aa1d8126915926321fb23e131dca524a0178ac6b049f1cf9abde7a81b3f82;
    address internal constant TESTNET_STAGING_CREATE2FACTORY_ADDRESS = 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2;
    address internal constant TESTNET_STAGING_DEPLOYER_ADDRESS = 0xD1e4098de8667a491Eb2Bf5acf09ED7F67260BCA;

    // Testnet prod environment constants
    bytes32 internal constant TESTNET_PROD_REMOTE_DOMAIN_DEPOSITOR_SALT = bytes32(uint256(3));
    bytes32 internal constant TESTNET_PROD_RESERVE_SALT = bytes32(uint256(4));
    bytes32 internal constant TESTNET_PROD_RESERVE_PROXY_SALT =
        0x81dca5014b714949fbdbe309b18745f06876ba9565e77be369f1f1ad0d254c98;
    address internal constant TESTNET_PROD_CREATE2FACTORY_ADDRESS = 0x643151056F7cCCD36030d6507a8C07Ed4a46E8D2;
    address internal constant TESTNET_PROD_DEPLOYER_ADDRESS = 0xD1e4098de8667a491Eb2Bf5acf09ED7F67260BCA;

    // Mainnet prod environment constants
    bytes32 internal constant MAINNET_PROD_REMOTE_DOMAIN_DEPOSITOR_SALT = bytes32(uint256(5));
    bytes32 internal constant MAINNET_PROD_RESERVE_SALT = bytes32(uint256(6));
    bytes32 internal constant MAINNET_PROD_RESERVE_PROXY_SALT =
        0xc05173deb4233ce2301dca1aaf2ef5cd7b9e581533bac9b6fd500b3bc59aa2f3;
    address internal constant MAINNET_PROD_CREATE2FACTORY_ADDRESS = 0xe7b84D8846c96Bb83155Da5537625c75e42d6E42;
    address internal constant MAINNET_PROD_DEPLOYER_ADDRESS = 0xadB384F7fa7486422051D2a896417EAAb9E5A9D1;
}

/**
 * @title EnvConfig
 * @notice Configuration struct that holds all environment-specific parameters
 * @dev Used to pass environment configuration between contracts in a structured way
 * @param remoteDomainDepositorSalt The base salt value used for RemoteDomainDepositor deployment
 * @param reserveSalt The base salt value used for xReserve non proxy contract deployment
 * @param reserveProxySalt The salt value used for xReserve proxy deployment
 * @param factoryAddress The CREATE2 factory address for deterministic deployment
 * @param deployerAddress The address that will deploy the contracts
 */
struct EnvConfig {
    bytes32 remoteDomainDepositorSalt;
    bytes32 reserveSalt;
    bytes32 reserveProxySalt;
    address factoryAddress;
    address deployerAddress;
}

/**
 * @title EnvSelector
 * @notice Helper contract to select environment configuration based on ENV variable
 * @dev Provides configuration for different deployment environments (LOCAL, TESTNET_STAGING, TESTNET_PROD, MAINNET_PROD)
 *      The environment is selected by setting the ENV environment variable before running the script
 *      Default environment is LOCAL if ENV is not specified
 */
contract EnvSelector is Script {
    /**
     * @notice Get configuration for the selected environment
     * @dev Reads ENV environment variable and returns the appropriate configuration
     * @return EnvConfig struct containing environment-specific parameters
     */
    function getEnvironmentConfig() public view returns (EnvConfig memory) {
        // Read environment from forge environment variable, default to LOCAL
        string memory env = vm.envOr("ENV", string("LOCAL"));
        console.log("Selected environment:", env);

        // Select environment configuration based on ENV value
        if (keccak256(bytes(env)) == keccak256(bytes("LOCAL"))) {
            return getLocalConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("TESTNET_STAGING"))) {
            return getTestnetStagingConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("TESTNET_PROD"))) {
            return getTestnetProdConfig();
        } else if (keccak256(bytes(env)) == keccak256(bytes("MAINNET_PROD"))) {
            return getMainnetProdConfig();
        } else {
            // Default to LOCAL if environment is unrecognized
            return getLocalConfig();
        }
    }

    /**
     * @notice Get configuration for the LOCAL environment
     * @dev Salt values for LOCAL: remoteDomainDepositor=1, reserve=2
     * @return EnvConfig with LOCAL-specific values
     */
    function getLocalConfig() public view returns (EnvConfig memory) {
        address localCreate2Factory = vm.envAddress("LOCAL_CREATE2_FACTORY_ADDRESS");
        address localDeployer = vm.envAddress("LOCAL_DEPLOYER_ADDRESS");

        return EnvConfig({
            remoteDomainDepositorSalt: Constants.LOCAL_REMOTE_DOMAIN_DEPOSITOR_SALT,
            reserveSalt: Constants.LOCAL_RESERVE_SALT,
            reserveProxySalt: Constants.LOCAL_RESERVE_PROXY_SALT,
            factoryAddress: localCreate2Factory,
            deployerAddress: localDeployer
        });
    }

    /**
     * @notice Get configuration for the TESTNET_STAGING environment
     * @dev Salt values for TESTNET_STAGING: remoteDomainDepositor=1, reserve=2
     * @return EnvConfig with TESTNET_STAGING-specific values
     */
    function getTestnetStagingConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            remoteDomainDepositorSalt: Constants.TESTNET_STAGING_REMOTE_DOMAIN_DEPOSITOR_SALT,
            reserveSalt: Constants.TESTNET_STAGING_RESERVE_SALT,
            reserveProxySalt: Constants.TESTNET_STAGING_RESERVE_PROXY_SALT,
            factoryAddress: Constants.TESTNET_STAGING_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.TESTNET_STAGING_DEPLOYER_ADDRESS
        });
    }

    /**
     * @notice Get configuration for the TESTNET_PROD environment
     * @dev Salt values for TESTNET_PROD: remoteDomainDepositor=3, reserve=4
     * @return EnvConfig with TESTNET_PROD-specific values
     */
    function getTestnetProdConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            remoteDomainDepositorSalt: Constants.TESTNET_PROD_REMOTE_DOMAIN_DEPOSITOR_SALT,
            reserveSalt: Constants.TESTNET_PROD_RESERVE_SALT,
            reserveProxySalt: Constants.TESTNET_PROD_RESERVE_PROXY_SALT,
            factoryAddress: Constants.TESTNET_PROD_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.TESTNET_PROD_DEPLOYER_ADDRESS
        });
    }

    /**
     * @notice Get configuration for the MAINNET_PROD environment
     * @dev Salt values for MAINNET_PROD: remoteDomainDepositor=5, reserve=6
     * @return EnvConfig with MAINNET_PROD-specific values
     */
    function getMainnetProdConfig() public pure returns (EnvConfig memory) {
        return EnvConfig({
            remoteDomainDepositorSalt: Constants.MAINNET_PROD_REMOTE_DOMAIN_DEPOSITOR_SALT,
            reserveSalt: Constants.MAINNET_PROD_RESERVE_SALT,
            reserveProxySalt: Constants.MAINNET_PROD_RESERVE_PROXY_SALT,
            factoryAddress: Constants.MAINNET_PROD_CREATE2FACTORY_ADDRESS,
            deployerAddress: Constants.MAINNET_PROD_DEPLOYER_ADDRESS
        });
    }
}
