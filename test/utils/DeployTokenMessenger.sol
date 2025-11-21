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

import {MessageTransmitter} from "@cctp/MessageTransmitter.sol";
import {AdminUpgradableProxy} from "@cctp/proxy/AdminUpgradableProxy.sol";
import {TokenMessenger} from "@cctp/TokenMessenger.sol";
import {TokenMinter} from "@cctp/TokenMinter.sol";
import {MessageTransmitterV2} from "@cctp/v2/MessageTransmitterV2.sol";
import {TokenMessengerV2} from "@cctp/v2/TokenMessengerV2.sol";
import {TokenMinterV2} from "@cctp/v2/TokenMinterV2.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Helpers for deploying the contracts during tests
contract DeployTokenMessenger is Test {
    uint32 public constant MAX_MESSAGE_BODY_SIZE = 1000;
    uint256 public constant MAX_BURN_AMOUNT_PER_MESSAGE = 1000000000000000000;
    address private attester = makeAddr("attester");
    address private attester2 = makeAddr("attester2");
    address private attesterManager = makeAddr("attesterManager");

    function deployTokenMessengerAndMinterV1(address owner, uint32 domain)
        public
        returns (TokenMessenger, TokenMinter)
    {
        vm.startPrank(owner);
        {
            MessageTransmitter mt = new MessageTransmitter(domain, attester, MAX_MESSAGE_BODY_SIZE, 1);
            TokenMinter minter = new TokenMinter(owner); // set token controller to owner
            TokenMessenger tm = new TokenMessenger(address(mt), 1);
            tm.addLocalMinter(address(minter));
            minter.addLocalTokenMessenger(address(tm));
            return (tm, minter);
        }
    }

    function deployTokenMessengerAndMinterV2(address owner, uint32 domain)
        public
        returns (TokenMessengerV2, TokenMinterV2)
    {
        vm.startPrank(owner);
        {
            // Deploy the token minter
            TokenMinterV2 minterV2 = new TokenMinterV2(owner);

            // Deploy the message transmitter
            MessageTransmitterV2 mtImpl = new MessageTransmitterV2(domain, 2);
            AdminUpgradableProxy mtProxy = _deployProxy(makeAddr("mtAdmin"), address(mtImpl));
            MessageTransmitterV2 mtV2 = MessageTransmitterV2(address(mtProxy));

            address[] memory attesters = new address[](2);
            attesters[0] = attester;
            attesters[1] = attester2;
            mtV2.initialize(
                owner,
                owner, // pauser
                owner, // rescuer
                attesterManager,
                attesters,
                2, // signatureThreshold
                MAX_MESSAGE_BODY_SIZE
            );

            // Deploy the token messenger
            TokenMessengerV2 tmImpl = new TokenMessengerV2(address(mtV2), 2);
            AdminUpgradableProxy tmProxy = _deployProxy(makeAddr("tmAdmin"), address(tmImpl));
            TokenMessengerV2 tmV2 = TokenMessengerV2(address(tmProxy));
            minterV2.addLocalTokenMessenger(address(tmV2));

            tmV2.initialize(
                TokenMessengerV2.TokenMessengerV2Roles({
                    owner: owner,
                    rescuer: owner, // rescuer
                    feeRecipient: owner,
                    denylister: owner,
                    tokenMinter: address(minterV2),
                    minFeeController: owner
                }),
                MAX_MESSAGE_BODY_SIZE,
                new uint32[](0),
                new bytes32[](0)
            );
            return (tmV2, minterV2);
        }
    }

    function _deployProxy(address admin, address implementation) internal returns (AdminUpgradableProxy) {
        return new AdminUpgradableProxy(implementation, admin, bytes(""));
    }
}
