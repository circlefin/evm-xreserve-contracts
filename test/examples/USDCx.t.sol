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

import {AddressLib} from "@gateway/src/lib/AddressLib.sol";
import {Test} from "forge-std/Test.sol";
import {USDCx} from "src/examples/USDCx.sol";
import {DepositIntent, DepositIntentLib} from "src/lib/DepositIntentLib.sol";

/// @title USDCxTest
/// @notice Unit tests for the USDCx contract
contract USDCxTest is Test {
    using DepositIntentLib for DepositIntent;

    USDCx public usdcx;

    // Test addresses
    address public owner;
    address public user1;
    address public user2;
    address public relayer;

    // Test keys for signing
    uint256 private attesterPrivateKey;
    uint256 private invalidAttesterPrivateKey;
    address public attester;
    address public invalidAttester;

    // Test constants
    uint32 public constant TEST_LOCAL_DOMAIN = 1;
    uint32 public constant TEST_REMOTE_DOMAIN = 10001;
    uint256 public constant TEST_AMOUNT = 100e6; // 100 USDC
    uint256 public constant TEST_FEE = 1e6; // 1 USDC

    function setUp() public {
        // Setup test addresses
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        relayer = makeAddr("relayer");

        // Setup test keys
        attesterPrivateKey = 0x1234;
        invalidAttesterPrivateKey = 0x5678;
        attester = vm.addr(attesterPrivateKey);
        invalidAttester = vm.addr(invalidAttesterPrivateKey);

        // Deploy USDCx contract
        vm.prank(owner);
        usdcx = new USDCx(owner, TEST_LOCAL_DOMAIN, attester);
    }

    /// @dev Helper function to create a valid DepositIntent
    function _createDepositIntent(uint256 amount, address recipient, uint256 maxFee, bytes32 nonce)
        internal
        view
        returns (DepositIntent memory)
    {
        return DepositIntent({
            version: 1,
            amount: amount,
            remoteDomain: TEST_LOCAL_DOMAIN, // This should match the USDCx contract's domain
            remoteToken: AddressLib._addressToBytes32(address(usdcx)), // Contract uses right-aligned address format
            remoteRecipient: AddressLib._addressToBytes32(recipient), // Balance uses right-aligned
            localToken: AddressLib._addressToBytes32(address(0x1)), // Mock local token
            localDepositor: AddressLib._addressToBytes32(user1), // Used for balance, right-aligned
            maxFee: maxFee,
            nonce: nonce,
            hookData: ""
        });
    }

    /// @dev Helper function to sign a deposit intent payload
    function _signPayload(bytes memory payload, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 hash = keccak256(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Helper function to create encoded deposit intent payload
    function _createEncodedDepositIntent(DepositIntent memory intent) internal pure returns (bytes memory) {
        return DepositIntentLib.encodeDepositIntent(intent);
    }

    // ===== Constructor Tests =====

    function test_constructor_deploysSuccessfully() public view {
        assertEq(usdcx.owner(), owner);
        assertEq(usdcx.domain(), TEST_LOCAL_DOMAIN);
        assertTrue(usdcx.attesters(attester));
        assertEq(usdcx.totalSupply(), 0);
    }

    function test_constructor_setsAttester() public view {
        assertTrue(usdcx.attesters(attester));

        // Verify other addresses are not set as attesters
        assertFalse(usdcx.attesters(invalidAttester));
    }

    // ===== Mint Function Tests =====

    function test_mint_success() public {
        bytes32 nonce = keccak256("test-nonce-1");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, TEST_FEE);

        assertEq(usdcx.balances(AddressLib._addressToBytes32(user1)), TEST_AMOUNT - TEST_FEE);
        assertEq(usdcx.balances(AddressLib._addressToBytes32(relayer)), TEST_FEE);
        assertEq(usdcx.totalSupply(), TEST_AMOUNT);
        assertTrue(usdcx.usedNonces(nonce));
    }

    function test_mint_succeedsWithZeroFee() public {
        // Setup
        bytes32 nonce = keccak256("test-nonce-2");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        // Perform mint with zero fee
        vm.prank(relayer);
        usdcx.mint(payload, signature, 0);

        // Verify state changes
        assertEq(usdcx.balances(AddressLib._addressToBytes32(user1)), TEST_AMOUNT);
        assertEq(usdcx.balances(AddressLib._addressToBytes32(relayer)), 0);
        assertEq(usdcx.totalSupply(), TEST_AMOUNT);
    }

    function test_mint_revertsIfInvalidAttester() public {
        // Setup
        bytes32 nonce = keccak256("test-nonce-3");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, invalidAttesterPrivateKey);

        // Expect revert
        vm.prank(relayer);
        vm.expectRevert("Invalid attester");
        usdcx.mint(payload, signature, TEST_FEE);
    }

    function test_mint_revertsIfInvalidVersion() public {
        // Setup with invalid version
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, keccak256("nonce"));
        intent.version = 2; // Invalid version
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(DepositIntentLib.InvalidDepositIntentVersion.selector, 2));
        usdcx.mint(payload, signature, TEST_FEE);
    }

    function test_mint_revertsIfZeroAmount() public {
        // Setup with zero amount
        bytes32 nonce = keccak256("test-nonce-4");
        DepositIntent memory intent = _createDepositIntent(0, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(DepositIntentLib.InvalidDepositAmount.selector, 0));
        usdcx.mint(payload, signature, 0);
    }

    function test_mint_revertsIfInvalidRemoteDomain() public {
        // Setup with invalid remote domain
        bytes32 nonce = keccak256("test-nonce-5");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        intent.remoteDomain = TEST_REMOTE_DOMAIN; // Use different domain than contract's domain
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        vm.expectRevert("Invalid remote domain");
        usdcx.mint(payload, signature, TEST_FEE);
    }

    function test_mint_revertsIfInvalidRemoteToken() public {
        // Setup with invalid remote token
        bytes32 nonce = keccak256("test-nonce-6");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        intent.remoteToken = AddressLib._addressToBytes32(address(0x123)); // Wrong token
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        vm.expectRevert("Invalid remote token");
        usdcx.mint(payload, signature, TEST_FEE);
    }

    function test_mint_revertsIfMaxFeeExceedsAmount() public {
        // Setup where amount < maxFee
        bytes32 nonce = keccak256("test-nonce-7");
        DepositIntent memory intent = _createDepositIntent(100, user1, 200, nonce); // amount < maxFee
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        vm.expectRevert("Max fee cannot exceed amount");
        usdcx.mint(payload, signature, 200);
    }

    function test_mint_revertsIfExcessiveFee() public {
        // Setup where feeAmount > maxFee
        bytes32 nonce = keccak256("test-nonce-8");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        vm.expectRevert("Cannot charge more than max fee");
        usdcx.mint(payload, signature, TEST_FEE + 1);
    }

    function test_mint_revertsIfNonceAlreadyUsed() public {
        // Setup
        bytes32 nonce = keccak256("test-nonce-9");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        // First mint should succeed
        vm.prank(relayer);
        usdcx.mint(payload, signature, TEST_FEE);

        // Second mint with same nonce should fail
        vm.prank(relayer);
        vm.expectRevert("Nonce already used");
        usdcx.mint(payload, signature, TEST_FEE);
    }

    // ===== Burn Function Tests =====

    function test_burn_success() public {
        // Setup - first mint some tokens
        bytes32 nonce = keccak256("mint-nonce");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, TEST_FEE);

        uint256 initialBalance = usdcx.balances(AddressLib._addressToBytes32(user1));
        uint256 initialTotalSupply = usdcx.totalSupply();

        // Test burn
        uint256 burnAmount = 50000000; // 50 million units (with 6 decimals = 50 USDC)
        bytes32 nativeRecipient = AddressLib._addressToBytes32(user2);

        vm.expectEmit(true, true, true, true);
        emit USDCx.Burn(
            AddressLib._addressToBytes32(user1), TEST_LOCAL_DOMAIN, burnAmount, TEST_REMOTE_DOMAIN, nativeRecipient
        );

        vm.prank(user1);
        usdcx.burn(burnAmount, TEST_REMOTE_DOMAIN, nativeRecipient);

        // Verify state changes
        assertEq(usdcx.balances(AddressLib._addressToBytes32(user1)), initialBalance - burnAmount);
        assertEq(usdcx.totalSupply(), initialTotalSupply - burnAmount);
    }

    function test_burn_revertsIfZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Zero value");
        usdcx.burn(0, TEST_REMOTE_DOMAIN, AddressLib._addressToBytes32(user2));
    }

    function test_burn_revertsIfInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert("Insufficient balance");
        usdcx.burn(TEST_AMOUNT, TEST_REMOTE_DOMAIN, AddressLib._addressToBytes32(user2));
    }

    function test_burn_revertsIfBelowMinimumBurnSize() public {
        // Setup - mint tokens first
        bytes32 nonce = keccak256("mint-nonce-min-burn");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, 0, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, 0);

        // Set minimum burn size
        uint256 minBurnSize = 10e6; // 10 USDC
        vm.prank(owner);
        usdcx.setMinBurnSize(minBurnSize);

        // Try to burn below minimum
        uint256 burnAmount = minBurnSize - 1;
        vm.prank(user1);
        vm.expectRevert("Amount below minimum burn size");
        usdcx.burn(burnAmount, TEST_REMOTE_DOMAIN, AddressLib._addressToBytes32(user2));
    }

    function test_burn_succeedsIfAtMinimumBurnSize() public {
        // Setup - mint tokens first
        bytes32 nonce = keccak256("mint-nonce-at-min-burn");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, 0, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, 0);

        // Set minimum burn size
        uint256 minBurnSize = 10e6; // 10 USDC
        vm.prank(owner);
        usdcx.setMinBurnSize(minBurnSize);

        // Burn exactly at minimum should succeed
        bytes32 nativeRecipient = AddressLib._addressToBytes32(user2);
        vm.prank(user1);
        usdcx.burn(minBurnSize, TEST_REMOTE_DOMAIN, nativeRecipient);

        assertEq(usdcx.balances(AddressLib._addressToBytes32(user1)), TEST_AMOUNT - minBurnSize);
        assertEq(usdcx.totalSupply(), TEST_AMOUNT - minBurnSize);
    }

    function test_burn_succeedsIfBurningAllBalance() public {
        // Setup - mint tokens first
        bytes32 nonce = keccak256("mint-nonce-burn-all");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, 0, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, 0);

        uint256 userBalance = usdcx.balances(AddressLib._addressToBytes32(user1));
        assertEq(userBalance, TEST_AMOUNT);

        // Burn all balance
        bytes32 nativeRecipient = AddressLib._addressToBytes32(user2);

        vm.prank(user1);
        usdcx.burn(userBalance, TEST_REMOTE_DOMAIN, nativeRecipient);

        // Verify balance is zero
        assertEq(usdcx.balances(AddressLib._addressToBytes32(user1)), 0);
        assertEq(usdcx.totalSupply(), 0);
    }

    // ===== setAttester Function Tests =====

    function test_setAttester_succeedsIfSettingNewAttester() public {
        address newAttester = makeAddr("new-attester");

        vm.prank(owner);
        usdcx.setAttester(newAttester, true);

        assertTrue(usdcx.attesters(newAttester));
    }

    function test_setAttester_succeedsIfRemovingAttester() public {
        // Verify attester is initially enabled
        assertTrue(usdcx.attesters(attester));

        // Remove attester
        vm.prank(owner);
        usdcx.setAttester(attester, false);

        assertFalse(usdcx.attesters(attester));
    }

    function test_setAttester_revertsIfNotOwner() public {
        address newAttester = makeAddr("new-attester");

        vm.prank(user1);
        vm.expectRevert("Not owner");
        usdcx.setAttester(newAttester, true);
    }

    // ===== setMinBurnSize Function Tests =====

    function test_setMinBurnSize_succeedsIfOwner() public {
        uint256 newMinBurnSize = 5e6; // 5 USDC

        vm.prank(owner);
        usdcx.setMinBurnSize(newMinBurnSize);

        assertEq(usdcx.minBurnSize(), newMinBurnSize);
    }

    function test_setMinBurnSize_revertsIfNotOwner() public {
        uint256 newMinBurnSize = 5e6; // 5 USDC

        vm.prank(user1);
        vm.expectRevert("Not owner");
        usdcx.setMinBurnSize(newMinBurnSize);
    }

    function test_attesterRotation_mintSucceedsWithNewAttester() public {
        // Add new attester using a proper private key
        uint256 newAttesterPrivateKey = 0x9999;
        address newAttester = vm.addr(newAttesterPrivateKey);

        vm.prank(owner);
        usdcx.setAttester(newAttester, true);

        // Remove old attester
        vm.prank(owner);
        usdcx.setAttester(attester, false);

        // Test mint with new attester
        bytes32 nonce = keccak256("new-attester-nonce");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, newAttesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, TEST_FEE);

        assertEq(usdcx.totalSupply(), TEST_AMOUNT);
    }

    function test_mint_succeedsWithMaxFeeEqualToAmount() public {
        bytes32 nonce = keccak256("max-fee-test");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_AMOUNT, nonce);
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, TEST_AMOUNT);

        // User should receive nothing, relayer gets everything
        assertEq(usdcx.balances(AddressLib._addressToBytes32(user1)), 0);
        assertEq(usdcx.balances(AddressLib._addressToBytes32(relayer)), TEST_AMOUNT);
    }

    function test_mint_succeedsWithHookData() public {
        bytes32 nonce = keccak256("hook-data-test");
        DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, user1, TEST_FEE, nonce);
        intent.hookData = "test-hook-data";
        bytes memory payload = _createEncodedDepositIntent(intent);
        bytes memory signature = _signPayload(payload, attesterPrivateKey);

        vm.prank(relayer);
        usdcx.mint(payload, signature, TEST_FEE);

        assertEq(usdcx.totalSupply(), TEST_AMOUNT);
    }

    function test_supportedVersionConstant() public view {
        assertEq(usdcx.SUPPORTED_VERSION(), 1);
    }

    function test_invariant_totalSupplyEqualsBalanceSum() public {
        // Mint to several users
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = makeAddr("user3"); // Use a different user instead of relayer to avoid double counting

        uint256 expectedTotalSupply = 0;

        for (uint256 i = 0; i < users.length; i++) {
            bytes32 nonce = keccak256(abi.encodePacked("invariant-test-", i));
            DepositIntent memory intent = _createDepositIntent(TEST_AMOUNT, users[i], TEST_FEE, nonce);
            bytes memory payload = _createEncodedDepositIntent(intent);
            bytes memory signature = _signPayload(payload, attesterPrivateKey);

            vm.prank(relayer);
            usdcx.mint(payload, signature, TEST_FEE);

            expectedTotalSupply += TEST_AMOUNT;
        }

        // Calculate sum of all balances (users + relayer who received fees)
        uint256 balanceSum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            balanceSum += usdcx.balances(AddressLib._addressToBytes32(users[i]));
        }
        balanceSum += usdcx.balances(AddressLib._addressToBytes32(relayer));

        assertEq(usdcx.totalSupply(), expectedTotalSupply);
        assertEq(balanceSum, expectedTotalSupply);
    }
}
