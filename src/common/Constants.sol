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

/// @dev Magic value returned by EIP-1271 compliant contracts for valid signatures
///      bytes4(keccak256("isValidSignature(bytes32,bytes)"))
bytes4 constant EIP1271_VALID_SIGNATURE_MAGIC = 0x1626ba7e;

/// @dev Magic value returned by EIP-1271 compliant contracts for invalid signatures
bytes4 constant EIP1271_INVALID_SIGNATURE_MAGIC = 0xffffffff;

/// @dev Magic value returned for valid persistent signatures in the attestation system
///      bytes4(keccak256("isValidPersistentSignature(bytes32,bytes)"))
bytes4 constant VALID_PERSISTENT_SIGNATURE_MAGIC = 0x8bd40d30;

/// @dev Standard length of an ECDSA signature in bytes: r (32) + s (32) + v (1)
uint256 constant ECDSA_SIGNATURE_LENGTH = 65;

/// @dev Size of bytes4, uint32, bytes32, and uint256 types in bytes
uint8 constant BYTES4_BYTES = 4;
uint8 constant UINT32_BYTES = 4;
uint8 constant BYTES32_BYTES = 32;
uint8 constant UINT256_BYTES = 32;
