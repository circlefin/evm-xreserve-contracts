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

import {AddressLib as GatewayAddressLib} from "@gateway/src/lib/AddressLib.sol";
import {BurnIntent} from "@gateway/src/lib/BurnIntents.sol";
import {TransferSpec} from "@gateway/src/lib/TransferSpec.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {RemoteDomainDepositor} from "./../../src/RemoteDomainDepositor.sol";
import {ForwardingCalldataLib} from "./../utils/ForwardingCalldataLib.sol";
import {XReserveMultichainTestUtils} from "./../utils/XReserveMultichainTestUtils.sol";

/// @title AttemptedAttesterAndSignatureManipulationTest
/// @notice Integration tests for attempted attester and signature manipulation scenarios.
///         These tests ensure that malicious attempts to forge, tamper, or replay
///         attester signatures or manipulate attester lists are correctly detected and rejected.
///         The flows include deposit, burn intent creation, attestation, and attempts at
///         signature or attester manipulation during withdrawal or forwarding.
contract AttemptedAttesterAndSignatureManipulationTest is XReserveMultichainTestUtils {
    using MessageHashUtils for bytes32;

    // Test addresses and keys
    address public depositor = makeAddr("depositor");
    address public depositor2 = makeAddr("depositor2");
    address public recipient = makeAddr("recipient");

    // Reserve setups
    ReserveSetup private ethereum;

    function setUp() public {
        // Setup source chain (Ethereum) with xReserve
        ethereum = _initializeReserveContracts("ethereum");

        // Now make contracts persistent after all deployments are complete
        vm.selectFork(ethereum.forkId);
        vm.makePersistent(address(ethereum.reserve));
        vm.makePersistent(ethereum.reserve.remoteDomainDepositorImplementation());

        // Give depositor some USDC on source chain
        vm.selectFork(ethereum.forkId);
        deal(address(ethereum.usdc), depositor, DEPOSIT_TO_REMOTE_AMOUNT);
    }

    function test_singleDepositAndWithdraw_withAttesterRotationAndSignatureThresholdBump_succeedWithFundsBurnt()
        public
    {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntent.spec.hookData = _createWithdrawHookData(
            address(ethereum.tokenMessenger),
            ForwardingCalldataLib.encodeCCTPV1DepositForBurn(
                DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE, address(ethereum.usdc)
            )
        );
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));
        burnIntents[0] = burnIntent;

        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.reserve.withdraw(encodedAttestations, attestationSignature);

        // ============ STEP 4: Attester key is rotated and signature threshold increases ============
        RemoteDomainDepositor rdd = RemoteDomainDepositor(remoteDomainDepositor);
        vm.startPrank(rdd.domainManager());
        {
            // Enable new attesters
            address newAttester1 = makeAddr("newAttester1");
            address newAttester2 = makeAddr("newAttester2");
            address newAttester3 = makeAddr("newAttester3");
            rdd.enableAttester(newAttester1);
            rdd.enableAttester(newAttester2);
            rdd.enableAttester(newAttester3);

            // Bump signature threshold
            rdd.setSignatureThreshold(3);

            // Disable old attester
            rdd.disableAttester(ethereum.attesters[0]);
            rdd.disableAttester(ethereum.attesters[1]);
        }

        // ============ STEP 5: Funds are burnt on the Ethereum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }

    function test_singleDepositAndWithdraw_withDisallowRemoteDomainDepositorContract_succeedWithFundsBurnt() public {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntent.spec.hookData = _createWithdrawHookData(
            address(ethereum.tokenMessenger),
            ForwardingCalldataLib.encodeCCTPV1DepositForBurn(
                DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE, address(ethereum.usdc)
            )
        );
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));
        burnIntents[0] = burnIntent;

        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.reserve.withdraw(encodedAttestations, attestationSignature);

        // ============ STEP 4: Attester key is rotated and signature threshold increases ============
        vm.startPrank(ethereum.gatewayWallet.contractSignersAllowlister());
        {
            // Disallow remote domain depositor contract
            ethereum.gatewayWallet.disallowContractSigner(remoteDomainDepositor);
        }

        // ============ STEP 5: Funds are burnt on the Ethereum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }
}
