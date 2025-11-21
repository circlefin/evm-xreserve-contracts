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

/// @dev Magic value used to identify WithdrawHookData byte encodings
///      bytes4(keccak256("circle.xReserve.WithdrawHookData"))
bytes4 constant WITHDRAW_HOOK_DATA_MAGIC = 0x6b20f62a;

/// @dev Current version number for WithdrawHookData encoding format
uint32 constant WITHDRAW_HOOK_DATA_VERSION = 1;

/// @dev `WithdrawHookData` field offsets
uint16 constant WITHDRAW_HOOK_DATA_MAGIC_OFFSET = 0;
uint16 constant WITHDRAW_HOOK_DATA_VERSION_OFFSET = 4;
uint16 constant WITHDRAW_HOOK_DATA_REMOTE_DOMAIN_OFFSET = 8;
uint16 constant WITHDRAW_HOOK_DATA_REMOTE_TOKEN_OFFSET = 12;
uint16 constant WITHDRAW_HOOK_DATA_REMOTE_DEPOSITOR_OFFSET = 44;
uint16 constant WITHDRAW_HOOK_DATA_FORWARDING_CONTRACT_OFFSET = 76;
uint16 constant WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_LENGTH_OFFSET = 108;
uint16 constant WITHDRAW_HOOK_DATA_FORWARDING_CALLDATA_OFFSET = 112;

/// @title WithdrawHookData
///
/// @notice Withdrawal hook data for the xReserve
///
/// @dev This struct should be embedded into the BurnIntent hookData field
/// @dev Magic: `bytes4(keccak256("circle.xReserve.WithdrawHookData"))`
///
/// @dev Byte encoding (big-endian):
///     FIELD                   OFFSET   BYTES   NOTES
///     magic                        0       4   Always 0x6b20f62a
///     version                      4       4   == 1
///     remote domain                8       4   Chain where wrapped tokens have been burnt
///     remote token                12      32   Address of the token to deposit on the remote domain
///     remote depositor            44      32   Address of the depositor (source of funds) on the remote domain
///     forwarding contract         76      32   One of TokenMessenger, TokenMessengerV2, or xReserve (as bytes32)
///     forwarding calldata length 108       4   In bytes, may vary
///     forwarding calldata        112       ?   Additional forwarding calldata to be passed to the final destination domain, must be the length specified above
struct WithdrawHookData {
    uint32 version; //               == 1
    uint32 remoteDomain; //          Chain where wrapped tokens have been burnt
    bytes32 remoteToken; //          Address of the token to deposit on the remote domain
    bytes32 remoteDepositor; //      Address of the depositor (source of funds) on the remote domain
    bytes32 forwardingContract; //   One of TokenMessenger, TokenMessengerV2, or xReserve (as bytes32), or zero if no forwarding is needed
    bytes forwardingCalldata; //     Additional forwarding calldata to be passed to the final destination domain, e.g. TokenMessengerCalldata
}
