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
import {FiatTokenV2_2} from "@gateway/test/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {Test} from "forge-std/Test.sol";
import {xReserve} from "../../src/xReserve.sol";
import {DeployXReserve} from "../utils/DeployXReserve.sol";

contract DeployXReserveTest is Test, DeployXReserve {
    address internal owner = makeAddr("owner");
    uint32 internal domain = 1;

    function test_deployXReserve_success() public {
        // Deploy the mock fiat token first
        FiatTokenV2_2 fiatToken = deployMockFiatToken(owner);
        assert(address(fiatToken) != address(0));

        // Deploy the gateway using the deployGateway helper
        (GatewayWallet gatewayWallet, GatewayMinter gatewayMinter) = deployGateway(
            owner,
            domain,
            address(fiatToken),
            defaultGatewayAttestationSigner,
            defaultGatewayBurnSigner,
            defaultGatewayFeeRecipient
        );
        assert(address(gatewayWallet) != address(0));
        assert(address(gatewayMinter) != address(0));

        address tokenMessenger = deployTokenMessenger(false, owner, domain, address(fiatToken));
        address tokenMessengerV2 = deployTokenMessenger(true, owner, domain, address(fiatToken));

        // Deploy the xReserve using the deployXReserve helper
        xReserve reserve = deployXReserve(
            owner, domain, address(gatewayMinter), address(gatewayWallet), tokenMessenger, tokenMessengerV2
        );

        assert(address(reserve) != address(0));
        assertEq(reserve.owner(), owner);
        assertEq(reserve.domain(), domain);
        assertEq(reserve.gatewayMinter(), address(gatewayMinter));
        assertEq(reserve.gatewayWallet(), address(gatewayWallet));
        assertEq(reserve.tokenMessenger(), tokenMessenger);
        assertEq(reserve.tokenMessengerV2(), tokenMessengerV2);
    }

    function test_deployAndSetupGatewayContracts_success() public {
        // Deploy the mock fiat token first
        FiatTokenV2_2 fiatToken = deployMockFiatToken(owner);

        // Deploy the gateway using the deployGateway helper
        (GatewayWallet gatewayWallet, GatewayMinter gatewayMinter) = deployGateway(
            owner,
            domain,
            address(fiatToken),
            defaultGatewayAttestationSigner,
            defaultGatewayBurnSigner,
            defaultGatewayFeeRecipient
        );

        assert(address(gatewayWallet) != address(0));
        assert(address(gatewayMinter) != address(0));
        // Optionally, check a property of the gateway minter
        assertEq(gatewayMinter.owner(), owner, "GatewayMinter owner should be set");
    }
}
