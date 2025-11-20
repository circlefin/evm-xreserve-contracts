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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenSupport} from "src/modules/x-reserve/TokenSupport.sol";
import {xReserve} from "src/xReserve.sol";
import {DeployXReserve} from "test/utils/DeployXReserve.sol";
import {ForkTestUtils} from "test/utils/ForkTestUtils.sol";

contract XReserveSetUnlimitedAllowancesTest is DeployXReserve {
    xReserve private reserve;
    FiatTokenV2_2 private token;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    address private gatewayWallet;
    address private tokenMessenger;
    address private tokenMessengerV2;

    uint32 private domain;

    function setUp() public {
        // Get fork variables for contract addresses
        ForkTestUtils.ForkVars memory forkedVars = ForkTestUtils.forkVars();
        domain = forkedVars.domain;
        token = FiatTokenV2_2(forkedVars.usdc);
        gatewayWallet = forkedVars.gatewayWallet;
        tokenMessenger = forkedVars.tokenMessenger;
        tokenMessengerV2 = forkedVars.tokenMessengerV2;

        reserve =
            deployXReserve(owner, domain, forkedVars.gatewayMinter, gatewayWallet, tokenMessenger, tokenMessengerV2);

        // Add token as supported
        vm.prank(owner);
        reserve.addSupportedToken(address(token));
    }

    function test_setUnlimitedAllowances_succeeds() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.prank(user);
        reserve.setUnlimitedAllowances(tokens);

        // Verify allowances were set
        assertEq(IERC20(token).allowance(address(reserve), gatewayWallet), type(uint256).max);
    }

    function test_setUnlimitedAllowances_revertsWhenTokenNotSupported() public {
        // Deploy unsupported token
        FiatTokenV2_2 unsupportedToken = deployMockFiatToken(owner);

        address[] memory tokens = new address[](1);
        tokens[0] = address(unsupportedToken);

        // Should revert on unsupported token
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TokenSupport.UnsupportedToken.selector, address(unsupportedToken)));
        reserve.setUnlimitedAllowances(tokens);
    }

    function test_setUnlimitedAllowances_worksWithMultipleTokens() public {
        // Deploy second token and add it as supported
        FiatTokenV2_2 token2 = deployMockFiatToken(owner);
        vm.prank(owner);
        reserve.addSupportedToken(address(token2));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        vm.prank(user);
        reserve.setUnlimitedAllowances(tokens);

        // Verify allowances were set for both
        assertEq(IERC20(token).allowance(address(reserve), gatewayWallet), type(uint256).max);
        assertEq(IERC20(token2).allowance(address(reserve), gatewayWallet), type(uint256).max);
    }

    function test_setUnlimitedAllowances_restoresUnlimitedAllowance() public {
        // Pre-set a very low allowance on the token
        uint256 lowAllowance = 100;
        vm.prank(address(reserve));
        IERC20(token).approve(gatewayWallet, lowAllowance);

        assertEq(IERC20(token).allowance(address(reserve), gatewayWallet), lowAllowance);

        // Call setUnlimitedAllowances to restore unlimited allowance
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.prank(user);
        reserve.setUnlimitedAllowances(tokens);

        // Verify allowance is now set to max
        assertEq(IERC20(token).allowance(address(reserve), gatewayWallet), type(uint256).max);
    }

    function test_addSupportedToken_autoSetsAllowancesViaOverriddenMethod() public {
        // Deploy a new token that hasn't been added yet
        FiatTokenV2_2 newToken = deployMockFiatToken(owner);

        // Verify initial allowances are 0
        assertEq(IERC20(newToken).allowance(address(reserve), gatewayWallet), 0);
        assertEq(IERC20(newToken).allowance(address(reserve), tokenMessenger), 0);
        assertEq(IERC20(newToken).allowance(address(reserve), tokenMessengerV2), 0);

        // Add the token as supported - this should automatically set all allowances
        vm.prank(owner);
        reserve.addSupportedToken(address(newToken));

        // Verify allowances are now set to max for all three contracts
        assertEq(IERC20(newToken).allowance(address(reserve), gatewayWallet), type(uint256).max);
        assertEq(IERC20(newToken).allowance(address(reserve), tokenMessenger), type(uint256).max);
        assertEq(IERC20(newToken).allowance(address(reserve), tokenMessengerV2), type(uint256).max);

        // Verify the token is supported
        assertTrue(reserve.isTokenSupported(address(newToken)));
    }
}
