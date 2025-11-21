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

import {Test} from "forge-std/Test.sol";
import {DepositIntent, DEPOSIT_INTENT_MAGIC} from "src/lib/DepositIntent.sol";
import {DepositIntentLib} from "src/lib/DepositIntentLib.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";
import {ForkTestUtils} from "../utils/ForkTestUtils.sol";

contract DepositIntentWrapperTest is Test, DeployXReserve {
    xReserve private reserve;

    address private owner = makeAddr("owner");
    uint32 private domain;
    address private gatewayMinter;
    address private gatewayWallet;
    address private tokenMessenger;
    address private tokenMessengerV2;

    // Test constants - matching the library tests
    uint32 internal constant VERSION = 1;
    uint256 internal constant AMOUNT = 1000000; // 1 USDC
    uint32 internal constant REMOTE_DOMAIN = 2;
    bytes32 internal constant REMOTE_TOKEN = bytes32(uint256(0x456));
    bytes32 internal constant REMOTE_RECIPIENT = bytes32(uint256(0x789));
    bytes32 internal constant LOCAL_TOKEN = bytes32(uint256(uint160(0xA0b86a33E6441e8e2F4C3B9D3C9b6d2c8e8e4E4e)));
    bytes32 internal constant LOCAL_DEPOSITOR = bytes32(uint256(uint160(0x123)));
    uint256 internal constant MAX_FEE = 5000; // 0.005 USDC
    bytes32 internal constant NONCE = bytes32(uint256(0xABC));
    bytes internal constant HOOK_DATA = hex"deadbeef";

    function setUp() public {
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        gatewayMinter = forkedVars.gatewayMinter;
        gatewayWallet = forkedVars.gatewayWallet;
        tokenMessenger = forkedVars.tokenMessenger;
        tokenMessengerV2 = forkedVars.tokenMessengerV2;
        reserve = deployXReserve(owner, domain, gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);
    }

    function _mockDepositIntent() internal pure returns (DepositIntent memory) {
        return DepositIntent({
            version: VERSION,
            amount: AMOUNT,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: REMOTE_TOKEN,
            remoteRecipient: REMOTE_RECIPIENT,
            localToken: LOCAL_TOKEN,
            localDepositor: LOCAL_DEPOSITOR,
            maxFee: MAX_FEE,
            nonce: NONCE,
            hookData: HOOK_DATA
        });
    }

    function _mockDepositIntentEmptyHook() internal pure returns (DepositIntent memory) {
        return DepositIntent({
            version: VERSION,
            amount: AMOUNT,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: REMOTE_TOKEN,
            remoteRecipient: REMOTE_RECIPIENT,
            localToken: LOCAL_TOKEN,
            localDepositor: LOCAL_DEPOSITOR,
            maxFee: MAX_FEE,
            nonce: NONCE,
            hookData: ""
        });
    }

    // ============ encodeDepositIntent Tests ============

    function test_encodeDepositIntent_succeeds() public view {
        DepositIntent memory intent = _mockDepositIntent();

        bytes memory encoded = reserve.encodeDepositIntent(intent);

        // Check magic number
        bytes4 magic = bytes4(encoded);
        assertEq(magic, DEPOSIT_INTENT_MAGIC);

        // Check length (240 bytes header + 4 bytes hook data)
        assertEq(encoded.length, 244);
    }

    function test_encodeDepositIntent_emptyHookData() public view {
        DepositIntent memory intent = _mockDepositIntentEmptyHook();

        bytes memory encoded = reserve.encodeDepositIntent(intent);

        // Check magic number
        bytes4 magic = bytes4(encoded);
        assertEq(magic, DEPOSIT_INTENT_MAGIC);

        // Check length (240 bytes header + 0 bytes hook data)
        assertEq(encoded.length, 240);
    }

    function test_encodeDepositIntent_matchesLibrary() public view {
        DepositIntent memory intent = _mockDepositIntent();

        bytes memory reserveEncoded = reserve.encodeDepositIntent(intent);
        bytes memory libraryEncoded = DepositIntentLib.encodeDepositIntent(intent);

        // Should produce identical results
        assertEq(reserveEncoded, libraryEncoded);
    }

    // ============ decodeDepositIntent Tests ============

    function test_decodeDepositIntent_succeeds() public view {
        DepositIntent memory originalIntent = _mockDepositIntent();
        bytes memory encoded = reserve.encodeDepositIntent(originalIntent);

        DepositIntent memory decodedIntent = reserve.decodeDepositIntent(encoded);

        // Verify all fields match
        assertEq(decodedIntent.version, originalIntent.version);
        assertEq(decodedIntent.amount, originalIntent.amount);
        assertEq(decodedIntent.remoteDomain, originalIntent.remoteDomain);
        assertEq(decodedIntent.remoteToken, originalIntent.remoteToken);
        assertEq(decodedIntent.remoteRecipient, originalIntent.remoteRecipient);
        assertEq(decodedIntent.localToken, originalIntent.localToken);
        assertEq(decodedIntent.localDepositor, originalIntent.localDepositor);
        assertEq(decodedIntent.maxFee, originalIntent.maxFee);
        assertEq(decodedIntent.nonce, originalIntent.nonce);
        assertEq(decodedIntent.hookData, originalIntent.hookData);
    }

    function test_decodeDepositIntent_emptyHookData() public view {
        DepositIntent memory originalIntent = _mockDepositIntentEmptyHook();
        bytes memory encoded = reserve.encodeDepositIntent(originalIntent);

        DepositIntent memory decodedIntent = reserve.decodeDepositIntent(encoded);

        // Verify critical fields
        assertEq(decodedIntent.version, originalIntent.version);
        assertEq(decodedIntent.amount, originalIntent.amount);
        assertEq(decodedIntent.localToken, originalIntent.localToken);
        assertEq(decodedIntent.hookData.length, 0);
    }

    function test_decodeDepositIntent_matchesLibrary() public view {
        DepositIntent memory originalIntent = _mockDepositIntent();
        bytes memory encoded = reserve.encodeDepositIntent(originalIntent);

        DepositIntent memory reserveDecoded = reserve.decodeDepositIntent(encoded);
        DepositIntent memory libraryDecoded = DepositIntentLib.decodeDepositIntent(encoded);

        // Should produce identical results
        assertEq(reserveDecoded.version, libraryDecoded.version);
        assertEq(reserveDecoded.amount, libraryDecoded.amount);
        assertEq(reserveDecoded.remoteDomain, libraryDecoded.remoteDomain);
        assertEq(reserveDecoded.remoteToken, libraryDecoded.remoteToken);
        assertEq(reserveDecoded.remoteRecipient, libraryDecoded.remoteRecipient);
        assertEq(reserveDecoded.localToken, libraryDecoded.localToken);
        assertEq(reserveDecoded.localDepositor, libraryDecoded.localDepositor);
        assertEq(reserveDecoded.maxFee, libraryDecoded.maxFee);
        assertEq(reserveDecoded.nonce, libraryDecoded.nonce);
        assertEq(reserveDecoded.hookData, libraryDecoded.hookData);
    }

    // ============ Round Trip Tests ============

    function test_roundTrip_depositIntent() public view {
        DepositIntent memory originalIntent = _mockDepositIntent();

        // Encode then decode
        bytes memory encoded = reserve.encodeDepositIntent(originalIntent);
        DepositIntent memory decodedIntent = reserve.decodeDepositIntent(encoded);

        // Should be identical
        assertEq(decodedIntent.version, originalIntent.version);
        assertEq(decodedIntent.amount, originalIntent.amount);
        assertEq(decodedIntent.remoteDomain, originalIntent.remoteDomain);
        assertEq(decodedIntent.remoteToken, originalIntent.remoteToken);
        assertEq(decodedIntent.remoteRecipient, originalIntent.remoteRecipient);
        assertEq(decodedIntent.localToken, originalIntent.localToken);
        assertEq(decodedIntent.localDepositor, originalIntent.localDepositor);
        assertEq(decodedIntent.maxFee, originalIntent.maxFee);
        assertEq(decodedIntent.nonce, originalIntent.nonce);
        assertEq(decodedIntent.hookData, originalIntent.hookData);
    }

    function test_roundTrip_emptyHookData() public view {
        DepositIntent memory originalIntent = _mockDepositIntentEmptyHook();

        // Encode then decode
        bytes memory encoded = reserve.encodeDepositIntent(originalIntent);
        DepositIntent memory decodedIntent = reserve.decodeDepositIntent(encoded);

        // Should be identical
        assertEq(decodedIntent.version, originalIntent.version);
        assertEq(decodedIntent.amount, originalIntent.amount);
        assertEq(decodedIntent.localToken, originalIntent.localToken);
        assertEq(decodedIntent.hookData.length, 0);
    }
}
