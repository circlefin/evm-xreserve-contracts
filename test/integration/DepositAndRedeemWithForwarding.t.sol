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
import {WithdrawHookData} from "./../../src/lib/WithdrawHookData.sol";
import {WithdrawHookDataLib} from "./../../src/lib/WithdrawHookDataLib.sol";
import {ForwardingCalldataLib} from "./../utils/ForwardingCalldataLib.sol";
import {XReserveMultichainTestUtils} from "./../utils/XReserveMultichainTestUtils.sol";

/// @title DepositAndRedeemWithForwardingTest
/// @notice Integration test demonstrating deposit, burn intent creation, attestation, and forwarding flows
///         1. User deposits and reserves USDC on the source chain via xReserve
///         2. User creates and signs a BurnIntent with WithdrawHookData for the destination chain
///         3. Attestation is produced for the burn intent
///         4. User uses forwarding logic (e.g., CCTP depositForBurn) on the destination chain
contract DepositAndRedeemWithForwardingTest is XReserveMultichainTestUtils {
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

    function test_singleDepositAndForwardViaCCTPV1DepositForBurn_success() public {
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
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

        _singleDepositAndForwardTest(burnIntent);
    }

    function test_singleDepositAndForwardViaCCTPV1DepositForBurnWithCaller_success() public {
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntent.spec.hookData = _createWithdrawHookData(
            address(ethereum.tokenMessenger),
            ForwardingCalldataLib.encodeCCTPV1DepositForBurnWithCaller(
                DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE, address(ethereum.usdc)
            )
        );
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));

        _singleDepositAndForwardTest(burnIntent);
    }

    function test_singleDepositAndForwardViaCCTPV2DepositForBurn_success() public {
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntent.spec.hookData = _createWithdrawHookData(
            address(ethereum.tokenMessengerV2),
            ForwardingCalldataLib.encodeCCTPV2DepositForBurn(
                DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE, address(ethereum.usdc)
            )
        );
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));

        _singleDepositAndForwardTest(burnIntent);
    }

    function test_singleDepositAndForwardViaCCTPV2DepositForBurnWithHook_success() public {
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntent.spec.hookData = _createWithdrawHookData(
            address(ethereum.tokenMessengerV2),
            ForwardingCalldataLib.encodeCCTPV2DepositForBurnWithHook(
                DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE, address(ethereum.usdc)
            )
        );
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));

        _singleDepositAndForwardTest(burnIntent);
    }

    function test_singleDepositAndForwardViaXReserveDepositToRemote_success() public {
        uint32 remoteDomainId2 = 10002;
        address[] memory remoteDomainAttesters = new address[](2);
        remoteDomainAttesters[0] = makeAddr("attester1");
        remoteDomainAttesters[1] = makeAddr("attester2");
        vm.startPrank(ethereum.reserve.owner());
        {
            ethereum.reserve.registerRemoteDomain(
                remoteDomainId2,
                makeAddr("domainManager"),
                makeAddr("domainPauser"),
                remoteDomainAttesters,
                2,
                10,
                address(0)
            );
            ethereum.reserve.registerRemoteToken(address(ethereum.usdc), remoteDomainId2, REMOTE_TOKEN_ADDRESS);
        }
        vm.stopPrank();

        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        // Create custom hook data with domain 10002 to match the forwarding target
        WithdrawHookData memory withdrawData = WithdrawHookData({
            version: 1,
            remoteDomain: REMOTE_DOMAIN_ID, // Match the forwarding target domain
            remoteToken: REMOTE_TOKEN_ADDRESS,
            remoteDepositor: REMOTE_RECIPIENT,
            forwardingContract: GatewayAddressLib._addressToBytes32(address(ethereum.reserve)),
            forwardingCalldata: ForwardingCalldataLib.encodeXReserveDepositToRemote(
                DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE, remoteDomainId2, address(ethereum.usdc)
            )
        });
        burnIntent.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawData);
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));

        _singleDepositAndForwardTest(burnIntent);
    }

    function _singleDepositAndForwardTest(BurnIntent memory burnIntent) internal {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
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
}
