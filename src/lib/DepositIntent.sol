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

/// @dev Magic value used to identify DepositIntent byte encodings
/// bytes4(keccak256("circle.xReserve.DepositIntent"))
bytes4 constant DEPOSIT_INTENT_MAGIC = 0x5a2e0acd;

/// @dev Version for marking byte encodings for easier forward compatibility
uint32 constant DEPOSIT_INTENT_VERSION = 1;

/// @dev `DepositIntent` field offsets
uint16 constant DEPOSIT_INTENT_MAGIC_OFFSET = 0;
uint16 constant DEPOSIT_INTENT_VERSION_OFFSET = 4;
uint16 constant DEPOSIT_INTENT_AMOUNT_OFFSET = 8;
uint16 constant DEPOSIT_INTENT_REMOTE_DOMAIN_OFFSET = 40;
uint16 constant DEPOSIT_INTENT_REMOTE_TOKEN_OFFSET = 44;
uint16 constant DEPOSIT_INTENT_REMOTE_RECIPIENT_OFFSET = 76;
uint16 constant DEPOSIT_INTENT_LOCAL_TOKEN_OFFSET = 108;
uint16 constant DEPOSIT_INTENT_LOCAL_DEPOSITOR_OFFSET = 140;
uint16 constant DEPOSIT_INTENT_MAX_FEE_OFFSET = 172;
uint16 constant DEPOSIT_INTENT_NONCE_OFFSET = 204;
uint16 constant DEPOSIT_INTENT_HOOK_DATA_LENGTH_OFFSET = 236;
uint16 constant DEPOSIT_INTENT_HOOK_DATA_OFFSET = 240;

/// @title DepositIntent
///
/// @notice Represents a user's intent to deposit tokens on the local domain for transferring to a remote domain
///
/// @dev Magic: `bytes4(keccak256("circle.xReserve.DepositIntent"))`
/// @dev The `nonce` field is used for replay protection and could be set to the deposit transaction hash
/// @dev Byte encoding (big-endian):
///     FIELD                   OFFSET   BYTES   NOTES
///     magic                        0       4   Always 0x5a2e0acd
///     version                      4       4   Version number, padded to 4 bytes for alignment
///     amount                       8      32   Amount of tokens to deposit
///     remote domain               40       4   Domain where wrapped tokens will be issued
///     remote token                44      32   Address of token on remote domain
///     remote recipient            76      32   Address of recipient on remote domain
///     local token                108      32   Address of token on local domain (address padded to bytes32)
///     local depositor            140      32   Address of depositor on local domain (address padded to bytes32)
///     max fee                    172      32   Maximum fee to pay on destination domain
///     nonce                      204      32   Arbitrary value to prevent replay
///     hook data length           236       4   Length of hook data in bytes
///     hook data                  240       ?   Optional hook for execution on destination domain
struct DepositIntent {
    uint32 version; //           Version number, should be 1
    uint256 amount; //           Amount of tokens to deposit
    uint32 remoteDomain; //      Domain where wrapped tokens will be issued
    bytes32 remoteToken; //      Address of the token to deposit on the remote domain
    bytes32 remoteRecipient; //  Address of the recipient on the remote domain
    bytes32 localToken; //       Address of the token to deposit on the local domain (as bytes32)
    bytes32 localDepositor; //   Address of the depositor on the local domain (as bytes32)
    uint256 maxFee; //           Maximum fee to pay on destination domain, in units of localToken
    bytes32 nonce; //            Arbitrary value to prevent replay
    bytes hookData; //           Optional hook for execution on destination domain
}
