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

import {AddressLib} from "src/lib/AddressLib.sol";

/// @title Immutables
/// @notice This contract contains the immutable variables set at deploy time.
contract Immutables {
    /// @dev external immutable contract addresses
    address public immutable gatewayMinter;
    address public immutable gatewayWallet;
    address public immutable tokenMessenger;
    address public immutable tokenMessengerV2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param gatewayMinter_ The address of the GatewayMinter contract
    /// @param gatewayWallet_ The address of the GatewayWallet contract
    /// @param tokenMessenger_ The address of the TokenMessenger contract
    /// @param tokenMessengerV2_ The address of the TokenMessengerV2 contract
    constructor(address gatewayMinter_, address gatewayWallet_, address tokenMessenger_, address tokenMessengerV2_) {
        AddressLib._checkNotZeroAddress(gatewayMinter_);
        AddressLib._checkNotZeroAddress(gatewayWallet_);
        AddressLib._checkNotZeroAddress(tokenMessenger_);
        AddressLib._checkNotZeroAddress(tokenMessengerV2_);

        gatewayMinter = gatewayMinter_;
        gatewayWallet = gatewayWallet_;
        tokenMessenger = tokenMessenger_;
        tokenMessengerV2 = tokenMessengerV2_;
    }
}
