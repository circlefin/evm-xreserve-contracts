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

import {TokenMessenger} from "@cctp/TokenMessenger.sol";
import {TokenMinter} from "@cctp/TokenMinter.sol";
import {BaseTokenMessenger} from "@cctp/v2/BaseTokenMessenger.sol";
import {TokenMessengerV2} from "@cctp/v2/TokenMessengerV2.sol";
import {TokenMinterV2} from "@cctp/v2/TokenMinterV2.sol";
import {GatewayMinter} from "@gateway/src/GatewayMinter.sol";
import {GatewayWallet} from "@gateway/src/GatewayWallet.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {RemoteDomainDepositor} from "./../../src/RemoteDomainDepositor.sol";
import {UpgradeablePlaceholder} from "./../../src/UpgradeablePlaceholder.sol";
import {xReserve} from "./../../src/xReserve.sol";
import {DeployGateway} from "./DeployGateway.sol";
import {DeployMockFiatToken} from "./DeployMockFiatToken.sol";
import {DeployTokenMessenger} from "./DeployTokenMessenger.sol";

/// @title DeployXReserve
/// @notice A contract for deploying the xReserve contract.
contract DeployXReserve is DeployGateway, DeployMockFiatToken, DeployTokenMessenger {
    uint256 public constant GATEWAY_WITHDRAW_DELAY = (3 * 24 * 60 * 60) / 12;
    uint256 public constant TOKEN_MESSENGER_MAX_BURN_MESSAGE_SIZE = 1000;

    address public defaultOwner = makeAddr("owner");
    uint32 public defaultCCTPRemoteDomain = 5; // solana
    bytes32 public defaultCCTPRemoteTokenMessenger = bytes32(bytes20(makeAddr("solanaRemoteTokenMessenger")));
    address public defaultGatewayAttestationSigner = makeAddr("GatewayAttestationSigner");
    address public defaultGatewayBurnSigner = makeAddr("GatewayBurnSigner");
    address public defaultGatewayFeeRecipient = makeAddr("GatewayFeeRecipient");

    /// @dev Deploys a xReserve contract with the given constructor arguments.
    function deployXReserve(
        address owner,
        uint32 domain,
        address gatewayMinter,
        address gatewayWallet,
        address tokenMessenger,
        address tokenMessengerV2
    ) public returns (xReserve reserve) {
        vm.startPrank(owner);
        {
            // Use fixed salts to simulate Create2 deployment process
            // Ensure the reserve proxy is deployed to the same address across forks
            // This allows RemoteDomainDepositor contracts to be deployed to the same address across forks as well,
            // which allows the same attesters to produce a single burn signature that can be used to burn across multiple source chains.
            // Deploy placeholder using CREATE2 and initialize it
            address placeholderImpl =
                Create2.deploy(0, bytes32("deploy_placeholder"), type(UpgradeablePlaceholder).creationCode);
            // Deploy proxy using CREATE2 and initialize it with placeholder implementation
            address proxy = Create2.deploy(
                0,
                bytes32("deploy_reserve_proxy"),
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(placeholderImpl, bytes("")) // Set to placeholder initially with empty initialization data
                )
            );
            UpgradeablePlaceholder(proxy).initialize(owner);

            // Deploy reserve implementation
            address reserveImpl = address(new xReserve(gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2));

            // Deploy RemoteDomainDepositor implementation using CREATE2 for testing
            address remoteDomainDepositorImplementation =
                Create2.deploy(0, bytes32("deploy_depositor_impl"), type(RemoteDomainDepositor).creationCode);

            // Upgrade proxy to reserve implementation
            UpgradeablePlaceholder(address(proxy)).upgradeToAndCall(
                reserveImpl, _encodeInitializeData(owner, domain, remoteDomainDepositorImplementation)
            );
            reserve = xReserve(proxy);
        }
        vm.stopPrank();
    }

    /// @dev Helper function to encode initialize data
    function _encodeInitializeData(address owner, uint32 domain, address remoteDomainDepositorImplementation)
        private
        pure
        returns (bytes memory)
    {
        address[] memory emptyTokens = new address[](0);
        return abi.encodeWithSignature(
            "initialize(uint32,address,address,address,address[],address)",
            domain,
            owner, // pauser
            owner, // blocklister
            owner, // registrationManager
            emptyTokens,
            remoteDomainDepositorImplementation
        );
    }

    /// @dev Deploys a GatewayWallet and GatewayMinter contract.
    function deployGateway(
        address owner,
        uint32 domain,
        address fiatToken,
        address attestationSigner,
        address burnSigner,
        address feeRecipient
    ) public returns (GatewayWallet gatewayWallet, GatewayMinter gatewayMinter) {
        (gatewayWallet, gatewayMinter) = deployGateway(owner, domain);

        vm.startPrank(owner);
        {
            // Configure minter settings
            gatewayMinter.addSupportedToken(fiatToken);
            gatewayMinter.addAttestationSigner(attestationSigner);
            gatewayMinter.updateMintAuthority(fiatToken, fiatToken);

            // Configure wallet settings
            gatewayWallet.addSupportedToken(fiatToken);
            gatewayWallet.addBurnSigner(burnSigner);
            gatewayWallet.updateFeeRecipient(feeRecipient);
            gatewayWallet.updateWithdrawalDelay(GATEWAY_WITHDRAW_DELAY);
        }
        vm.stopPrank();

        // Setup wallet and minter as USDC minter / burner
        configureMinter(address(gatewayMinter), fiatToken);
        configureMinter(address(gatewayWallet), fiatToken);
        return (gatewayWallet, gatewayMinter);
    }

    /// @dev Deploys a TokenMessenger or TokenMessengerV2 contract, depending on isV2.
    function deployTokenMessenger(bool isV2, address owner, uint32 domain, address fiatToken)
        public
        returns (address)
    {
        BaseTokenMessenger messenger;
        TokenMinter minter;
        if (isV2) {
            (TokenMessengerV2 messengerV2, TokenMinterV2 minterV2) = deployTokenMessengerAndMinterV2(owner, domain);
            messenger = BaseTokenMessenger(address(messengerV2));
            minter = TokenMinter(address(minterV2));
        } else {
            (TokenMessenger messengerInstance, TokenMinter minterV1) = deployTokenMessengerAndMinterV1(owner, domain);
            messenger = BaseTokenMessenger(address(messengerInstance));
            minter = minterV1;
        }

        messenger.addRemoteTokenMessenger(defaultCCTPRemoteDomain, defaultCCTPRemoteTokenMessenger);
        configureNewTokenOnTokenMessenger(
            address(messenger), address(fiatToken), defaultCCTPRemoteDomain, defaultCCTPRemoteTokenMessenger
        );
        return address(messenger);
    }

    function configureNewTokenOnTokenMessenger(
        address tm,
        address token,
        uint32 remoteDomain,
        bytes32 remoteTokenMessenger
    ) public {
        BaseTokenMessenger messenger = BaseTokenMessenger(tm);
        TokenMinter minter = TokenMinter(address(messenger.localMinter()));

        vm.startPrank(minter.tokenController());
        {
            minter.linkTokenPair(token, remoteDomain, remoteTokenMessenger);
            minter.setMaxBurnAmountPerMessage(token, type(uint256).max);
        }
        vm.stopPrank();
        assertEq(minter.getLocalToken(remoteDomain, remoteTokenMessenger), token);

        // Configure CCTP with fiatToken mint allowance
        configureMinter(address(minter), token);
    }

    /// @dev Configures the minter for the given fiat token.
    function configureMinter(address minter, address fiatToken) public {
        FiatTokenV2_2 nativeToken = FiatTokenV2_2(fiatToken);
        address masterMinter = nativeToken.masterMinter();
        vm.prank(masterMinter);
        nativeToken.configureMinter(address(minter), type(uint256).max);
    }
}
