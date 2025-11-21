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
import {ForwardingCalldataLib} from "./../utils/ForwardingCalldataLib.sol";
import {XReserveMultichainTestUtils} from "./../utils/XReserveMultichainTestUtils.sol";

/// @title UnexpectedStuckFundsFlowTest
/// @dev Integration tests covering scenarios where funds may unintentionally become stuck:
///      1. Users direct deposits to a `GatewayWallet` at a `RemoteDomainDepositor` address,
///         bypassing the intended `xReserve.depositToRemote` entrypoint.
///      2. Setting `xReserve` as the recipient for a standard withdrawal,
///         resulting in funds being minted directly to the reserve contract.
///      3. Setting `xReserve` as the recipient for a forwarded withdrawal,
///         but forwarding less than the minted amount, leaving residual funds in the reserve contract.
///      - Scenario (1) is difficult to prevent due to the permissionless nature of deposits.
///      - For (2) and (3), Circle's offchain services are expected to reject requests that
///        either direct funds to the reserve, OR if the forwarded amount does not match the minted amount.
///      - While on-chain enforcement is possible, it is costly. Therefore we opt to not enforce these cases onchain.
///        The test cases are included here for completeness and demonstrate these are expected behaviors.
contract UnexpectedStuckFundsFlowTest is XReserveMultichainTestUtils {
    using MessageHashUtils for bytes32;

    // Test addresses and keys
    address public depositor = makeAddr("depositor");

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

    function test_depositMisdirectedFunds_succeedsAndLeadsToSuccessfulBurns() public {
        // ============ STEP 1: User deposits funds into GatewayWallet under the RemoteDomainDepositor address ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        vm.startPrank(depositor);
        {
            ethereum.usdc.approve(address(ethereum.gatewayWallet), DEPOSIT_TO_REMOTE_AMOUNT);
            ethereum.gatewayWallet.depositFor(address(ethereum.usdc), remoteDomainDepositor, DEPOSIT_TO_REMOTE_AMOUNT);
        }
        assertEq(
            ethereum.gatewayWallet.availableBalance(address(ethereum.usdc), remoteDomainDepositor),
            DEPOSIT_TO_REMOTE_AMOUNT
        );
        assertEq(
            ethereum.reserve.balanceOfNativeCollateral(address(ethereum.usdc), REMOTE_DOMAIN_ID),
            DEPOSIT_TO_REMOTE_AMOUNT
        );

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntents[0] = burnIntent;
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        // NOTE: Attestation succeeds here even though no additional funds were deposited into GatewayWallet.
        //       This should be prevented by Circle's offchain services.
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.reserve.withdraw(encodedAttestations, attestationSignature);

        // ============ STEP 4: Funds are burnt on the Ethereum ============
        // NOTE: Burn succeeds here even though no additional funds were deposited into GatewayWallet.
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }

    function test_depositAndWithdrawWithXReserveAsRecipient_succeedsAndLeavesFundsInTheReserve() public {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntents[0] = burnIntent;
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        // NOTE: Attestation succeeds here and causes funds to be minted to the reserve contract.
        //       This should be prevented by Circle's offchain services.
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.reserve.withdraw(encodedAttestations, attestationSignature);
        assertEq(ethereum.usdc.balanceOf(address(ethereum.reserve)), DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE);

        // ============ STEP 4: Funds are burnt on the Ethereum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }

    function test_depositAndWithdrawWithForwarding_whenForwardedAmountIsLessThanMintedAmount_succeedsAndLeavesFundsInTheReserve(
    ) public {
        // ============ STEP 1: User deposit USDC on Ethereum ============
        _depositToRemote(ethereum, depositor, DEPOSIT_TO_REMOTE_AMOUNT);

        // ============ STEP 2: User creates and signs BurnIntent with WithdrawHookData to release funds on Ethereum ============
        uint256 forwardAmount = 1; // Amount to forward - less than the minted amount
        address remoteDomainDepositor = ethereum.reserve.getRemoteDomainDepositor(REMOTE_DOMAIN_ID);
        BurnIntent[] memory burnIntents = new BurnIntent[](1);
        BurnIntent memory burnIntent = _createBurnIntent(
            ethereum, ethereum, remoteDomainDepositor, address(ethereum.reserve), DEPOSIT_TO_REMOTE_AMOUNT
        );
        burnIntent.spec.hookData = _createWithdrawHookData(
            address(ethereum.tokenMessenger),
            ForwardingCalldataLib.encodeCCTPV1DepositForBurn(forwardAmount, address(ethereum.usdc))
        );
        burnIntent.spec.destinationCaller = GatewayAddressLib._addressToBytes32(address(ethereum.reserve));
        burnIntents[0] = burnIntent;
        (bytes memory encodedBurnIntents, bytes memory burnSignature) =
            _signBurnIntentsMultiAttester(ethereum, burnIntents);

        // ============ STEP 3: User uses GatewayMinter to mint with attestation on Ethereum ============
        TransferSpec[] memory transferSpecs = new TransferSpec[](1);
        transferSpecs[0] = burnIntents[0].spec;
        // NOTE: Attestation succeeds here and causes funds to be minted to the reserve contract.
        //       This should be prevented by Circle's offchain services.
        (bytes memory encodedAttestations, bytes memory attestationSignature) =
            _signAttestationWithTransferSpecs(transferSpecs, ethereum.attestationSignerKey);
        ethereum.reserve.withdraw(encodedAttestations, attestationSignature);
        assertEq(
            ethereum.usdc.balanceOf(address(ethereum.reserve)),
            DEPOSIT_TO_REMOTE_AMOUNT - WITHDRAWAL_MAX_FEE - forwardAmount
        );

        // ============ STEP 4: Funds are burnt on the Ethereum ============
        _burnFromChain(ethereum, encodedBurnIntents, burnSignature);
    }
}
