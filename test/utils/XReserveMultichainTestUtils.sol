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
import {TokenMessengerV2} from "@cctp/v2/TokenMessengerV2.sol";
import {GatewayMinter} from "@gateway/src/GatewayMinter.sol";
import {GatewayWallet} from "@gateway/src/GatewayWallet.sol";
import {AddressLib} from "@gateway/src/lib/AddressLib.sol";
import {AttestationLib} from "@gateway/src/lib/AttestationLib.sol";
import {Attestation, AttestationSet} from "@gateway/src/lib/Attestations.sol";
import {BurnIntentLib} from "@gateway/src/lib/BurnIntentLib.sol";
import {BurnIntent, BurnIntentSet} from "@gateway/src/lib/BurnIntents.sol";
import {TransferSpec} from "@gateway/src/lib/TransferSpec.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {WithdrawHookData} from "./../../src/lib/WithdrawHookData.sol";
import {WithdrawHookDataLib} from "./../../src/lib/WithdrawHookDataLib.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "./DeployXReserve.sol";
import {ForkTestUtils} from "./ForkTestUtils.sol";

contract XReserveMultichainTestUtils is DeployXReserve {
    using MessageHashUtils for bytes32;

    // Additional test constants specific to xReserve
    uint256 public constant DEPOSIT_TO_REMOTE_AMOUNT = 800e6; // 800 USDC to reserve
    uint256 public constant DEPOSIT_MAX_FEE = 1e6; // 10 USDC max fee
    uint256 public constant WITHDRAWAL_MAX_FEE = 10e6; // 10 USDC max fee
    bytes public constant DEPOSIT_TO_REMOTE_HOOK_DATA = "Reserve test hook data";
    uint32 public constant REMOTE_DOMAIN_ID = 10001;
    bytes32 public constant REMOTE_TOKEN_ADDRESS = 0xe0d50200e150e70cb83af4a6c04668c71a9bf162798f7bf4c9300d4acde150cc;
    bytes32 public constant REMOTE_RECIPIENT = 0xc0d50200e150e70cb83af4a6c04668c71a9bf162798f7bf4c9300d4acde150cc;
    uint256 public constant REMOTE_CHAIN_SIGNATURE_THRESHOLD = 2;
    uint256 public constant REMOTE_CHAIN_PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS = (7 * 24 * 60 * 60) / 12; // 7 days

    struct ReserveSetup {
        uint256 forkId;
        uint32 domain;
        uint256 burnSignerKey;
        uint256 attestationSignerKey;
        address[] attesters;
        uint256 attester1Key;
        uint256 attester2Key;
        xReserve reserve;
        FiatTokenV2_2 usdc;
        GatewayWallet gatewayWallet;
        GatewayMinter gatewayMinter;
        TokenMessenger tokenMessenger;
        TokenMessengerV2 tokenMessengerV2;
    }

    struct Roles {
        address owner;
        uint256 burnSignerKey;
        uint256 attestationSignerKey;
        address attesterManager;
        address[] attesters;
        uint256 attester1Key;
        uint256 attester2Key;
    }

    function _initializeReserveContracts(string memory chainName) internal returns (ReserveSetup memory) {
        // Create and select fork for specified chain
        uint256 forkId = vm.createFork(vm.rpcUrl(chainName));
        vm.selectFork(forkId);

        FiatTokenV2_2 usdc = FiatTokenV2_2(ForkTestUtils.forkVars().usdc);
        uint32 domain = ForkTestUtils.forkVars().domain;
        TokenMessenger tokenMessenger = TokenMessenger(ForkTestUtils.forkVars().tokenMessenger);
        TokenMessengerV2 tokenMessengerV2 = TokenMessengerV2(ForkTestUtils.forkVars().tokenMessengerV2);
        GatewayWallet gatewayWallet = GatewayWallet(ForkTestUtils.forkVars().gatewayWallet);
        GatewayMinter gatewayMinter = GatewayMinter(ForkTestUtils.forkVars().gatewayMinter);

        // Generate unique role addresses for the reserve contracts
        Roles memory roles = _setupReserveVariables(forkId);

        // Deploy xReserve with all required dependencies
        xReserve reserve = deployXReserve(
            roles.owner,
            domain,
            address(gatewayMinter),
            address(gatewayWallet),
            address(tokenMessenger),
            address(tokenMessengerV2)
        );

        // Upgrade gateway wallet to a new implementation and update the burn signer and contract signers allowlister
        vm.startPrank(gatewayWallet.owner());
        {
            GatewayWallet newGatewayWalletImpl = new GatewayWallet();
            gatewayWallet.upgradeToAndCall(address(newGatewayWalletImpl), bytes(""));
            gatewayWallet.updateContractSignersAllowlister(makeAddr("contractSignersAllowlister"));
            gatewayWallet.addBurnSigner(vm.addr(roles.burnSignerKey));
        }
        vm.stopPrank();

        // Update attestation signer on the gateway minter
        vm.prank(gatewayMinter.owner());
        gatewayMinter.addAttestationSigner(vm.addr(roles.attestationSignerKey));

        address remoteDomainDepositor;
        vm.startPrank(roles.owner);
        {
            address[] memory supportedTokens = new address[](1);
            supportedTokens[0] = address(usdc);

            // Register a remote domain for testing
            reserve.addSupportedToken(address(usdc));
            address domainManager = vm.addr(777 + block.chainid);
            address domainPauser = vm.addr(777 + block.chainid);
            // Use consistent attesters for the same remote domain across all chains
            address[] memory remoteAttesters = new address[](2);
            remoteAttesters[0] = vm.addr(777); // Same as attester1Key
            remoteAttesters[1] = vm.addr(888); // Same as attester2Key
            remoteDomainDepositor = reserve.registerRemoteDomain(
                REMOTE_DOMAIN_ID,
                domainManager,
                domainPauser,
                remoteAttesters,
                REMOTE_CHAIN_SIGNATURE_THRESHOLD,
                REMOTE_CHAIN_PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS,
                address(0)
            );
            reserve.registerRemoteToken(address(usdc), REMOTE_DOMAIN_ID, REMOTE_TOKEN_ADDRESS);
            // Note: Don't make remoteDomainDepositor persistent to avoid CREATE2 collisions
        }
        vm.stopPrank();

        vm.prank(gatewayWallet.contractSignersAllowlister());
        gatewayWallet.allowlistContractSigner(remoteDomainDepositor);

        vm.prank(usdc.masterMinter());
        usdc.configureMinter(address(gatewayMinter), type(uint256).max);

        return ReserveSetup({
            forkId: forkId,
            domain: domain,
            burnSignerKey: roles.burnSignerKey,
            attestationSignerKey: roles.attestationSignerKey,
            attesters: roles.attesters,
            attester1Key: roles.attester1Key,
            attester2Key: roles.attester2Key,
            reserve: reserve,
            usdc: usdc,
            gatewayWallet: gatewayWallet,
            gatewayMinter: gatewayMinter,
            tokenMessenger: tokenMessenger,
            tokenMessengerV2: tokenMessengerV2
        });
    }

    function _setupReserveVariables(uint256 forkId) internal returns (Roles memory) {
        vm.selectFork(forkId);

        uint256 chainId = block.chainid;
        address owner = makeAddr("owner");
        address attesterManager = vm.addr(chainId + 2);
        uint256 attester1Key = 777; // Use static keys multi-chain signing
        uint256 attester2Key = 888; // Use static keys multi-chain signing
        address[] memory attesters = new address[](2);
        attesters[0] = vm.addr(attester1Key);
        attesters[1] = vm.addr(attester2Key);
        uint256 burnSignerKey = vm.randomUint();
        uint256 attestationSignerKey = vm.randomUint();

        return Roles({
            owner: owner,
            burnSignerKey: burnSignerKey,
            attestationSignerKey: attestationSignerKey,
            attesterManager: attesterManager,
            attesters: attesters,
            attester1Key: attester1Key,
            attester2Key: attester2Key
        });
    }

    /// @dev Deposits tokens to the xReserve and verifies the state of the reserve
    /// @param chain The reserve setup for the chain
    /// @param depositor_ The address making the deposit
    /// @param amount_ The amount to deposit
    function _depositToRemote(ReserveSetup memory chain, address depositor_, uint256 amount_) internal {
        vm.selectFork(chain.forkId);
        deal(address(chain.usdc), depositor_, amount_);

        uint256 initialDepositorBalance = chain.usdc.balanceOf(depositor_);
        uint256 initialGatewayBalance = chain.usdc.balanceOf(address(chain.gatewayWallet));
        uint256 initialRemoteDomainDepositorBalance =
            chain.reserve.balanceOfNativeCollateral(address(chain.usdc), REMOTE_DOMAIN_ID);

        vm.startPrank(depositor_);
        {
            chain.usdc.approve(address(chain.reserve), amount_);

            // Simple deposit without reserving
            chain.reserve.depositToRemote(
                DEPOSIT_TO_REMOTE_AMOUNT,
                REMOTE_DOMAIN_ID,
                REMOTE_RECIPIENT,
                address(chain.usdc),
                DEPOSIT_MAX_FEE,
                DEPOSIT_TO_REMOTE_HOOK_DATA
            );
        }
        vm.stopPrank();

        assertEq(chain.usdc.balanceOf(depositor_), initialDepositorBalance - amount_);
        assertEq(chain.usdc.balanceOf(address(chain.gatewayWallet)), initialGatewayBalance + amount_);
        assertEq(
            chain.reserve.balanceOfNativeCollateral(address(chain.usdc), REMOTE_DOMAIN_ID),
            initialRemoteDomainDepositorBalance + amount_
        );
    }

    function _createBurnIntent(
        ReserveSetup memory sourceReserveSetup,
        ReserveSetup memory destReserveSetup,
        address depositor_,
        address recipient_,
        uint256 amount_
    ) internal returns (BurnIntent memory) {
        vm.selectFork(sourceReserveSetup.forkId);
        return BurnIntent({
            maxBlockHeight: block.number + 1000,
            maxFee: WITHDRAWAL_MAX_FEE,
            spec: _createTransferSpec(
                sourceReserveSetup, destReserveSetup, amount_ - WITHDRAWAL_MAX_FEE, depositor_, recipient_
            )
        });
    }

    function _createTransferSpec(
        ReserveSetup memory sourceChain,
        ReserveSetup memory destChain,
        uint256 amount,
        address depositor_,
        address recipient_
    ) internal returns (TransferSpec memory) {
        return TransferSpec({
            version: 1,
            sourceDomain: sourceChain.domain,
            destinationDomain: destChain.domain,
            sourceContract: AddressLib._addressToBytes32(address(sourceChain.gatewayWallet)),
            destinationContract: AddressLib._addressToBytes32(address(destChain.gatewayMinter)),
            sourceToken: AddressLib._addressToBytes32(address(sourceChain.usdc)),
            destinationToken: AddressLib._addressToBytes32(address(destChain.usdc)),
            sourceDepositor: AddressLib._addressToBytes32(depositor_),
            destinationRecipient: AddressLib._addressToBytes32(recipient_),
            sourceSigner: AddressLib._addressToBytes32(depositor_),
            destinationCaller: AddressLib._addressToBytes32(address(0)),
            value: amount,
            salt: keccak256(abi.encode(vm.randomUint())),
            hookData: _createWithdrawHookData(address(0), bytes(""))
        });
    }

    function _createWithdrawHookData(address forwardingContract, bytes memory forwardingCalldata)
        internal
        pure
        returns (bytes memory hookData)
    {
        WithdrawHookData memory withdrawData = WithdrawHookData({
            version: 1,
            remoteDomain: REMOTE_DOMAIN_ID,
            remoteToken: REMOTE_TOKEN_ADDRESS,
            remoteDepositor: REMOTE_RECIPIENT,
            forwardingContract: AddressLib._addressToBytes32(forwardingContract),
            forwardingCalldata: forwardingCalldata
        });
        return WithdrawHookDataLib.encodeWithdrawHookData(withdrawData);
    }

    function _signBurnIntentsMultiAttester(ReserveSetup memory reserveSetup, BurnIntent[] memory intents)
        internal
        view
        returns (bytes memory encodedIntent, bytes memory signature)
    {
        encodedIntent = intents.length == 1
            ? BurnIntentLib.encodeBurnIntent(intents[0])
            : BurnIntentLib.encodeBurnIntentSet(BurnIntentSet({intents: intents}));
        // Use the gateway wallet's domain separator, not USDC's domain separator
        bytes32 domainSeparator = reserveSetup.gatewayWallet.domainSeparator();
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(domainSeparator, BurnIntentLib.getTypedDataHash(encodedIntent));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(reserveSetup.attester1Key, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(reserveSetup.attester2Key, digest);
        // Signatures must be in ascending order of attester addresses
        // attester1: 0x7121207b118bbacf0340a989527474bd4495c3c6 (key 777)
        // attester2: 0x440d9ab59a4ed2f575666c23ef8c17c53a96e3e0 (key 888)
        // Since attester2 address < attester1 address, put attester2 signature first
        signature = abi.encodePacked(r2, s2, v2, r1, s1, v1);
        assertEq(signature.length, 65 * 2);
    }

    function _burnFromChain(ReserveSetup memory chain, bytes memory encodedBurnAuth, bytes memory burnSignature)
        internal
    {
        bytes[] memory allBurnAuths = new bytes[](1);
        allBurnAuths[0] = encodedBurnAuth;
        bytes[] memory allSignatures = new bytes[](1);
        allSignatures[0] = burnSignature;
        uint256[][] memory fees = _createFees(allBurnAuths, WITHDRAWAL_MAX_FEE);

        vm.selectFork(chain.forkId);

        // Record state before burn
        uint256 totalBalanceBefore = chain.reserve.balanceOfNativeCollateral(address(chain.usdc), REMOTE_DOMAIN_ID);

        // Execute burn operation
        bytes memory burnSignerSignature = _signBurnIntents(allBurnAuths, allSignatures, fees, chain.burnSignerKey);
        assertEq(burnSignerSignature.length, 65);
        chain.gatewayWallet.gatewayBurn(abi.encode(allBurnAuths, allSignatures, fees), burnSignerSignature);

        // Verify state after burn
        assertEq(
            chain.reserve.balanceOfNativeCollateral(address(chain.usdc), REMOTE_DOMAIN_ID),
            totalBalanceBefore - DEPOSIT_TO_REMOTE_AMOUNT
        );
    }

    function _createFees(bytes[] memory encodedBurnAuths, uint256 feeAmount)
        internal
        pure
        returns (uint256[][] memory fees)
    {
        uint256 n = encodedBurnAuths.length;

        fees = new uint256[][](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 m = BurnIntentLib.cursor(encodedBurnAuths[i]).numElements;
            fees[i] = new uint256[](m);
            for (uint256 j = 0; j < m; j++) {
                fees[i][j] = feeAmount;
            }
        }
    }

    function _signBurnIntents(
        bytes[] memory intents,
        bytes[] memory signatures,
        uint256[][] memory fees,
        uint256 signerKey
    ) internal pure returns (bytes memory burnerSignature) {
        // Generate a random address and key for the burn signer
        bytes memory encodedCalldata = abi.encode(intents, signatures, fees);

        // Sign the calldata hash as the burn signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, keccak256(encodedCalldata).toEthSignedMessageHash());
        burnerSignature = abi.encodePacked(r, s, v);
    }

    function _signAttestationWithTransferSpecs(TransferSpec[] memory transferSpecs, uint256 signerKey)
        internal
        view
        returns (bytes memory encodedAttestation, bytes memory signature)
    {
        Attestation[] memory attestations = new Attestation[](transferSpecs.length);
        for (uint256 i = 0; i < transferSpecs.length; i++) {
            attestations[i] = Attestation({maxBlockHeight: block.number + 1000, spec: transferSpecs[i]});
        }
        return _signAttestations(attestations, signerKey);
    }

    function _signAttestations(Attestation[] memory attestations, uint256 signerKey)
        private
        pure
        returns (bytes memory encodedAttestation, bytes memory signature)
    {
        if (attestations.length == 1) {
            encodedAttestation = AttestationLib.encodeAttestation(attestations[0]);
        } else {
            AttestationSet memory attestationSet = AttestationSet({attestations: attestations});
            encodedAttestation = AttestationLib.encodeAttestationSet(attestationSet);
        }
        signature = _sign(signerKey, encodedAttestation);
    }

    function _sign(uint256 signerKey, bytes memory data) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, keccak256(data).toEthSignedMessageHash());
        signature = abi.encodePacked(r, s, v);
    }
}
