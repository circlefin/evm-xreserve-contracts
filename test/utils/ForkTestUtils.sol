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
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployXReserve} from "./DeployXReserve.sol";

/// Helpers for managing values and dependencies between forks
/// @dev USDC addresses: https://developers.circle.com/stablecoins/usdc-contract-addresses
/// @dev CCTP domains: https://developers.circle.com/cctp/supported-domains
/// @dev CCTP contract addresses: https://developers.circle.com/cctp/evm-smart-contracts
/// @dev Gateway addresses: https://developers.circle.com/gateway/references/contract-addresses
library ForkTestUtils {
    error UnknownChain(uint256 id);

    uint32 public constant LOCAL_DOMAIN = 99;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant ETHEREUM_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ARBITRUM_CHAIN_ID = 42161;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 public constant OPTIMISM_CHAIN_ID = 10;
    uint256 public constant OPTIMISM_SEPOLIA_CHAIN_ID = 11155420;

    address public constant TESTNET_TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    address public constant MAINNET_TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address public constant TESTNET_GATEWAY_WALLET = 0x0077777d7EBA4688BDeF3E311b846F25870A19B9;
    address public constant TESTNET_GATEWAY_MINTER = 0x0022222ABE238Cc2C7Bb1f21003F0a260052475B;
    address public constant MAINNET_GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;
    address public constant MAINNET_GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

    struct ForkVars {
        uint32 domain;
        address usdc;
        address tokenMessenger;
        address tokenMessengerV2;
        address gatewayWallet;
        address gatewayMinter;
    }

    /// @notice Retrieves configuration variables for the current forked chain.
    /// @dev Returns addresses and domain IDs for USDC, TokenMessenger, GatewayWallet, etc.
    /// @return ForkVars struct with chain-specific contract addresses and domain ID.
    function forkVars() public returns (ForkVars memory) {
        if (block.chainid == LOCAL_CHAIN_ID) {
            return deployLocalDependencies();
        }

        if (block.chainid == ETHEREUM_CHAIN_ID) {
            return ForkVars({
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                domain: 0,
                tokenMessenger: 0xBd3fa81B58Ba92a82136038B25aDec7066af3155,
                tokenMessengerV2: MAINNET_TOKEN_MESSENGER_V2,
                gatewayWallet: MAINNET_GATEWAY_WALLET,
                gatewayMinter: MAINNET_GATEWAY_MINTER
            });
        }

        if (block.chainid == ETHEREUM_SEPOLIA_CHAIN_ID) {
            return ForkVars({
                usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
                domain: 0,
                tokenMessenger: 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5,
                tokenMessengerV2: TESTNET_TOKEN_MESSENGER_V2,
                gatewayWallet: TESTNET_GATEWAY_WALLET,
                gatewayMinter: TESTNET_GATEWAY_MINTER
            });
        }

        if (block.chainid == OPTIMISM_CHAIN_ID) {
            return ForkVars({
                usdc: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
                domain: 2,
                tokenMessenger: 0x2B4069517957735bE00ceE0fadAE88a26365528f,
                tokenMessengerV2: MAINNET_TOKEN_MESSENGER_V2,
                gatewayWallet: MAINNET_GATEWAY_WALLET,
                gatewayMinter: MAINNET_GATEWAY_MINTER
            });
        }

        if (block.chainid == OPTIMISM_SEPOLIA_CHAIN_ID) {
            return ForkVars({
                usdc: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7,
                domain: 2,
                tokenMessenger: 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5,
                tokenMessengerV2: TESTNET_TOKEN_MESSENGER_V2,
                gatewayWallet: TESTNET_GATEWAY_WALLET,
                gatewayMinter: TESTNET_GATEWAY_MINTER
            });
        }

        if (block.chainid == ARBITRUM_CHAIN_ID) {
            return ForkVars({
                usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                domain: 3,
                tokenMessenger: 0x19330d10D9Cc8751218eaf51E8885D058642E08A,
                tokenMessengerV2: MAINNET_TOKEN_MESSENGER_V2,
                gatewayWallet: MAINNET_GATEWAY_WALLET,
                gatewayMinter: MAINNET_GATEWAY_MINTER
            });
        }

        if (block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID) {
            return ForkVars({
                usdc: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d,
                domain: 3,
                tokenMessenger: 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5,
                tokenMessengerV2: TESTNET_TOKEN_MESSENGER_V2,
                gatewayWallet: TESTNET_GATEWAY_WALLET,
                gatewayMinter: TESTNET_GATEWAY_MINTER
            });
        }

        revert UnknownChain(block.chainid);
    }

    function deployLocalDependencies() public returns (ForkVars memory) {
        DeployXReserve mockDeployer = new DeployXReserve();
        FiatTokenV2_2 usdc = mockDeployer.deployMockFiatToken(mockDeployer.defaultOwner());
        (GatewayWallet gatewayWallet, GatewayMinter gatewayMinter) = mockDeployer.deployGateway(
            mockDeployer.defaultOwner(),
            LOCAL_DOMAIN,
            address(usdc),
            mockDeployer.defaultGatewayAttestationSigner(),
            mockDeployer.defaultGatewayBurnSigner(),
            mockDeployer.defaultGatewayFeeRecipient()
        );
        address tokenMessenger =
            mockDeployer.deployTokenMessenger(false, mockDeployer.defaultOwner(), LOCAL_DOMAIN, address(usdc));
        address tokenMessengerV2 =
            mockDeployer.deployTokenMessenger(true, mockDeployer.defaultOwner(), LOCAL_DOMAIN, address(usdc));

        return ForkVars({
            domain: LOCAL_DOMAIN,
            usdc: address(usdc),
            tokenMessenger: tokenMessenger,
            tokenMessengerV2: tokenMessengerV2,
            gatewayWallet: address(gatewayWallet),
            gatewayMinter: address(gatewayMinter)
        });
    }
}
