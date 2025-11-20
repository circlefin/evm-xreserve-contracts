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

import {MasterMinter} from "@gateway/test/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "@gateway/test/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {Test} from "forge-std/Test.sol";
import {DeployMockFiatToken} from "./DeployMockFiatToken.sol";
import {ForkTestUtils} from "./ForkTestUtils.sol";

contract DeployMockFiatTokenTest is Test {
    DeployMockFiatToken private mockTokenDeployer;
    address private owner = makeAddr("owner");

    function setUp() public {
        mockTokenDeployer = new DeployMockFiatToken();
    }

    function test_deployMockFiatToken() public {
        // Skip if not on local chain (redundant safety check)
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);

        FiatTokenV2_2 fiatToken = mockTokenDeployer.deployMockFiatToken(owner);

        FiatTokenProxy fiatTokenAsProxy = FiatTokenProxy(payable(address(fiatToken)));
        assertEq(fiatTokenAsProxy.admin(), makeAddr("fiatTokenProxyAdmin"));
        assertTrue(fiatTokenAsProxy.implementation() != address(0));

        MasterMinter masterMinter = MasterMinter(payable(address(fiatToken.masterMinter())));
        assertEq(masterMinter.owner(), owner);
        assertTrue(address(masterMinter.getMinterManager()) != address(0));

        assertEq(fiatToken.owner(), owner);
        assertEq(fiatToken.pauser(), owner);
        assertEq(fiatToken.blacklister(), owner);
        assertEq(fiatToken.name(), "USDC");
        assertEq(fiatToken.symbol(), "USDC");
        assertEq(fiatToken.currency(), "USD");
        assertEq(fiatToken.decimals(), 6);
    }
}
