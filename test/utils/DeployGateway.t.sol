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

import {GatewayMinter} from "@gateway/src/GatewayMinter.sol";
import {GatewayWallet} from "@gateway/src/GatewayWallet.sol";
import {Test} from "forge-std/Test.sol";
import {DeployGateway} from "./DeployGateway.sol";

contract DeployGatewayTest is Test {
    DeployGateway private deployer;
    address private owner = makeAddr("owner");
    uint32 private domain = 99;

    function setUp() public {
        deployer = new DeployGateway();
    }

    function test_deployGatewayContracts_success() public {
        (GatewayWallet wallet, GatewayMinter minter) = deployer.deployGateway(owner, domain);

        // Check that the contracts are deployed to nonzero addresses
        assertTrue(address(wallet) != address(0));
        assertTrue(address(minter) != address(0));

        assertEq(wallet.owner(), owner);
        assertEq(minter.owner(), owner);
        assertEq(wallet.domain(), domain);
        assertEq(minter.domain(), domain);
    }
}
