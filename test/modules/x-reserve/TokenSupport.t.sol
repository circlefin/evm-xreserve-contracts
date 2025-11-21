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

import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ZeroAddress} from "src/common/Errors.sol";
import {Immutables} from "src/modules/x-reserve/Immutables.sol";
import {TokenSupport, TokenSupportStorage} from "src/modules/x-reserve/TokenSupport.sol";
import {DeployMockFiatToken} from "../../utils/DeployMockFiatToken.sol";

contract TokenSupportHarness is Test, TokenSupport {
    constructor()
        Immutables(
            makeAddr("gatewayMinter"),
            makeAddr("gatewayWallet"),
            makeAddr("tokenMessenger"),
            makeAddr("tokenMessengerV2")
        )
    {}

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
    }

    function initializeWithTokens(address owner, address[] calldata supportedTokens) public initializer {
        __Ownable_init(owner);
        __Ownable2Step_init();
        __TokenSupport_init(supportedTokens);
    }

    // Expose storage functions for testing
    function getStorageSlot() public pure returns (bytes32) {
        return TokenSupportStorage.SLOT;
    }

    // Expose storage data for testing
    function getStorageData(address token) public view returns (bool) {
        return TokenSupportStorage.get().supportedTokens[token];
    }
}

contract TokenSupportTest is Test, DeployMockFiatToken {
    TokenSupportHarness private tokenSupport;

    address private owner = makeAddr("owner");
    FiatTokenV2_2 private usdc;
    FiatTokenV2_2 private eurc;

    function setUp() public {
        tokenSupport = new TokenSupportHarness();
        tokenSupport.initialize(owner);

        usdc = deployMockFiatToken(owner);
        eurc = deployMockFiatToken(owner);
    }

    function test_addSupportedToken_addsTokenWhenOwner() public {
        vm.expectEmit(false, false, false, true);
        emit TokenSupport.TokenSupported(address(usdc));

        vm.startPrank(owner);
        tokenSupport.addSupportedToken(address(usdc));
        vm.stopPrank();

        assertTrue(tokenSupport.isTokenSupported(address(usdc)));
    }

    function test_addSupportedToken_revertsWhenNotOwner() public {
        address random = makeAddr("random");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));

        vm.startPrank(random);
        tokenSupport.addSupportedToken(address(usdc));
        vm.stopPrank();
    }

    function test_addSupportedToken_allowsDuplicateToken() public {
        vm.startPrank(owner);

        // First addition should emit event
        vm.expectEmit(true, false, false, false);
        emit TokenSupport.TokenSupported(address(usdc));
        tokenSupport.addSupportedToken(address(usdc));
        assertTrue(tokenSupport.isTokenSupported(address(usdc)));

        // Second addition should NOT emit event (duplicate)
        vm.recordLogs();
        tokenSupport.addSupportedToken(address(usdc));

        // Verify no events were emitted for duplicate
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No events should be emitted for duplicate tokens");

        assertTrue(tokenSupport.isTokenSupported(address(usdc)));
        vm.stopPrank();
    }

    function test_addSupportedToken_addsMultipleTokens() public {
        vm.startPrank(owner);
        tokenSupport.addSupportedToken(address(usdc));
        tokenSupport.addSupportedToken(address(eurc));
        vm.stopPrank();

        assertTrue(tokenSupport.isTokenSupported(address(usdc)));
        assertTrue(tokenSupport.isTokenSupported(address(eurc)));
    }

    function test_addSupportedToken_revertsOnZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        tokenSupport.addSupportedToken(address(0));
        vm.stopPrank();
    }

    function test_isTokenSupported_returnsFalseWhenNotAdded() public view {
        assertFalse(tokenSupport.isTokenSupported(address(eurc)));
    }

    function test_isTokenSupported_returnsTrueWhenAdded() public {
        vm.startPrank(owner);
        tokenSupport.addSupportedToken(address(usdc));
        vm.stopPrank();

        assertTrue(tokenSupport.isTokenSupported(address(usdc)));
    }

    // Test __TokenSupport_init function
    function test_init_initializesWithSupportedTokens() public {
        address[] memory supportedTokens = new address[](2);
        supportedTokens[0] = address(usdc);
        supportedTokens[1] = address(eurc);

        TokenSupportHarness newTokenSupport = new TokenSupportHarness();
        newTokenSupport.initializeWithTokens(owner, supportedTokens);

        assertTrue(newTokenSupport.isTokenSupported(address(usdc)));
        assertTrue(newTokenSupport.isTokenSupported(address(eurc)));
    }

    function test_init_initializesWithEmptyArray() public {
        address[] memory supportedTokens = new address[](0);

        TokenSupportHarness newTokenSupport = new TokenSupportHarness();
        newTokenSupport.initializeWithTokens(owner, supportedTokens);

        assertFalse(newTokenSupport.isTokenSupported(address(usdc)));
        assertFalse(newTokenSupport.isTokenSupported(address(eurc)));
    }

    function test_init_initializesWithSingleToken() public {
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(usdc);

        TokenSupportHarness newTokenSupport = new TokenSupportHarness();
        newTokenSupport.initializeWithTokens(owner, supportedTokens);

        assertTrue(newTokenSupport.isTokenSupported(address(usdc)));
        assertFalse(newTokenSupport.isTokenSupported(address(eurc)));
    }

    function test_init_emitsEventsForInitialTokens() public {
        address[] memory supportedTokens = new address[](2);
        supportedTokens[0] = address(usdc);
        supportedTokens[1] = address(eurc);

        TokenSupportHarness newTokenSupport = new TokenSupportHarness();

        vm.expectEmit(true, false, false, false);
        emit TokenSupport.TokenSupported(address(usdc));
        vm.expectEmit(true, false, false, false);
        emit TokenSupport.TokenSupported(address(eurc));

        newTokenSupport.initializeWithTokens(owner, supportedTokens);
    }

    function test_init_revertsOnZeroAddress() public {
        TokenSupportHarness newTokenSupport = new TokenSupportHarness();

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(0);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        newTokenSupport.initializeWithTokens(owner, supportedTokens);
    }

    // Test storage slot calculation
    function test_getStorageSlot_returnsCorrectSlot() public view {
        bytes32 actualSlot = tokenSupport.getStorageSlot();
        assertEq(
            actualSlot,
            keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.TokenSupport"))) - 1))
                & ~bytes32(uint256(0xff)),
            "Storage slot should match expected EIP-7201 slot."
        );
    }

    // Test storage consistency
    function test_storage_returnsConsistentData() public {
        vm.startPrank(owner);
        tokenSupport.addSupportedToken(address(usdc));
        vm.stopPrank();

        // Verify both ways of accessing storage return the same value
        assertTrue(tokenSupport.isTokenSupported(address(usdc)));
        assertTrue(tokenSupport.getStorageData(address(usdc)));
    }

    // Test boundary values
    function test_addSupportedToken_handlesBoundaryAddresses() public {
        FiatTokenV2_2 token1 = deployMockFiatToken(owner);
        FiatTokenV2_2 token2 = deployMockFiatToken(owner);
        FiatTokenV2_2 token3 = deployMockFiatToken(owner);

        address[3] memory testAddresses = [address(token1), address(token2), address(token3)];

        vm.startPrank(owner);
        for (uint256 i = 0; i < testAddresses.length; i++) {
            tokenSupport.addSupportedToken(testAddresses[i]);
            assertTrue(tokenSupport.isTokenSupported(testAddresses[i]));
        }
        vm.stopPrank();
    }

    // Test uninitialized state
    function test_isTokenSupported_returnsFalseWhenUninitialized() public {
        TokenSupportHarness freshTokenSupport = new TokenSupportHarness();
        // Don't initialize

        assertFalse(freshTokenSupport.isTokenSupported(address(usdc)));
        assertFalse(freshTokenSupport.isTokenSupported(address(0)));
    }

    // Test _addSupportedToken does not auto-approve in base implementation
    function test_addSupportedToken_setsUnlimitedAllowanceInBaseImplementation() public {
        TokenSupportHarness tokenSupportHarness = new TokenSupportHarness();
        tokenSupportHarness.initialize(owner);

        FiatTokenV2_2 mockToken = deployMockFiatToken(owner);

        // Verify initial allowance is 0
        assertEq(IERC20(mockToken).allowance(address(tokenSupportHarness), tokenSupportHarness.gatewayWallet()), 0);
        assertEq(IERC20(mockToken).allowance(address(tokenSupportHarness), tokenSupportHarness.tokenMessenger()), 0);
        assertEq(IERC20(mockToken).allowance(address(tokenSupportHarness), tokenSupportHarness.tokenMessengerV2()), 0);

        // Add the token as supported
        vm.prank(owner);
        tokenSupportHarness.addSupportedToken(address(mockToken));

        // Verify allowance remains 0 (base implementation is empty)
        assertEq(
            IERC20(mockToken).allowance(address(tokenSupportHarness), tokenSupportHarness.gatewayWallet()),
            type(uint256).max
        );
        assertEq(
            IERC20(mockToken).allowance(address(tokenSupportHarness), tokenSupportHarness.tokenMessenger()),
            type(uint256).max
        );
        assertEq(
            IERC20(mockToken).allowance(address(tokenSupportHarness), tokenSupportHarness.tokenMessengerV2()),
            type(uint256).max
        );

        // Verify the token is supported
        assertTrue(tokenSupportHarness.isTokenSupported(address(mockToken)));
    }
}
