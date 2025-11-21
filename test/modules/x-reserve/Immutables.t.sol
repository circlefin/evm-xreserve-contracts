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
import {ZeroAddress} from "src/common/Errors.sol";
import {Immutables} from "src/modules/x-reserve/Immutables.sol";

contract ImmutablesTest is Test, Immutables {
    address internal constant GATEWAY_MINTER = address(0x1111);
    address internal constant GATEWAY_WALLET = address(0x2222);
    address internal constant TOKEN_MESSENGER = address(0x3333);
    address internal constant TOKEN_MESSENGER_V2 = address(0x4444);

    constructor() Immutables(GATEWAY_MINTER, GATEWAY_WALLET, TOKEN_MESSENGER, TOKEN_MESSENGER_V2) {}

    function test_immutablesAreSetCorrectly() public view {
        assertEq(gatewayMinter, GATEWAY_MINTER, "gatewayMinter not set correctly");
        assertEq(gatewayWallet, GATEWAY_WALLET, "gatewayWallet not set correctly");
        assertEq(tokenMessenger, TOKEN_MESSENGER, "tokenMessenger not set correctly");
        assertEq(tokenMessengerV2, TOKEN_MESSENGER_V2, "tokenMessengerV2 not set correctly");
    }

    function test_revertsOnZeroGatewayMinter() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new Immutables(address(0), GATEWAY_WALLET, TOKEN_MESSENGER, TOKEN_MESSENGER_V2);
    }

    function test_revertsOnZeroGatewayWallet() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new Immutables(GATEWAY_MINTER, address(0), TOKEN_MESSENGER, TOKEN_MESSENGER_V2);
    }

    function test_revertsOnZeroTokenMessenger() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new Immutables(GATEWAY_MINTER, GATEWAY_WALLET, address(0), TOKEN_MESSENGER_V2);
    }

    function test_revertsOnZeroTokenMessengerV2() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new Immutables(GATEWAY_MINTER, GATEWAY_WALLET, TOKEN_MESSENGER, address(0));
    }
}
