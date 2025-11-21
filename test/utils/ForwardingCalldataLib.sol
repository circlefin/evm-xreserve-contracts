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

import {TokenMessenger} from "@cctp/TokenMessenger.sol";
import {TokenMessengerV2} from "@cctp/v2/TokenMessengerV2.sol";
import {DepositToRemote} from "./../../src/modules/x-reserve/DepositToRemote.sol";

/// @title ForwardingCalldataLib
/// @notice Library for encoding forwarding calldata for CCTP v1, v2, and xReserve
library ForwardingCalldataLib {
    uint32 public constant CCTP_DESTINATION_DOMAIN = 5; // Solana
    bytes public constant CCTP_HOOK_DATA = bytes("cctp_hook_data");
    bytes32 public constant CCTP_MINT_RECIPIENT = bytes32("mint_recipient");
    uint32 public constant MIN_FINALITY_THRESHOLD = 1000;

    bytes public constant X_RESERVE_HOOK_DATA = bytes("x_reserve_hook_data");
    bytes32 public constant X_RESERVE_REMOTE_RECIPIENT = bytes32("remote_recipient");

    function encodeCCTPV1DepositForBurn(uint256 amount, address token) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            TokenMessenger.depositForBurn.selector, amount, CCTP_DESTINATION_DOMAIN, CCTP_MINT_RECIPIENT, token
        );
    }

    function encodeCCTPV1DepositForBurnWithCaller(uint256 amount, address token) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            TokenMessenger.depositForBurnWithCaller.selector,
            amount,
            CCTP_DESTINATION_DOMAIN,
            CCTP_MINT_RECIPIENT,
            token,
            bytes32("destination_caller")
        );
    }

    function encodeCCTPV2DepositForBurn(uint256 amount, address token) internal pure returns (bytes memory) {
        uint256 maxFee = amount / 10;
        return abi.encodeWithSelector(
            TokenMessengerV2.depositForBurn.selector,
            amount,
            CCTP_DESTINATION_DOMAIN,
            CCTP_MINT_RECIPIENT,
            token,
            bytes32(0), // destinationCaller
            maxFee,
            MIN_FINALITY_THRESHOLD
        );
    }

    function encodeCCTPV2DepositForBurnWithHook(uint256 amount, address token) internal pure returns (bytes memory) {
        uint256 maxFee = amount / 10;
        return abi.encodeWithSelector(
            TokenMessengerV2.depositForBurnWithHook.selector,
            amount,
            CCTP_DESTINATION_DOMAIN,
            CCTP_MINT_RECIPIENT,
            token,
            bytes32(0),
            maxFee,
            MIN_FINALITY_THRESHOLD,
            CCTP_HOOK_DATA
        );
    }

    function encodeXReserveDepositToRemote(uint256 value, uint32 remoteDomain, address token)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            DepositToRemote.depositToRemote.selector,
            value,
            remoteDomain,
            X_RESERVE_REMOTE_RECIPIENT,
            token,
            0,
            X_RESERVE_HOOK_DATA
        );
    }
}
