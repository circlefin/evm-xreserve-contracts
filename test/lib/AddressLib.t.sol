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
import {Test} from "forge-std/Test.sol";
import {ZeroAddress, ZeroBytes32, InvalidAddressPadding} from "src/common/Errors.sol";
import {AddressLib} from "./../../src/lib/AddressLib.sol";

/// @dev Test harness to expose internal library functions
contract AddressLibHarness {
    function checkNotZeroAddress(address addr) external pure {
        AddressLib._checkNotZeroAddress(addr);
    }

    function checkNotZeroBytes32(bytes32 buf) external pure {
        AddressLib._checkNotZeroBytes32(buf);
    }

    function addressToBytes32(address addr) external pure returns (bytes32) {
        return GatewayAddressLib._addressToBytes32(addr);
    }

    function bytes32ToAddressSafe(bytes32 buf) external pure returns (address) {
        return AddressLib._bytes32ToAddressSafe(buf);
    }
}

contract AddressLibTest is Test {
    AddressLibHarness private harness;

    function setUp() public {
        harness = new AddressLibHarness();
    }

    // Tests for _checkNotZeroAddress
    function test_checkNotZeroAddress_passesWithValidAddress() public {
        address validAddress = makeAddr("validAddress");
        // Should not revert
        harness.checkNotZeroAddress(validAddress);
    }

    function test_checkNotZeroAddress_revertsWithZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        harness.checkNotZeroAddress(address(0));
    }

    function test_checkNotZeroAddress_passesWithRandomAddresses() public {
        harness.checkNotZeroAddress(address(0x1));
        harness.checkNotZeroAddress(address(0xdeadbeef));
        harness.checkNotZeroAddress(address(type(uint160).max));
        harness.checkNotZeroAddress(makeAddr("random1"));
        harness.checkNotZeroAddress(makeAddr("random2"));
    }

    function testFuzz_checkNotZeroAddress_passesWithNonZeroAddresses(address addr) public view {
        vm.assume(addr != address(0));
        harness.checkNotZeroAddress(addr);
    }

    // Tests for _checkNotZeroBytes32
    function test_checkNotZeroBytes32_revertsWithZeroBytes32() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroBytes32.selector));
        harness.checkNotZeroBytes32(bytes32(0));
    }

    function test_checkNotZeroBytes32_passesWithRandomBytes32() public view {
        harness.checkNotZeroBytes32(bytes32(uint256(0x1)));
        harness.checkNotZeroBytes32(bytes32(uint256(0xdeadbeef)));
        harness.checkNotZeroBytes32(bytes32(type(uint256).max));
        harness.checkNotZeroBytes32(keccak256("random1"));
        harness.checkNotZeroBytes32(keccak256("random2"));
    }

    // Tests for _addressToBytes32
    function test_addressToBytes32_convertsCorrectly() public view {
        address addr = address(0x1234567890123456789012345678901234567890);
        bytes32 expected = bytes32(uint256(uint160(addr)));
        bytes32 result = harness.addressToBytes32(addr);

        assertEq(result, expected, "Address to bytes32 conversion should be correct");

        // Verify it's right-aligned (padded with leading zeros)
        assertEq(
            result,
            bytes32(0x0000000000000000000000001234567890123456789012345678901234567890),
            "Should be right-aligned with leading zeros"
        );
    }

    function test_addressToBytes32_handlesZeroAddress() public view {
        address zeroAddr = address(0);
        bytes32 result = harness.addressToBytes32(zeroAddr);

        assertEq(result, bytes32(0), "Zero address should convert to zero bytes32");
    }

    function test_addressToBytes32_handlesMaxAddress() public view {
        address maxAddr = address(type(uint160).max);
        bytes32 result = harness.addressToBytes32(maxAddr);
        bytes32 expected = bytes32(uint256(type(uint160).max));

        assertEq(result, expected, "Max address should convert correctly");
    }

    function test_addressToBytes32_handlesBoundaryValues() public view {
        // Test address(0x1)
        address addr1 = address(0x1);
        bytes32 result1 = harness.addressToBytes32(addr1);
        assertEq(result1, bytes32(0x0000000000000000000000000000000000000000000000000000000000000001));

        // Test address with only high bits set in the 20-byte range
        address addrHigh = address(0xfF00000000000000000000000000000000000000);
        bytes32 resultHigh = harness.addressToBytes32(addrHigh);
        assertEq(resultHigh, bytes32(0x000000000000000000000000ff00000000000000000000000000000000000000));
    }

    function testFuzz_addressToBytes32_correctConversion(address addr) public view {
        bytes32 result = harness.addressToBytes32(addr);
        bytes32 expected = bytes32(uint256(uint160(addr)));

        assertEq(result, expected, "Fuzz: Address to bytes32 conversion should be correct");

        // Verify the upper 12 bytes are always zero
        bytes32 upperBytes = result & bytes32(0xffffffffffffffffffffffff0000000000000000000000000000000000000000);
        assertEq(upperBytes, bytes32(0), "Upper 12 bytes should always be zero");
    }

    // Tests for round-trip conversions
    function test_roundTrip_addressToBytes32ToAddress() public {
        address originalAddr = makeAddr("testAddress");

        bytes32 bytes32Result = harness.addressToBytes32(originalAddr);
        address finalAddr = harness.bytes32ToAddressSafe(bytes32Result);

        assertEq(finalAddr, originalAddr, "Round trip conversion should preserve original address");
    }

    function test_roundTrip_bytes32ToAddressToBytes32() public view {
        // Note: This only works if the upper 12 bytes of the original bytes32 are zero
        bytes32 originalBytes = bytes32(0x0000000000000000000000001234567890123456789012345678901234567890);

        address addrResult = harness.bytes32ToAddressSafe(originalBytes);
        bytes32 finalBytes = harness.addressToBytes32(addrResult);

        assertEq(finalBytes, originalBytes, "Round trip should preserve bytes32 with zero upper bytes");
    }

    function testFuzz_roundTrip_addressToBytes32ToAddress(address addr) public view {
        bytes32 bytes32Result = harness.addressToBytes32(addr);
        address finalAddr = harness.bytes32ToAddressSafe(bytes32Result);

        assertEq(finalAddr, addr, "Fuzz: Round trip should preserve original address");
    }

    function testFuzz_roundTrip_bytes32ToAddressToBytes32_withZeroUpperBytes(uint160 lower20Bytes) public view {
        // Create bytes32 with zero upper bytes and fuzzed lower 20 bytes
        bytes32 originalBytes = bytes32(uint256(lower20Bytes));

        address addrResult = harness.bytes32ToAddressSafe(originalBytes);
        bytes32 finalBytes = harness.addressToBytes32(addrResult);

        assertEq(finalBytes, originalBytes, "Fuzz: Round trip should preserve bytes32 with zero upper bytes");
    }

    // Edge case tests
    function test_conversionConsistency_specialAddresses() public {
        address[] memory specialAddresses = new address[](4);
        specialAddresses[0] = address(0);
        specialAddresses[1] = address(0x1);
        specialAddresses[2] = address(type(uint160).max);
        specialAddresses[3] = makeAddr("special");

        for (uint256 i = 0; i < specialAddresses.length; i++) {
            address addr = specialAddresses[i];

            // Convert address -> bytes32 -> address
            bytes32 asBytes32 = harness.addressToBytes32(addr);
            address backToAddr = harness.bytes32ToAddressSafe(asBytes32);

            assertEq(backToAddr, addr, "Special address round trip should be consistent");

            // Verify bytes32 format
            assertEq(asBytes32, bytes32(uint256(uint160(addr))), "Bytes32 format should be correct");
        }
    }

    function test_conversionConsistency_randomBytes32WithZeroUpper() public view {
        // Test with various bytes32 values that have zero upper bytes
        bytes32[] memory testBytes = new bytes32[](3);
        testBytes[0] = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);
        testBytes[1] = bytes32(0x000000000000000000000000deadbeefcafebabe1234567890abcdef12345678);
        testBytes[2] = bytes32(0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff);

        for (uint256 i = 0; i < testBytes.length; i++) {
            bytes32 bytes32Val = testBytes[i];

            // Convert bytes32 -> address -> bytes32
            address asAddr = harness.bytes32ToAddressSafe(bytes32Val);
            bytes32 backToBytes32 = harness.addressToBytes32(asAddr);

            assertEq(backToBytes32, bytes32Val, "Bytes32 with zero upper bytes round trip should be consistent");

            // Verify address format
            assertEq(asAddr, address(uint160(uint256(bytes32Val))), "Address format should be correct");
        }
    }

    // Tests for _bytes32ToAddressSafe
    function test_bytes32ToAddressSafe_convertsValidBytes32() public view {
        // Test with properly padded bytes32 (zero upper 12 bytes)
        bytes32 validInput = bytes32(0x0000000000000000000000001234567890123456789012345678901234567890);
        address expected = address(0x1234567890123456789012345678901234567890);
        address result = harness.bytes32ToAddressSafe(validInput);

        assertEq(result, expected, "Safe conversion should work with properly padded bytes32");
    }

    function test_bytes32ToAddressSafe_revertsWithNonZeroPadding() public {
        // Test with non-zero upper bytes - should revert
        bytes32 invalidInput = bytes32(0xdeadbeef00000000000000001234567890123456789012345678901234567890);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidInput));
        harness.bytes32ToAddressSafe(invalidInput);
    }

    function test_bytes32ToAddressSafe_revertsWithSingleNonZeroBit() public {
        // Test with just one bit set in upper 12 bytes
        bytes32 invalidInput = bytes32(0x0000000000000000000000011234567890123456789012345678901234567890);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidInput));
        harness.bytes32ToAddressSafe(invalidInput);
    }

    function test_bytes32ToAddressSafe_revertsWithAllUpperBytesSet() public {
        // Test with all upper 12 bytes set to 0xFF
        bytes32 invalidInput = bytes32(0xffffffffffffffffffffffff1234567890123456789012345678901234567890);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidInput));
        harness.bytes32ToAddressSafe(invalidInput);
    }

    function test_bytes32ToAddressSafe_handlesZeroAddress() public view {
        // Zero bytes32 should convert to zero address without reverting
        bytes32 zeroBytes = bytes32(0);
        address result = harness.bytes32ToAddressSafe(zeroBytes);

        assertEq(result, address(0), "Zero bytes32 should safely convert to zero address");
    }

    function test_bytes32ToAddressSafe_handlesMaxValidAddress() public view {
        // Test with max value in lower 20 bytes, zero in upper 12
        bytes32 maxValidInput = bytes32(uint256(type(uint160).max));
        address expected = address(type(uint160).max);
        address result = harness.bytes32ToAddressSafe(maxValidInput);

        assertEq(result, expected, "Should handle max valid address");
    }

    function test_bytes32ToAddressSafe_boundaryTests() public {
        // Test boundary between valid and invalid padding
        // Valid: upper 12 bytes are zero
        bytes32 validBoundary = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);
        address result = harness.bytes32ToAddressSafe(validBoundary);
        assertEq(result, address(0x1), "Should accept minimum valid address");

        // Invalid: 13th byte from left (12th from right of upper section) has a bit set
        bytes32 invalidBoundary = bytes32(0x0000000000000000000000010000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidBoundary));
        harness.bytes32ToAddressSafe(invalidBoundary);
    }

    function testFuzz_bytes32ToAddressSafe_acceptsValidPadding(uint160 addressValue) public view {
        // Create properly padded bytes32 from address value
        bytes32 validInput = bytes32(uint256(addressValue));

        // Should not revert
        address result = harness.bytes32ToAddressSafe(validInput);
        assertEq(result, address(addressValue), "Fuzz: Should accept properly padded bytes32");
    }

    function testFuzz_bytes32ToAddressSafe_rejectsInvalidPadding(bytes12 upperBytes, uint160 addressValue) public {
        vm.assume(upperBytes != bytes12(0)); // Ensure at least one non-zero bit in upper bytes

        // Construct bytes32 with non-zero upper bytes
        bytes32 invalidInput = bytes32(uint256(uint96(upperBytes)) << 160 | uint256(addressValue));

        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidInput));
        harness.bytes32ToAddressSafe(invalidInput);
    }

    // Integration tests
    function test_integration_addressToBytes32AndSafeConversion() public {
        // Test that addressToBytes32 always produces valid input for bytes32ToAddressSafe
        address originalAddr = makeAddr("testAddress");

        // Convert address to bytes32
        bytes32 bytes32Result = harness.addressToBytes32(originalAddr);

        // Safe conversion should work without reverting
        address finalAddr = harness.bytes32ToAddressSafe(bytes32Result);

        assertEq(finalAddr, originalAddr, "Round trip with safe conversion should preserve address");
    }

    function testFuzz_integration_addressToBytes32ProducesValidFormat(address addr) public view {
        // Verify that addressToBytes32 always produces format acceptable by bytes32ToAddressSafe
        bytes32 encoded = harness.addressToBytes32(addr);

        // This should never revert since addressToBytes32 produces properly padded bytes32
        address decoded = harness.bytes32ToAddressSafe(encoded);

        assertEq(decoded, addr, "Fuzz: addressToBytes32 should always produce safe-decodable bytes32");
    }

    // Additional test: Compare safe vs unsafe conversion behavior
    function test_bytes32ToAddressSafe_comparisonWithUnsafe() public {
        address testAddr = address(0x1234567890123456789012345678901234567890);

        // Create bytes32 with garbage in upper bytes
        bytes32 dirtyBytes = bytes32(0xDEADBEEFCAFEBABE000000000000000000000000000000000000000000000000)
            | bytes32(uint256(uint160(testAddr)));

        // Unsafe conversion extracts the address, ignoring upper bytes (demonstrating the vulnerability)
        address unsafeResult = address(uint160(uint256(dirtyBytes)));
        assertEq(unsafeResult, testAddr, "Unsafe extracts address ignoring invalid padding");

        // Safe conversion should reject it
        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, dirtyBytes));
        harness.bytes32ToAddressSafe(dirtyBytes);
    }

    // Test that demonstrates why safe conversion is important for security
    function test_bytes32ToAddressSafe_preventsMaliciousDataInjection() public {
        // Simulate an attacker trying to inject data in the upper bytes
        address legitAddress = makeAddr("legitimate");
        bytes12 maliciousData = hex"BADC0FFEE0DDF00D000000";

        bytes32 maliciousBytes32 = bytes32(uint256(uint96(maliciousData)) << 160 | uint256(uint160(legitAddress)));

        // The safe function should reject this
        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, maliciousBytes32));
        harness.bytes32ToAddressSafe(maliciousBytes32);

        // But the unsafe function would accept it (demonstrating the vulnerability)
        address unsafeResult = address(uint160(uint256(maliciousBytes32)));
        assertEq(unsafeResult, legitAddress, "Unsafe function extracts address ignoring malicious padding");
    }

    // Edge case: Test single bit padding rejection
    function test_bytes32ToAddressSafe_rejectsSingleBitPadding() public {
        address testAddr = makeAddr("test");

        // Test each individual bit position in the upper 12 bytes
        for (uint256 i = 0; i < 96; i++) {
            bytes32 invalidBytes32 = bytes32(uint256(1) << (160 + i)) | bytes32(uint256(uint160(testAddr)));

            vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidBytes32));
            harness.bytes32ToAddressSafe(invalidBytes32);
        }
    }

    // Fuzz test: safe conversion rejects any non-zero padding
    function testFuzz_bytes32ToAddressSafe_rejectsAnyNonZeroPadding(uint96 upperBits, address addr) public {
        vm.assume(upperBits != 0); // Ensure non-zero padding

        // Create bytes32 with non-zero upper bits
        bytes32 invalidBytes = bytes32(uint256(upperBits) << 160 | uint256(uint160(addr)));

        vm.expectRevert(abi.encodeWithSelector(InvalidAddressPadding.selector, invalidBytes));
        harness.bytes32ToAddressSafe(invalidBytes);
    }
}
