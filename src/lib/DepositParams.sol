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

/// @notice Parameters for deposit and transfer operations
struct DepositParams {
    uint256 value;
    uint32 remoteDomain;
    bytes32 remoteRecipient;
    address localToken;
    uint256 maxFee;
    bytes hookData;
}

/// @notice Parameters for EIP-2612/EIP-7597 permit operations
struct PermitParams {
    address owner;
    uint256 deadline;
    bytes signature;
}

/// @notice Parameters for ERC-3009/ERC-7598 authorization operations
struct AuthorizationParams {
    address from;
    uint256 validAfter;
    uint256 validBefore;
    bytes32 nonce;
    bytes signature;
}
