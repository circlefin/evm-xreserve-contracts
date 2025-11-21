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

import {BurnIntent} from "@gateway/src/lib/BurnIntents.sol";
import {TransferSpec} from "@gateway/src/lib/TransferSpec.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {XReserveMultichainTestUtils} from "./../utils/XReserveMultichainTestUtils.sol";

/// @title DepositAndDirectRedeemTest
/// @notice Integration test for direct deposit and redeem flow:
///         1. User deposits and reserves USDC on the source chain via xReserve
///         2. User creates and signs a BurnIntent for the destination chain
///         3. Attestation is generated for the burn intent
///         4. User redeems on the destination chain using GatewayMinter and attestation
contract DepositAndDirectRedeemTest is XReserveMultichainTestUtils {
    using MessageHashUtils for bytes32;

    // Test addresses and keys
    address public depositor = makeAddr("depositor");
    address public depositor2 = makeAddr("depositor2");
    address public recipient = makeAddr("recipient");

    // Reserve setups
    ReserveSetup private ethereum;
    ReserveSetup private arbitrum;

    function setUp() public {
        // Setup source chain (Ethereum) with xReserve
        ethereum = _initializeReserveContracts("ethereum");
        // Setup destination chain (Arbitrum)
        arbitrum = _initializeReserveContracts("arbitrum");

        // Make contracts persistent after all deployments are complete
        // This ensures the xReserve proxy and RemoteDomainDepositor contracts have the same addresses on both forks
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        vm.selectFork(ethereum.forkId);
        vm.makePersistent(address(ethereum.reserve));
        vm.makePersistent(ethereum.reserve.remoteDomainDepositorImplementation());
        // Make the xReserve implementation persistent (has different address per chain due to constructor args)
        address ethXReserveImpl = address(uint160(uint256(vm.load(address(ethereum.reserve), implSlot))));
        vm.makePersistent(ethXReserveImpl);

        vm.selectFork(arbitrum.forkId);
        vm.makePersistent(address(arbitrum.reserve));
        vm.makePersistent(arbitrum.reserve.remoteDomainDepositorImplementation());
        // Make the xReserve implementation persistent (has different address per chain due to constructor args)
        address arbXReserveImpl = address(uint160(uint256(vm.load(address(arbitrum.reserve), implSlot))));
        vm.makePersistent(arbXReserveImpl);

        // Give depositor some USDC on source chain
        vm.selectFork(ethereum.forkId);
        deal(address(ethereum.usdc), depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        vm.selectFork(arbitrum.forkId);
        deal(address(arbitrum.usdc), depositor2, DEPOSIT_TO_REMOTE_AMOUNT);
    }

    function test_singleDepositAndRedeemViaGatewayRoundtrip_fromOriginalSourceChain_viaGateway_success() public {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent =
            _createBurnIntent(ethereum, ethereum, remoteDomainDepositor, recipient, DEPOSIT_TO_REMOTE_AMOUNT);
        burnIntents[0] = burnIntent;
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.gatewayMinter.gatewayMint(encodedAttestations, attestationSignature);

        // ============ STEP 4: Funds are burnt on the Ethereum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }

    function test_singleDepositAndRedeemViaGatewayRoundtrip_fromOriginalSourceChain_viaXReserve_success() public {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent =
            _createBurnIntent(ethereum, ethereum, remoteDomainDepositor, recipient, DEPOSIT_TO_REMOTE_AMOUNT);
        burnIntents[0] = burnIntent;
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.reserve.withdraw(encodedAttestations, attestationSignature);

        // ============ STEP 4: Funds are burnt on the Ethereum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }

    function test_singleDepositAndRedeemViaGatewayRoundtrip_fromAlternativeChain_viaGateway_success() public {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData for Arbitrum ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent =
            _createBurnIntent(ethereum, arbitrum, remoteDomainDepositor, recipient, DEPOSIT_TO_REMOTE_AMOUNT);
        burnIntents[0] = burnIntent;
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on destination chain ============
        vm.selectFork(arbitrum.forkId);
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, arbitrum.attestationSignerKey);
        arbitrum.reserve.withdraw(encodedAttestations, attestationSignature);

        // ============ STEP 4: Funds are burnt on the source chain ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }

    function test_multipleDepositAndRedeemViaGatewayRoundtrip_fromOriginalSourceChain_viaGateway_success() public {
        // ============ STEP 1: User deposit USDC on Ethereum and Arbitrum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);
        _depositToRemote(arbitrum, depositor2, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        BurnIntent[] memory burnIntents = new BurnIntent[](2);

        vm.selectFork(ethereum.forkId);
        address remoteDomainDepositorEthereum = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent memory burnIntentEthereum =
            _createBurnIntent(ethereum, ethereum, remoteDomainDepositorEthereum, recipient, DEPOSIT_TO_REMOTE_AMOUNT);

        vm.selectFork(arbitrum.forkId);
        address remoteDomainDepositorArbitrum = arbitrum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent memory burnIntentArbitrum =
            _createBurnIntent(arbitrum, ethereum, remoteDomainDepositorArbitrum, recipient, DEPOSIT_TO_REMOTE_AMOUNT);

        burnIntents[0] = burnIntentEthereum;
        burnIntents[1] = burnIntentArbitrum;

        // Assuming same attesters configured on both chains
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        vm.selectFork(ethereum.forkId);
        TransferSpec[] memory transferSpecs = new TransferSpec[](2);
        transferSpecs[0] = burnIntents[0].spec;
        transferSpecs[1] = burnIntents[1].spec;
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.gatewayMinter.gatewayMint(encodedAttestations, attestationSignature);

        // ============ STEP 4: Funds are burnt on the Ethereum and Arbitrum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
        _burnFromChain(arbitrum, encodedBurnIntents, burnSignature);
    }
}
