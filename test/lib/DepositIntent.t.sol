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
import {TypedMemView} from "@memview-sol/TypedMemView.sol";
import {Test} from "forge-std/Test.sol";
import {UINT32_BYTES} from "src/common/Constants.sol";
import {ZeroBytes32} from "src/common/Errors.sol";
import {DepositIntent, DEPOSIT_INTENT_MAGIC, DEPOSIT_INTENT_HOOK_DATA_LENGTH_OFFSET} from "src/lib/DepositIntent.sol";
import {DepositIntentLib} from "src/lib/DepositIntentLib.sol";

contract DepositIntentTest is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // Test constants
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

    bytes internal constant LONG_HOOK_DATA = "This is a longer hook data string to test larger hook data payloads";

    /// @notice Helper function to clone bytes array
    function cloneBytes(bytes memory source) internal pure returns (bytes memory target) {
        target = new bytes(source.length);
        for (uint256 i = 0; i < source.length; i++) {
            target[i] = source[i];
        }
    }

    /// @notice Helper function to create corrupted hook data length - similar to TransferSpec test utils
    function _getCorruptedHookDataLengthData(
        bytes memory encodedIntent,
        uint32 originalHookDataLength,
        bool makeLengthBigger
    ) internal pure returns (bytes memory corruptedData, uint32 corruptedHookDataLength) {
        uint256 hookDataLengthOffset = DEPOSIT_INTENT_HOOK_DATA_LENGTH_OFFSET;
        corruptedData = cloneBytes(encodedIntent);

        if (makeLengthBigger) {
            corruptedHookDataLength = originalHookDataLength * 2;
        } else {
            corruptedHookDataLength = originalHookDataLength / 2;
        }

        bytes memory encodedInvalidLength = abi.encodePacked(corruptedHookDataLength);
        for (uint8 i = 0; i < UINT32_BYTES; i++) {
            corruptedData[hookDataLengthOffset + i] = encodedInvalidLength[i];
        }

        return (corruptedData, corruptedHookDataLength);
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

    // ===== Encoding Tests =====

    function test_encodeDepositIntent_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        // Check magic
        bytes4 magic = bytes4(encoded);
        assertEq(magic, DEPOSIT_INTENT_MAGIC);

        // Basic length check (240 bytes for header + 4 bytes hook data)
        assertEq(encoded.length, 244);
    }

    function test_encodeDepositIntent_emptyHookData() public pure {
        DepositIntent memory intent = _mockDepositIntentEmptyHook();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        // Check magic
        bytes4 magic = bytes4(encoded);
        assertEq(magic, DEPOSIT_INTENT_MAGIC);

        // Basic length check (240 bytes for header + 0 bytes hook data)
        assertEq(encoded.length, 240);
    }

    // ===== Decoding Tests =====

    function test_decodeDepositIntent_succeeds() public view {
        DepositIntent memory originalIntent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(originalIntent);

        DepositIntent memory decodedIntent = DepositIntentLib.decodeDepositIntent(encoded);

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
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(originalIntent);

        DepositIntent memory decodedIntent = DepositIntentLib.decodeDepositIntent(encoded);

        assertEq(decodedIntent.hookData.length, 0);
        assertEq(decodedIntent.amount, originalIntent.amount);
    }

    // ===== Round-trip Tests =====

    function test_roundTrip_depositIntent() public view {
        DepositIntent memory originalIntent = _mockDepositIntent();

        bytes memory encoded = DepositIntentLib.encodeDepositIntent(originalIntent);
        DepositIntent memory decodedIntent = DepositIntentLib.decodeDepositIntent(encoded);

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

    // ===== Field Accessor Tests =====

    function test_getVersion_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        uint32 version = DepositIntentLib.getVersion(intentView);
        assertEq(version, VERSION);
    }

    function test_getAmount_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        uint256 amount = DepositIntentLib.getAmount(intentView);
        assertEq(amount, AMOUNT);
    }

    function test_getRemoteDomain_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        uint32 remoteDomain = DepositIntentLib.getRemoteDomain(intentView);
        assertEq(remoteDomain, REMOTE_DOMAIN);
    }

    function test_getRemoteToken_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes32 remoteToken = DepositIntentLib.getRemoteToken(intentView);
        assertEq(remoteToken, REMOTE_TOKEN);
    }

    function test_getRemoteRecipient_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes32 remoteRecipient = DepositIntentLib.getRemoteRecipient(intentView);
        assertEq(remoteRecipient, REMOTE_RECIPIENT);
    }

    function test_getLocalToken_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes32 localToken = DepositIntentLib.getLocalToken(intentView);
        assertEq(localToken, LOCAL_TOKEN);
    }

    function test_getLocalDepositor_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes32 localDepositor = DepositIntentLib.getLocalDepositor(intentView);
        assertEq(localDepositor, LOCAL_DEPOSITOR);
    }

    function test_getMaxFee_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        uint256 maxFee = DepositIntentLib.getMaxFee(intentView);
        assertEq(maxFee, MAX_FEE);
    }

    function test_getNonce_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes32 nonce = DepositIntentLib.getNonce(intentView);
        assertEq(nonce, NONCE);
    }

    function test_getHookDataLength_succeeds() public pure {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        uint32 hookDataLength = DepositIntentLib.getHookDataLength(intentView);
        assertEq(hookDataLength, HOOK_DATA.length);
    }

    function test_getHookData_succeeds() public view {
        DepositIntent memory intent = _mockDepositIntent();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes memory hookData = DepositIntentLib.getHookData(intentView);
        assertEq(hookData, HOOK_DATA);
    }

    function test_getHookData_handlesEmptyData() public view {
        DepositIntent memory intent = _mockDepositIntentEmptyHook();
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        bytes memory hookData = DepositIntentLib.getHookData(intentView);
        assertEq(hookData.length, 0);
    }

    // ===== Validation Tests =====

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeDepositIntent_revertsOnDataTooShort() public {
        bytes memory shortData = hex"123456";

        vm.expectRevert(
            abi.encodeWithSelector(DepositIntentLib.DepositPayloadDataTooShort.selector, 4, shortData.length)
        );
        DepositIntentLib.decodeDepositIntent(shortData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeDepositIntent_revertsOnInvalidMagic() public {
        // Create data with wrong magic but correct length
        bytes memory invalidMagicData = new bytes(244);
        // Set wrong magic
        invalidMagicData[0] = 0x12;
        invalidMagicData[1] = 0x34;
        invalidMagicData[2] = 0x56;
        invalidMagicData[3] = 0x78;

        vm.expectRevert(
            abi.encodeWithSelector(DepositIntentLib.InvalidDepositPayloadMagic.selector, bytes4(0x12345678))
        );
        DepositIntentLib.decodeDepositIntent(invalidMagicData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validateDepositIntent_revertsOnHeaderTooShort() public {
        // Create malformed data with correct magic but too short for header
        bytes memory malformedData = abi.encodePacked(DEPOSIT_INTENT_MAGIC, uint32(1)); // Only 8 bytes total

        vm.expectRevert(abi.encodeWithSelector(DepositIntentLib.DepositPayloadHeaderTooShort.selector, 240, 8));
        DepositIntentLib.decodeDepositIntent(malformedData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validateDepositIntent_revertsOnLengthMismatch() public {
        // Create intent with hook data length that doesn't match actual data
        bytes memory baseData = abi.encodePacked(
            DEPOSIT_INTENT_MAGIC,
            VERSION,
            AMOUNT,
            REMOTE_DOMAIN,
            REMOTE_TOKEN,
            REMOTE_RECIPIENT,
            LOCAL_TOKEN,
            LOCAL_DEPOSITOR,
            MAX_FEE,
            NONCE,
            uint32(10)
        );
        // Only provide 4 bytes of hook data instead of claimed 10
        bytes memory malformedIntent = abi.encodePacked(baseData, hex"deadbeef");

        vm.expectRevert(abi.encodeWithSelector(DepositIntentLib.DepositPayloadOverallLengthMismatch.selector, 250, 244));
        DepositIntentLib.decodeDepositIntent(malformedIntent);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeDepositIntent_revertsOnInvalidVersion() public {
        DepositIntent memory intent = _mockDepositIntent();
        intent.version = 2; // Invalid version
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(DepositIntentLib.InvalidDepositIntentVersion.selector, 2));
        DepositIntentLib.decodeDepositIntent(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeDepositIntent_revertsOnZeroAmount() public {
        DepositIntent memory intent = _mockDepositIntent();
        intent.amount = 0;
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(DepositIntentLib.InvalidDepositAmount.selector, 0));
        DepositIntentLib.decodeDepositIntent(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeDepositIntent_revertsOnZeroLocalToken() public {
        DepositIntent memory intent = _mockDepositIntent();
        intent.localToken = bytes32(0);
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(ZeroBytes32.selector));
        DepositIntentLib.decodeDepositIntent(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeDepositIntent_revertsOnZeroLocalDepositor() public {
        DepositIntent memory intent = _mockDepositIntent();
        intent.localDepositor = bytes32(0);
        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(ZeroBytes32.selector));
        DepositIntentLib.decodeDepositIntent(encoded);
    }

    // ===== Fuzz Tests =====

    function testFuzz_roundTrip_depositIntent(
        uint256 amount,
        uint32 remoteDomain,
        bytes32 remoteToken,
        bytes32 remoteRecipient,
        address localToken,
        address localDepositor,
        uint256 maxFee,
        bytes32 nonce,
        bytes memory hookData
    ) public view {
        // Skip zero addresses and zero amount
        vm.assume(localToken != address(0));
        vm.assume(localDepositor != address(0));
        vm.assume(amount > 0);

        DepositIntent memory originalIntent = DepositIntent({
            version: 1,
            amount: amount,
            remoteDomain: remoteDomain,
            remoteToken: remoteToken,
            remoteRecipient: remoteRecipient,
            localToken: GatewayAddressLib._addressToBytes32(localToken),
            localDepositor: GatewayAddressLib._addressToBytes32(localDepositor),
            maxFee: maxFee,
            nonce: nonce,
            hookData: hookData
        });

        bytes memory encoded = DepositIntentLib.encodeDepositIntent(originalIntent);
        DepositIntent memory decodedIntent = DepositIntentLib.decodeDepositIntent(encoded);

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

    function testFuzz_fieldAccessors_consistentWithStruct(
        uint256 amount,
        uint32 remoteDomain,
        bytes32 remoteToken,
        address localToken,
        uint256 maxFee
    ) public view {
        // Skip zero addresses and zero amount
        vm.assume(localToken != address(0));
        vm.assume(amount > 0);

        DepositIntent memory intent = DepositIntent({
            version: 1,
            amount: amount,
            remoteDomain: remoteDomain,
            remoteToken: remoteToken,
            remoteRecipient: REMOTE_RECIPIENT,
            localToken: GatewayAddressLib._addressToBytes32(localToken),
            localDepositor: LOCAL_DEPOSITOR,
            maxFee: maxFee,
            nonce: NONCE,
            hookData: HOOK_DATA
        });

        bytes memory encoded = DepositIntentLib.encodeDepositIntent(intent);
        bytes29 intentView = encoded.ref(0);

        // Test that field accessors return the same values as the struct
        assertEq(DepositIntentLib.getVersion(intentView), intent.version);
        assertEq(DepositIntentLib.getAmount(intentView), intent.amount);
        assertEq(DepositIntentLib.getRemoteDomain(intentView), intent.remoteDomain);
        assertEq(DepositIntentLib.getRemoteToken(intentView), intent.remoteToken);
        assertEq(DepositIntentLib.getRemoteRecipient(intentView), intent.remoteRecipient);
        assertEq(DepositIntentLib.getLocalToken(intentView), intent.localToken);
        assertEq(DepositIntentLib.getLocalDepositor(intentView), intent.localDepositor);
        assertEq(DepositIntentLib.getMaxFee(intentView), intent.maxFee);
        assertEq(DepositIntentLib.getNonce(intentView), intent.nonce);
        assertEq(DepositIntentLib.getHookDataLength(intentView), intent.hookData.length);
        assertEq(DepositIntentLib.getHookData(intentView), intent.hookData);
    }

    // ===== NULL Check Tests =====

    /// forge-config: default.allow_internal_expect_revert = true
    /// @notice Test that getHookData reverts with InvalidDepositIntentHookData when slice returns NULL
    function test_getHookData_revertsOnInvalidHookData() public {
        DepositIntent memory intent = DepositIntent({
            version: VERSION,
            amount: AMOUNT,
            remoteDomain: REMOTE_DOMAIN,
            remoteToken: REMOTE_TOKEN,
            remoteRecipient: REMOTE_RECIPIENT,
            localToken: LOCAL_TOKEN,
            localDepositor: LOCAL_DEPOSITOR,
            maxFee: MAX_FEE,
            nonce: NONCE,
            hookData: LONG_HOOK_DATA
        });

        bytes memory encodedIntent = DepositIntentLib.encodeDepositIntent(intent);

        (bytes memory corruptedData, uint32 corruptedHookDataLength) =
            _getCorruptedHookDataLengthData(encodedIntent, uint32(LONG_HOOK_DATA.length), true);
        bytes29 corruptedRef = corruptedData.ref(uint40(uint32(DEPOSIT_INTENT_MAGIC)));

        vm.expectRevert(
            abi.encodeWithSelector(
                DepositIntentLib.InvalidDepositIntentHookData.selector, corruptedHookDataLength, corruptedRef.len()
            )
        );
        DepositIntentLib.getHookData(corruptedRef);
    }

    // ============ Validate Magic Values ============

    function test_validateDepositIntentMagicValue() public pure {
        assertEq(DEPOSIT_INTENT_MAGIC, bytes4(keccak256("circle.xReserve.DepositIntent")));
    }
}
