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
import {AddressLib as GatewayAddressLib} from "@gateway/src/lib/AddressLib.sol";
import {AttestationLib} from "@gateway/src/lib/AttestationLib.sol";
import {Attestation, AttestationSet} from "@gateway/src/lib/Attestations.sol";
import {TransferSpec, TRANSFER_SPEC_VERSION} from "@gateway/src/lib/TransferSpec.sol";
import {TransferSpecLib} from "@gateway/src/lib/TransferSpecLib.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AddressLib} from "./../../src/lib/AddressLib.sol";
import {WithdrawHookData} from "./../../src/lib/WithdrawHookData.sol";
import {WithdrawHookDataLib} from "./../../src/lib/WithdrawHookDataLib.sol";
import {DepositToRemote} from "./../../src/modules/x-reserve/DepositToRemote.sol";
import {Pausing} from "./../../src/modules/x-reserve/Pausing.sol";
import {RemoteDomainRegistration} from "./../../src/modules/x-reserve/RemoteDomainRegistration.sol";
import {Withdrawal} from "./../../src/modules/x-reserve/Withdrawal.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";
import {ForkTestUtils} from "./../utils/ForkTestUtils.sol";
import {ForwardingCalldataLib} from "./../utils/ForwardingCalldataLib.sol";

// solhint-disable-next-line max-states-count
contract XReserveWithdrawTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;
    FiatTokenV2_2 private token2; // Second token for multi-token tests

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    uint32 private domain;
    address private gatewayMinter;
    address private gatewayWallet;
    address private tokenMessenger;
    address private tokenMessengerV2;
    bytes32 private remoteToken = bytes32(uint256(uint160(makeAddr("remoteToken"))));
    bytes32 private remoteToken2 = bytes32(uint256(uint160(makeAddr("remoteToken2"))));

    // Remote tokens for the second token
    bytes32 private remoteToken2ForDomain = bytes32(uint256(uint160(makeAddr("remoteToken2Domain1"))));
    bytes32 private remoteToken2ForDomain2 = bytes32(uint256(uint160(makeAddr("remoteToken2Domain2"))));
    uint32 private constant REMOTE_DOMAIN = 10001;
    uint32 private constant REMOTE_DOMAIN_2 = 10002;
    uint32 private constant CCTP_REMOTE_DOMAIN = 5;

    Attestation private defaultAttestation;
    WithdrawHookData private withdrawHookDataToRemoteChain;
    WithdrawHookData private withdrawHookDataToCctpV1;
    WithdrawHookData private withdrawHookDataToCctpV2;
    WithdrawHookData private withdrawHookDataNoForwarding;
    address private remoteDepositor;
    address private remoteDepositor2;
    uint256 private gatewayMintSignerPrivateKey;

    function setUp() public {
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);
        gatewayMinter = forkedVars.gatewayMinter;
        gatewayWallet = forkedVars.gatewayWallet;
        tokenMessenger = forkedVars.tokenMessenger;
        tokenMessengerV2 = forkedVars.tokenMessengerV2;

        (, gatewayMintSignerPrivateKey) = makeAddrAndKey("gatewayMintSigner");

        reserve = deployXReserve(
            owner,
            domain,
            forkedVars.gatewayMinter,
            forkedVars.gatewayWallet,
            forkedVars.tokenMessenger,
            forkedVars.tokenMessengerV2
        );

        token2 = deployMockFiatToken(owner);
        vm.prank(token2.masterMinter());
        token2.configureMinter(gatewayMinter, type(uint256).max);

        configureNewTokenOnTokenMessenger(tokenMessenger, address(token2), REMOTE_DOMAIN, remoteToken2);
        configureNewTokenOnTokenMessenger(tokenMessengerV2, address(token2), REMOTE_DOMAIN, remoteToken2);

        GatewayWallet wallet = GatewayWallet(gatewayWallet);
        vm.startPrank(wallet.owner());
        {
            wallet.addSupportedToken(address(token));
            wallet.addSupportedToken(address(token2));
        }
        vm.stopPrank();

        // Mock upgrade to GatewayWalletV2 if not local chain
        if (block.chainid != ForkTestUtils.LOCAL_CHAIN_ID) {
            GatewayWallet gatewayWalletV2Impl = new GatewayWallet();
            vm.startPrank(wallet.owner());
            {
                wallet.upgradeToAndCall(address(gatewayWalletV2Impl), bytes(""));
                wallet.updateContractSignersAllowlister(makeAddr("contractSignersAllowlister"));
            }
            vm.stopPrank();
        }

        // Register remote domains for testing
        address[] memory attesters = new address[](2);
        attesters[0] = makeAddr("attester1");
        attesters[1] = makeAddr("attester2");

        vm.startPrank(owner);
        {
            remoteDepositor = reserve.registerRemoteDomain(
                REMOTE_DOMAIN, makeAddr("domainManager"), makeAddr("domainPauser"), attesters, 2, 50400, address(0)
            );
            remoteDepositor2 = reserve.registerRemoteDomain(
                REMOTE_DOMAIN_2, makeAddr("domainManager"), makeAddr("domainPauser"), attesters, 2, 50400, address(0)
            );

            reserve.addSupportedToken(address(token));
            reserve.addSupportedToken(address(token2));

            // Register both tokens for both remote domains
            reserve.registerRemoteToken(address(token), REMOTE_DOMAIN, remoteToken);
            reserve.registerRemoteToken(address(token), REMOTE_DOMAIN_2, remoteToken2);
            reserve.registerRemoteToken(address(token2), REMOTE_DOMAIN, remoteToken2ForDomain);
            reserve.registerRemoteToken(address(token2), REMOTE_DOMAIN_2, remoteToken2ForDomain2);
        }
        vm.stopPrank();

        vm.startPrank(wallet.contractSignersAllowlister());
        {
            wallet.allowlistContractSigner(address(remoteDepositor));
            wallet.allowlistContractSigner(address(remoteDepositor2));
        }
        vm.stopPrank();

        // Set the gateway mint signer and add support for token2
        GatewayMinter minter = GatewayMinter(gatewayMinter);
        vm.startPrank(minter.owner());
        {
            minter.addAttestationSigner(address(vm.addr(gatewayMintSignerPrivateKey)));
            minter.addSupportedToken(address(token));
            minter.addSupportedToken(address(token2));
        }
        vm.stopPrank();

        defaultAttestation = Attestation({
            maxBlockHeight: block.number + 100,
            spec: TransferSpec({
                version: TRANSFER_SPEC_VERSION,
                sourceDomain: domain,
                destinationDomain: domain,
                sourceContract: GatewayAddressLib._addressToBytes32(gatewayWallet),
                destinationContract: GatewayAddressLib._addressToBytes32(gatewayMinter),
                sourceToken: GatewayAddressLib._addressToBytes32(address(token)),
                destinationToken: GatewayAddressLib._addressToBytes32(address(token)),
                sourceDepositor: GatewayAddressLib._addressToBytes32(user),
                destinationRecipient: GatewayAddressLib._addressToBytes32(address(reserve)),
                sourceSigner: GatewayAddressLib._addressToBytes32(user),
                destinationCaller: bytes32(0),
                value: 1000,
                salt: keccak256("saltWithdraw"),
                hookData: bytes("")
            })
        });

        withdrawHookDataToRemoteChain = WithdrawHookData({
            version: 1,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: remoteToken,
            remoteDepositor: GatewayAddressLib._addressToBytes32(remoteDepositor),
            forwardingContract: GatewayAddressLib._addressToBytes32(address(reserve)),
            forwardingCalldata: ForwardingCalldataLib.encodeXReserveDepositToRemote(1000, REMOTE_DOMAIN_2, address(token))
        });

        withdrawHookDataToCctpV1 = WithdrawHookData({
            version: 1,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: remoteToken,
            remoteDepositor: GatewayAddressLib._addressToBytes32(remoteDepositor),
            forwardingContract: GatewayAddressLib._addressToBytes32(address(tokenMessenger)),
            forwardingCalldata: ForwardingCalldataLib.encodeCCTPV1DepositForBurn(1000, address(token))
        });

        withdrawHookDataToCctpV2 = WithdrawHookData({
            version: 1,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: remoteToken,
            remoteDepositor: GatewayAddressLib._addressToBytes32(remoteDepositor),
            forwardingContract: GatewayAddressLib._addressToBytes32(address(tokenMessengerV2)),
            forwardingCalldata: ForwardingCalldataLib.encodeCCTPV2DepositForBurn(1000, address(token))
        });

        withdrawHookDataNoForwarding = WithdrawHookData({
            version: 1,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: remoteToken,
            remoteDepositor: GatewayAddressLib._addressToBytes32(remoteDepositor),
            forwardingContract: GatewayAddressLib._addressToBytes32(address(0)),
            forwardingCalldata: bytes("")
        });
    }

    function test_withdraw_succeeds_withdrawNoForwarding() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataNoForwarding);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation.spec))
        );

        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_succeeds_withdrawNoForwardingDifferentDestination() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.destinationRecipient = GatewayAddressLib._addressToBytes32(makeAddr("differentDestination"));
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataNoForwarding);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            makeAddr("differentDestination"),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation.spec))
        );

        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_succeeds_withdrawToRemoteChain() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToRemoteChain);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        // Test withdraw succeeds
        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token),
            1000,
            address(reserve),
            ForwardingCalldataLib.X_RESERVE_REMOTE_RECIPIENT,
            REMOTE_DOMAIN_2,
            remoteToken2,
            0,
            ForwardingCalldataLib.X_RESERVE_HOOK_DATA
        );
        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation.spec))
        );

        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_succeeds_withdrawToCCTPV1Chain() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV1);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        // Test withdraw succeeds
        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation.spec))
        );

        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_succeeds_withdrawToCCTPV2Chain() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV2);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation.spec))
        );

        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_succeeds_withdrawWithAttestationSet() public {
        Attestation memory attestationWithdrawToRemoteChain = defaultAttestation;
        Attestation memory attestationWithdrawToCctpV1 = defaultAttestation;
        Attestation memory attestationWithdrawToCctpV2 = defaultAttestation;
        Attestation memory attestationWithdrawNoForwarding = defaultAttestation;

        attestationWithdrawToRemoteChain.spec.hookData =
            WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToRemoteChain);
        attestationWithdrawToCctpV1.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV1);
        attestationWithdrawToCctpV2.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV2);
        attestationWithdrawNoForwarding.spec.hookData =
            WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataNoForwarding);

        Attestation[] memory attestations = new Attestation[](4);
        attestations[0] = attestationWithdrawToRemoteChain;
        attestations[1] = attestationWithdrawToCctpV1;
        attestations[2] = attestationWithdrawToCctpV2;
        attestations[3] = attestationWithdrawNoForwarding;

        AttestationSet memory attestationSet = AttestationSet({attestations: attestations});

        bytes memory attestationSetPayload = AttestationLib.encodeAttestationSet(attestationSet);
        bytes memory signature = _signAttestation(attestationSetPayload);

        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token),
            1000,
            address(reserve),
            ForwardingCalldataLib.X_RESERVE_REMOTE_RECIPIENT,
            REMOTE_DOMAIN_2,
            remoteToken2,
            0,
            ForwardingCalldataLib.X_RESERVE_HOOK_DATA
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationWithdrawToRemoteChain.spec))
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationWithdrawToCctpV1.spec))
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationWithdrawToCctpV2.spec))
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationWithdrawNoForwarding.spec))
        );

        reserve.withdraw(attestationSetPayload, signature);
    }

    // ============ Multi-Token Forwarding Tests ============

    function test_withdraw_succeeds_multiTokenForwarding_differentDestinations() public {
        // Create attestations for different tokens with different amounts
        Attestation memory attestationToken1 = defaultAttestation;
        attestationToken1.spec.sourceToken = GatewayAddressLib._addressToBytes32(address(token));
        attestationToken1.spec.destinationToken = GatewayAddressLib._addressToBytes32(address(token));
        attestationToken1.spec.value = 1000;
        attestationToken1.spec.salt = keccak256("saltToken1");

        Attestation memory attestationToken2 = defaultAttestation;
        attestationToken2.spec.sourceToken = GatewayAddressLib._addressToBytes32(address(token2));
        attestationToken2.spec.destinationToken = GatewayAddressLib._addressToBytes32(address(token2));
        attestationToken2.spec.value = 2500;
        attestationToken2.spec.salt = keccak256("saltToken2");

        // Setup different forwarding for each token
        WithdrawHookData memory token1HookData = withdrawHookDataToRemoteChain;
        token1HookData.remoteToken = remoteToken;

        WithdrawHookData memory token2HookData = withdrawHookDataToCctpV1;
        token2HookData.remoteToken = remoteToken2ForDomain;
        token2HookData.forwardingCalldata = ForwardingCalldataLib.encodeCCTPV1DepositForBurn(1000, address(token2));

        attestationToken1.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(token1HookData);
        attestationToken2.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(token2HookData);

        Attestation[] memory attestations = new Attestation[](2);
        attestations[0] = attestationToken1;
        attestations[1] = attestationToken2;

        AttestationSet memory attestationSet = AttestationSet({attestations: attestations});
        bytes memory attestationSetPayload = AttestationLib.encodeAttestationSet(attestationSet);
        bytes memory signature = _signAttestation(attestationSetPayload);

        // Expect events for both token withdrawals
        // Expect DepositToRemote event for token1 (xReserve forwarding)
        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token),
            1000,
            address(reserve),
            ForwardingCalldataLib.X_RESERVE_REMOTE_RECIPIENT,
            REMOTE_DOMAIN_2,
            remoteToken2,
            0,
            ForwardingCalldataLib.X_RESERVE_HOOK_DATA
        );

        // Expect withdrawal events for both tokens
        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationToken1.spec))
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token2),
            2500,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken2ForDomain,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationToken2.spec))
        );

        reserve.withdraw(attestationSetPayload, signature);
    }

    function test_withdraw_succeeds_multiTokenForwarding_MixedWithAndWithoutForwarding() public {
        // Create attestations - one with forwarding, one without
        Attestation memory attestationWithForwarding = defaultAttestation;
        attestationWithForwarding.spec.sourceToken = GatewayAddressLib._addressToBytes32(address(token));
        attestationWithForwarding.spec.destinationToken = GatewayAddressLib._addressToBytes32(address(token));
        attestationWithForwarding.spec.value = 1500;
        attestationWithForwarding.spec.salt = keccak256("saltWithForwarding");
        attestationWithForwarding.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV2);

        Attestation memory attestationWithoutForwarding = defaultAttestation;
        attestationWithoutForwarding.spec.sourceToken = GatewayAddressLib._addressToBytes32(address(token2));
        attestationWithoutForwarding.spec.destinationToken = GatewayAddressLib._addressToBytes32(address(token2));
        attestationWithoutForwarding.spec.value = 3000;
        attestationWithoutForwarding.spec.salt = keccak256("saltWithoutForwarding");
        attestationWithoutForwarding.spec.hookData =
            WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataNoForwarding);

        Attestation[] memory attestations = new Attestation[](2);
        attestations[0] = attestationWithForwarding;
        attestations[1] = attestationWithoutForwarding;

        AttestationSet memory attestationSet = AttestationSet({attestations: attestations});
        bytes memory attestationSetPayload = AttestationLib.encodeAttestationSet(attestationSet);
        bytes memory signature = _signAttestation(attestationSetPayload);

        // Expect events
        // Event for attestation with hook data (forwarded)
        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1500,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationWithForwarding.spec))
        );

        // Event for attestation without hook data (not forwarded)
        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token2),
            3000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            AddressLib._bytes32ToAddressSafe(attestationWithoutForwarding.spec.destinationRecipient),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestationWithoutForwarding.spec))
        );

        reserve.withdraw(attestationSetPayload, signature);
    }

    function test_withdraw_succeeds_multiTokenForwarding_SameTokenDifferentAmounts() public {
        // Test multiple attestations for the same token but different amounts and destinations
        Attestation memory attestation1 = defaultAttestation;
        attestation1.spec.value = 1000;
        attestation1.spec.salt = keccak256("salt1");
        attestation1.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToRemoteChain);

        Attestation memory attestation2 = defaultAttestation;
        attestation2.spec.value = 2000;
        attestation2.spec.salt = keccak256("salt2");
        attestation2.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV1);

        Attestation memory attestation3 = defaultAttestation;
        attestation3.spec.value = 3000;
        attestation3.spec.salt = keccak256("salt3");
        attestation3.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToCctpV2);

        Attestation[] memory attestations = new Attestation[](3);
        attestations[0] = attestation1;
        attestations[1] = attestation2;
        attestations[2] = attestation3;

        AttestationSet memory attestationSet = AttestationSet({attestations: attestations});
        bytes memory attestationSetPayload = AttestationLib.encodeAttestationSet(attestationSet);
        bytes memory signature = _signAttestation(attestationSetPayload);

        // Expect all events with different amounts
        vm.expectEmit(true, true, true, true);
        emit DepositToRemote.DepositedToRemote(
            address(token),
            1000,
            address(reserve),
            ForwardingCalldataLib.X_RESERVE_REMOTE_RECIPIENT,
            REMOTE_DOMAIN_2,
            remoteToken2,
            0,
            ForwardingCalldataLib.X_RESERVE_HOOK_DATA
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            1000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation1.spec))
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            2000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation2.spec))
        );

        vm.expectEmit(true, true, true, true);
        emit Withdrawal.Withdrawn(
            address(token),
            3000,
            GatewayAddressLib._addressToBytes32(remoteDepositor),
            address(reserve),
            REMOTE_DOMAIN,
            remoteToken,
            keccak256(TransferSpecLib.encodeTransferSpec(attestation3.spec))
        );

        reserve.withdraw(attestationSetPayload, signature);
    }

    // ============ Withdraw Revert Tests ============
    function test_withdraw_revertsOnZeroHookDataLength() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = bytes("");
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(abi.encodeWithSelector(Withdrawal.HookDataEmpty.selector));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidFunctionSelector() public {
        Attestation memory attestation = defaultAttestation;
        WithdrawHookData memory withdrawHookData = withdrawHookDataToRemoteChain;
        withdrawHookData.forwardingCalldata = abi.encodeWithSignature(
            "invalidSelector(uint256,uint32,bytes32,address,uint256,bytes)",
            1000,
            REMOTE_DOMAIN_2,
            bytes32(uint256(uint160(user))),
            address(token),
            100,
            ""
        );
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookData);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(
            abi.encodeWithSelector(
                Withdrawal.InvalidFunctionSelector.selector,
                bytes4(keccak256("invalidSelector(uint256,uint32,bytes32,address,uint256,bytes)"))
            )
        );
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnRemoteDomainNotRegistered() public {
        // Create hook data with unregistered remote domain
        WithdrawHookData memory unregisteredDomainHookData = withdrawHookDataToRemoteChain;
        unregisteredDomainHookData.remoteDomain = 99999; // Unregistered domain
        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(unregisteredDomainHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, 99999));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnRemoteTokenNotRegistered() public {
        // Create hook data with unregistered remote token
        WithdrawHookData memory unregisteredTokenHookData = withdrawHookDataToRemoteChain;
        unregisteredTokenHookData.remoteToken = bytes32(uint256(uint160(makeAddr("unregisteredToken"))));
        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(unregisteredTokenHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(
            abi.encodeWithSelector(
                RemoteDomainRegistration.RemoteTokenNotRegistered.selector,
                REMOTE_DOMAIN,
                unregisteredTokenHookData.remoteToken
            )
        );
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidForwardingContract() public {
        // Create hook data with invalid forwarding contract
        WithdrawHookData memory invalidForwardingHookData = withdrawHookDataToRemoteChain;
        address invalidForwardingContract = makeAddr("invalidContract");
        invalidForwardingHookData.forwardingContract = GatewayAddressLib._addressToBytes32(invalidForwardingContract); // Not allowed
        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(invalidForwardingHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(
            abi.encodeWithSelector(Withdrawal.InvalidForwardingContract.selector, invalidForwardingContract)
        );
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidForwardingCalldata_EmptyCalldata() public {
        // Create hook data with empty forwarding calldata
        WithdrawHookData memory emptyCalldataHookData = withdrawHookDataToRemoteChain;
        emptyCalldataHookData.forwardingCalldata = bytes(""); // Empty calldata
        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(emptyCalldataHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(abi.encodeWithSelector(Withdrawal.ForwardingCalldataTooShort.selector, 0));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidForwardingCalldata_TooShort() public {
        // Create hook data with calldata that's too short (less than 228 bytes)
        WithdrawHookData memory shortCalldataHookData = withdrawHookDataToRemoteChain;

        // Create calldata with correct function selector but insufficient parameters (only 100 bytes total)
        // This should be less than the required 228 bytes minimum
        bytes memory shortCalldata = abi.encodePacked(
            bytes4(keccak256("depositToRemote(uint256,uint32,bytes32,address,uint256,bytes)")), // 4 bytes
            uint256(1000), // 32 bytes
            uint32(REMOTE_DOMAIN_2) // 4 bytes
                // Missing remaining parameters - total only ~40 bytes, far less than 188
        );

        shortCalldataHookData.forwardingCalldata = shortCalldata;
        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(shortCalldataHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(abi.encodeWithSelector(Withdrawal.InvalidForwardingCalldata.selector, shortCalldata));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidDestinationRecipient() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.destinationRecipient = bytes32(uint256(uint160(user)));
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToRemoteChain);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(
            abi.encodeWithSelector(Withdrawal.InvalidDestinationRecipient.selector, bytes32(uint256(uint160(user))))
        );
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidForwardingContract_NonZeroUnknownContract() public {
        // Test validation phase revert at line 429 with a non-standard forwarding contract
        address unknownContract = makeAddr("unknownForwardingContract");

        WithdrawHookData memory unknownContractHookData = withdrawHookDataToRemoteChain;
        unknownContractHookData.forwardingContract = GatewayAddressLib._addressToBytes32(unknownContract);

        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(unknownContractHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(abi.encodeWithSelector(Withdrawal.InvalidForwardingContract.selector, unknownContract));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnInvalidForwardingContract_ZeroAddress() public {
        address invalidForwardingContract = makeAddr("invalidForwardingContract");

        WithdrawHookData memory zeroAddressHookData = withdrawHookDataToRemoteChain;
        zeroAddressHookData.forwardingContract = GatewayAddressLib._addressToBytes32(invalidForwardingContract);

        bytes memory hookData = WithdrawHookDataLib.encodeWithdrawHookData(zeroAddressHookData);

        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = hookData;
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);
        vm.expectRevert(
            abi.encodeWithSelector(Withdrawal.InvalidForwardingContract.selector, invalidForwardingContract)
        );
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnDomainWithdrawalsPaused() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToRemoteChain);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        // Actually pause deposits for REMOTE_DOMAIN_2 using reserve's pausing
        vm.prank(makeAddr("domainPauser")); // Use the domain pauser for REMOTE_DOMAIN_2
        reserve.setDomainPauseState(REMOTE_DOMAIN, false, true); // pause withdrawals, allow deposits

        vm.expectRevert(abi.encodeWithSelector(Pausing.DomainWithdrawalsPaused.selector, REMOTE_DOMAIN));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnGlobalPause() public {
        Attestation memory attestation = defaultAttestation;
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(withdrawHookDataToRemoteChain);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        // Actually pause deposits for REMOTE_DOMAIN_2 instead of mocking
        vm.prank(owner); // owner can set domain manager
        reserve.pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        reserve.withdraw(attestationPayload, signature);
    }

    function test_withdraw_revertsOnRemoteDomainNotRegistered_DuringForwarding() public {
        Attestation memory attestation = defaultAttestation;
        WithdrawHookData memory unregisteredDomainHookData = withdrawHookDataToRemoteChain;
        unregisteredDomainHookData.forwardingCalldata =
            ForwardingCalldataLib.encodeXReserveDepositToRemote(1000, 999, address(token));
        attestation.spec.hookData = WithdrawHookDataLib.encodeWithdrawHookData(unregisteredDomainHookData);
        bytes memory attestationPayload = AttestationLib.encodeAttestation(attestation);
        bytes memory signature = _signAttestation(attestationPayload);

        vm.expectRevert(abi.encodeWithSelector(RemoteDomainRegistration.RemoteDomainNotRegistered.selector, 999));
        reserve.withdraw(attestationPayload, signature);
    }

    function _signAttestation(bytes memory data) private view returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(gatewayMintSignerPrivateKey, MessageHashUtils.toEthSignedMessageHash(keccak256(data)));
        signature = abi.encodePacked(r, s, v);
    }
}
