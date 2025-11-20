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
import {ForkTestUtils} from "./ForkTestUtils.sol";

contract TestForkTestUtils is Test {
    function test_forkVars_ethereum() external {
        vm.chainId(ForkTestUtils.ETHEREUM_CHAIN_ID);
        ForkTestUtils.ForkVars memory vars = ForkTestUtils.forkVars();
        assertEq(vars.usdc, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        assertEq(vars.domain, 0);
        assertEq(vars.gatewayMinter, ForkTestUtils.MAINNET_GATEWAY_MINTER);
        assertEq(vars.gatewayWallet, ForkTestUtils.MAINNET_GATEWAY_WALLET);
        assertEq(vars.tokenMessenger, 0xBd3fa81B58Ba92a82136038B25aDec7066af3155);
        assertEq(vars.tokenMessengerV2, ForkTestUtils.MAINNET_TOKEN_MESSENGER_V2);
    }

    function test_forkVars_local() external {
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);
        vm.chainId(ForkTestUtils.LOCAL_CHAIN_ID);
        ForkTestUtils.ForkVars memory vars = ForkTestUtils.forkVars();

        // Verify that contracts were deployed (non-zero addresses)
        assertTrue(vars.usdc != address(0));
        assertTrue(vars.gatewayMinter != address(0));
        assertTrue(vars.gatewayWallet != address(0));
        assertTrue(vars.tokenMessenger != address(0));
        assertTrue(vars.tokenMessengerV2 != address(0));

        // Verify the domain is correct
        assertEq(vars.domain, ForkTestUtils.LOCAL_DOMAIN, "Domain should be LOCAL_DOMAIN");

        // Verify that the contracts have code (are actual contracts)
        assertTrue(vars.usdc.code.length > 0);
        assertTrue(vars.gatewayMinter.code.length > 0);
        assertTrue(vars.gatewayWallet.code.length > 0);
        assertTrue(vars.tokenMessenger.code.length > 0);
        assertTrue(vars.tokenMessengerV2.code.length > 0);
    }

    function test_forkVars_unknown() external {
        vm.chainId(123);
        vm.expectRevert(abi.encodeWithSelector(ForkTestUtils.UnknownChain.selector, 123));
        ForkTestUtils.forkVars();
    }
}
