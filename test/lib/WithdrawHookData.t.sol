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
import {TransferPayloadTestUtils} from "lib/evm-gateway-contracts/test/util/TransferPayloadTestUtils.sol";
import {UINT32_BYTES} from "src/common/Constants.sol";
import {
    WithdrawHookData,
    WITHDRAW_HOOK_DATA_MAGIC,
    WITHDRAW_HOOK_DATA_VERSION,
    WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET,
    WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET
} from "src/lib/WithdrawHookData.sol";
import {WithdrawHookDataLib} from "src/lib/WithdrawHookDataLib.sol";

contract WithdrawHookDataTest is TransferPayloadTestUtils {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using WithdrawHookDataLib for bytes29;

    uint8 private constant BYTES4_BYTES = 4;

    // ===== Test Data Constants =====

    bytes32 internal constant TEST_FORWARDING_CONTRACT =
        bytes32(uint256(uint160(0x1234567890123456789012345678901234567890)));
    bytes32 internal constant ZERO_FORWARDING_CONTRACT = bytes32(0);

    // ===== Helper Functions =====

    /// @notice Helper function to create corrupted forwarding calldata length - similar to TransferSpec test utils
    function _getCorruptedForwardingCalldataLengthData(
        bytes memory encodedHookData,
        uint32 originalCalldataLength,
        bool makeLengthBigger
    ) internal pure returns (bytes memory corruptedData, uint32 corruptedCalldataLength) {
        uint256 calldataLengthOffset = WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET;
        corruptedData = cloneBytes(encodedHookData);

        if (makeLengthBigger) {
            corruptedCalldataLength = originalCalldataLength * 2;
        } else {
            corruptedCalldataLength = originalCalldataLength / 2;
        }

        bytes memory encodedInvalidLength = abi.encodePacked(corruptedCalldataLength);
        for (uint8 i = 0; i < UINT32_BYTES; i++) {
            corruptedData[calldataLengthOffset + i] = encodedInvalidLength[i];
        }

        return (corruptedData, corruptedCalldataLength);
    }

    /// @notice Creates a sample WithdrawHookData struct for testing
    function _createSampleWithdrawHookData(bytes memory forwardingCalldata)
        internal
        pure
        returns (WithdrawHookData memory)
    {
        return WithdrawHookData({
            version: 1,
            remoteDomain: 123456,
            remoteToken: bytes32(uint256(0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890)),
            remoteDepositor: bytes32(uint256(0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321)),
            forwardingContract: TEST_FORWARDING_CONTRACT,
            forwardingCalldata: forwardingCalldata
        });
    }

    /// @notice Verifies all fields read from a WithdrawHookData view match the original struct
    function _verifyWithdrawHookDataFieldsFromView(bytes29 ref, WithdrawHookData memory hookData) internal view {
        // Verify the view has the correct type
        assertEq(TypedMemView.typeOf(ref), WithdrawHookDataLib._toMemViewType(WITHDRAW_HOOK_DATA_MAGIC));
        assertEq(WithdrawHookDataLib.getVersion(ref), hookData.version, "Eq Fail: version");
        assertEq(WithdrawHookDataLib.getRemoteDomain(ref), hookData.remoteDomain, "Eq Fail: remoteDomain");
        assertEq(WithdrawHookDataLib.getRemoteToken(ref), hookData.remoteToken, "Eq Fail: remoteToken");
        assertEq(WithdrawHookDataLib.getRemoteDepositor(ref), hookData.remoteDepositor, "Eq Fail: remoteDepositor");
        assertEq(
            WithdrawHookDataLib.getForwardingContract(ref), hookData.forwardingContract, "Eq Fail: forwardingContract"
        );

        // Forwarding calldata checks
        uint32 forwardingCalldataLength = WithdrawHookDataLib.getForwardingCalldataLength(ref);
        assertEq(forwardingCalldataLength, hookData.forwardingCalldata.length, "Mismatch: forwardingCalldata.length");
        bytes memory retrievedForwardingCalldata = WithdrawHookDataLib.getForwardingCalldata(ref);
        assertEq(
            keccak256(retrievedForwardingCalldata),
            keccak256(hookData.forwardingCalldata),
            "Mismatch: forwardingCalldata content"
        );
    }

    // ===== Casting Tests =====

    function test_asWithdrawHookDataView_success() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);

        // Verify the magic is correct
        bytes4 magic = bytes4(encoded);
        assertEq(magic, WITHDRAW_HOOK_DATA_MAGIC);

        // Verify the view type
        assertEq(TypedMemView.typeOf(ref), WithdrawHookDataLib._toMemViewType(WITHDRAW_HOOK_DATA_MAGIC));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_asWithdrawHookDataView_revertsOnShortData() public {
        bytes memory shortData = hex"1122";
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.WithdrawHookDataTooShort.selector, BYTES4_BYTES, shortData.length
            )
        );
        WithdrawHookDataLib._asWithdrawHookDataView(shortData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnInvalidMagic4Bytes() public {
        (bytes memory invalidMagicData,) = _magic("not a valid magic");
        bytes4 incorrectMagic = bytes4(invalidMagicData);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawHookDataLib.InvalidWithdrawHookDataMagic.selector, incorrectMagic)
        );
        WithdrawHookDataLib._validate(invalidMagicData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnInvalidMagicLonger() public {
        (bytes memory invalidMagicData,) = _magic("not a valid magic");
        bytes memory longerInvalidMagic = bytes.concat(invalidMagicData, hex"01020304");
        bytes4 incorrectMagic = bytes4(longerInvalidMagic);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawHookDataLib.InvalidWithdrawHookDataMagic.selector, incorrectMagic)
        );
        WithdrawHookDataLib._validate(longerInvalidMagic);
    }

    // ===== Validation Tests =====

    function test_validate_successEmptyForwardingCalldata() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(new bytes(0));
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        WithdrawHookDataLib._validate(encoded);
    }

    function test_validate_successShortForwardingCalldata() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        WithdrawHookDataLib._validate(encoded);
    }

    function test_validate_successLongForwardingCalldata() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        WithdrawHookDataLib._validate(encoded);
    }

    function test_validate_successFuzz(
        uint32 version,
        uint32 remoteDomain,
        bytes32 remoteToken,
        bytes32 remoteDepositor,
        address forwardingContract,
        bytes memory forwardingCalldata
    ) public pure {
        vm.assume(version == WITHDRAW_HOOK_DATA_VERSION);
        WithdrawHookData memory data = WithdrawHookData({
            version: version,
            remoteDomain: remoteDomain,
            remoteToken: remoteToken,
            remoteDepositor: remoteDepositor,
            forwardingContract: GatewayAddressLib._addressToBytes32(forwardingContract),
            forwardingCalldata: forwardingCalldata
        });
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(data);
        WithdrawHookDataLib._validate(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnInvalidVersion() public {
        uint32 invalidVersion = WITHDRAW_HOOK_DATA_VERSION + 1;
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        hookData.version = invalidVersion;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);

        vm.expectRevert(
            abi.encodeWithSelector(WithdrawHookDataLib.InvalidWithdrawHookDataVersion.selector, invalidVersion)
        );
        WithdrawHookDataLib._validate(encoded);
    }

    // ===== Validation Failures: Structure =====

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnDataTooShortForHeader() public {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes memory validEncoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);

        uint16 truncatedLength = WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET - 1;
        bytes memory shortData = new bytes(truncatedLength);
        for (uint16 i = 0; i < truncatedLength; i++) {
            shortData[i] = validEncoded[i];
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.WithdrawHookDataHeaderTooShort.selector,
                WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET,
                shortData.length
            )
        );
        WithdrawHookDataLib._validate(shortData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnDeclaredForwardingCalldataLengthTooBig() public {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        uint256 originalLength = encoded.length;
        uint32 originalForwardingCalldataLength = uint32(hookData.forwardingCalldata.length);

        uint32 invalidForwardingCalldataLength = originalForwardingCalldataLength + 10;
        bytes4 encodedInvalidLength = bytes4(invalidForwardingCalldataLength);
        bytes memory corruptedData = cloneBytes(encoded);
        for (uint8 i = 0; i < 4; i++) {
            corruptedData[WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET + i] = encodedInvalidLength[i];
        }

        uint256 expectedLengthBasedOnCorruption =
            WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET + invalidForwardingCalldataLength;
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.WithdrawHookDataOverallLengthMismatch.selector,
                expectedLengthBasedOnCorruption,
                originalLength
            )
        );
        WithdrawHookDataLib._validate(corruptedData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnDeclaredForwardingCalldataLengthTooSmall() public {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        uint256 originalLength = encoded.length;
        uint32 originalForwardingCalldataLength = uint32(hookData.forwardingCalldata.length);

        uint32 invalidForwardingCalldataLength = originalForwardingCalldataLength - 5;
        bytes4 encodedInvalidLength = bytes4(invalidForwardingCalldataLength);
        bytes memory corruptedData = cloneBytes(encoded);
        for (uint8 i = 0; i < 4; i++) {
            corruptedData[WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET + i] = encodedInvalidLength[i];
        }

        uint256 expectedLengthBasedOnCorruption =
            WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET + invalidForwardingCalldataLength;
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.WithdrawHookDataOverallLengthMismatch.selector,
                expectedLengthBasedOnCorruption,
                originalLength
            )
        );
        WithdrawHookDataLib._validate(corruptedData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnTruncatedData() public {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        uint256 expectedLength = encoded.length;

        bytes memory truncatedData = new bytes(expectedLength - 1);
        for (uint256 i = 0; i < truncatedData.length; i++) {
            truncatedData[i] = encoded[i];
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.WithdrawHookDataOverallLengthMismatch.selector, expectedLength, truncatedData.length
            )
        );
        WithdrawHookDataLib._validate(truncatedData);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_validate_revertsOnTrailingBytes() public {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        uint256 originalLength = encoded.length;

        bytes memory corruptedData = bytes.concat(encoded, hex"FFFF");
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.WithdrawHookDataOverallLengthMismatch.selector, originalLength, corruptedData.length
            )
        );
        WithdrawHookDataLib._validate(corruptedData);
    }

    // ===== Field Accessor Tests =====

    function test_readAllFieldsEmptyForwardingCalldata() public view {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(new bytes(0));
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        _verifyWithdrawHookDataFieldsFromView(ref, hookData);
    }

    function test_readAllFieldsShortForwardingCalldata() public view {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        _verifyWithdrawHookDataFieldsFromView(ref, hookData);
    }

    function test_readAllFieldsLongForwardingCalldata() public view {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        _verifyWithdrawHookDataFieldsFromView(ref, hookData);
    }

    function test_readAllFieldsZeroForwardingContract() public view {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        hookData.forwardingContract = ZERO_FORWARDING_CONTRACT;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        _verifyWithdrawHookDataFieldsFromView(ref, hookData);
    }

    function test_readAllFieldsFuzz(
        uint32 version,
        uint32 remoteDomain,
        bytes32 remoteToken,
        bytes32 remoteDepositor,
        address forwardingContract,
        bytes memory forwardingCalldata
    ) public view {
        vm.assume(version == WITHDRAW_HOOK_DATA_VERSION);
        WithdrawHookData memory data = WithdrawHookData({
            version: version,
            remoteDomain: remoteDomain,
            remoteToken: remoteToken,
            remoteDepositor: remoteDepositor,
            forwardingContract: GatewayAddressLib._addressToBytes32(forwardingContract),
            forwardingCalldata: forwardingCalldata
        });
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(data);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        _verifyWithdrawHookDataFieldsFromView(ref, data);
    }

    // ===== Individual Field Accessor Tests =====

    function test_getVersion() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        hookData.version = 42;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        assertEq(WithdrawHookDataLib.getVersion(ref), 42);
    }

    function test_getRemoteDomain() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        hookData.remoteDomain = 999999;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        assertEq(WithdrawHookDataLib.getRemoteDomain(ref), 999999);
    }

    function test_getRemoteToken() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes32 testToken = bytes32(uint256(0x1111111111111111111111111111111111111111111111111111111111111111));
        hookData.remoteToken = testToken;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        assertEq(WithdrawHookDataLib.getRemoteToken(ref), testToken);
    }

    function test_getRemoteDepositor() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes32 testDepositor = bytes32(uint256(0x2222222222222222222222222222222222222222222222222222222222222222));
        hookData.remoteDepositor = testDepositor;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        assertEq(WithdrawHookDataLib.getRemoteDepositor(ref), testDepositor);
    }

    function test_getForwardingContract() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(SHORT_HOOK_DATA);
        bytes32 testContract = GatewayAddressLib._addressToBytes32(0x9999999999999999999999999999999999999999);
        hookData.forwardingContract = testContract;
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        assertEq(WithdrawHookDataLib.getForwardingContract(ref), testContract);
    }

    function test_getForwardingCalldataLength() public pure {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        assertEq(WithdrawHookDataLib.getForwardingCalldataLength(ref), LONG_HOOK_DATA.length);
    }

    function test_getForwardingCalldataEmpty() public view {
        WithdrawHookData memory hookData = _createSampleWithdrawHookData(new bytes(0));
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);

        bytes memory retrievedForwardingCalldata = WithdrawHookDataLib.getForwardingCalldata(ref);
        assertEq(retrievedForwardingCalldata.length, 0);
        assertEq(WithdrawHookDataLib.getForwardingCalldataLength(ref), 0);
    }

    // ===== Decoding Tests =====

    function test_decodeWithdrawHookData() public view {
        WithdrawHookData memory original = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(original);

        WithdrawHookData memory decoded = WithdrawHookDataLib.decodeWithdrawHookData(encoded);

        // Verify all fields match
        assertEq(decoded.version, original.version, "version mismatch");
        assertEq(decoded.remoteDomain, original.remoteDomain, "remoteDomain mismatch");
        assertEq(decoded.remoteToken, original.remoteToken, "remoteToken mismatch");
        assertEq(decoded.remoteDepositor, original.remoteDepositor, "remoteDepositor mismatch");
        assertEq(decoded.forwardingContract, original.forwardingContract, "forwardingContract mismatch");
        assertEq(
            keccak256(decoded.forwardingCalldata), keccak256(original.forwardingCalldata), "forwardingCalldata mismatch"
        );
    }

    function test_decodeWithdrawHookDataFuzz(
        uint32 version,
        uint32 remoteDomain,
        bytes32 remoteToken,
        bytes32 remoteDepositor,
        address forwardingContract,
        bytes memory forwardingCalldata
    ) public view {
        vm.assume(version == WITHDRAW_HOOK_DATA_VERSION);
        WithdrawHookData memory original = WithdrawHookData({
            version: version,
            remoteDomain: remoteDomain,
            remoteToken: remoteToken,
            remoteDepositor: remoteDepositor,
            forwardingContract: GatewayAddressLib._addressToBytes32(forwardingContract),
            forwardingCalldata: forwardingCalldata
        });

        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(original);
        WithdrawHookData memory decoded = WithdrawHookDataLib.decodeWithdrawHookData(encoded);

        // Verify all fields match
        assertEq(decoded.version, original.version, "version mismatch");
        assertEq(decoded.remoteDomain, original.remoteDomain, "remoteDomain mismatch");
        assertEq(decoded.remoteToken, original.remoteToken, "remoteToken mismatch");
        assertEq(decoded.remoteDepositor, original.remoteDepositor, "remoteDepositor mismatch");
        assertEq(decoded.forwardingContract, original.forwardingContract, "forwardingContract mismatch");
        assertEq(
            keccak256(decoded.forwardingCalldata), keccak256(original.forwardingCalldata), "forwardingCalldata mismatch"
        );
    }

    // ===== Encoding Tests =====

    function test_encodeDecodeRoundTrip() public view {
        WithdrawHookData memory original = _createSampleWithdrawHookData(LONG_HOOK_DATA);
        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(original);
        bytes29 ref = WithdrawHookDataLib._asWithdrawHookDataView(encoded);
        _verifyWithdrawHookDataFieldsFromView(ref, original);
    }

    function test_encodingStructure() public pure {
        WithdrawHookData memory hookData = WithdrawHookData({
            version: 1,
            remoteDomain: 123,
            remoteToken: bytes32(uint256(0x1111)),
            remoteDepositor: bytes32(uint256(0x2222)),
            forwardingContract: GatewayAddressLib._addressToBytes32(address(0x3333)),
            forwardingCalldata: hex"abcd"
        });

        bytes memory encoded = WithdrawHookDataLib.encodeWithdrawHookData(hookData);

        // Verify magic is at the beginning
        bytes4 magic = bytes4(encoded);
        assertEq(magic, WITHDRAW_HOOK_DATA_MAGIC);

        // Verify total length includes all components
        uint256 expectedLength = 4 + 4 + 4 + 32 + 32 + 32 + 4 + hookData.forwardingCalldata.length;
        assertEq(encoded.length, expectedLength);
    }

    // ===== Hash Calculation Tests =====

    function test_magicValue_correctlyCalculated() public pure {
        assertEq(WITHDRAW_HOOK_DATA_MAGIC, bytes4(keccak256("circle.xReserve.WithdrawHookData")));
    }

    // ===== NULL Check Tests =====

    /// forge-config: default.allow_internal_expect_revert = true
    /// @notice Test that getForwardingCalldata reverts with InvalidWithdrawHookDataForwardingCalldata when slice returns NULL
    function test_getForwardingCalldata_revertsOnInvalidCalldata() public {
        WithdrawHookData memory hookData = WithdrawHookData({
            version: WITHDRAW_HOOK_DATA_VERSION,
            remoteDomain: 1,
            remoteToken: bytes32(uint256(0x3456789012345678901234567890123456789012345678901234567890123456)),
            remoteDepositor: bytes32(uint256(0x4567890123456789012345678901234567890123456789012345678901234567)),
            forwardingContract: TEST_FORWARDING_CONTRACT,
            forwardingCalldata: LONG_HOOK_DATA
        });

        bytes memory encodedHookData = WithdrawHookDataLib.encodeWithdrawHookData(hookData);

        (bytes memory corruptedData, uint32 corruptedCalldataLength) =
            _getCorruptedForwardingCalldataLengthData(encodedHookData, uint32(LONG_HOOK_DATA.length), true);
        bytes29 corruptedRef = corruptedData.ref(uint40(uint32(WITHDRAW_HOOK_DATA_MAGIC)));

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawHookDataLib.InvalidWithdrawHookDataForwardingCalldata.selector,
                corruptedCalldataLength,
                corruptedRef.len()
            )
        );
        WithdrawHookDataLib.getForwardingCalldata(corruptedRef);
    }
}
