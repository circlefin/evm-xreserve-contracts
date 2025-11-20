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

/// @title ERC-7597: Permit Extension for Smart Contract Accounts
/// @notice The interface from ERC-7597 that extends EIP-2612 to support contract wallets by using `bytes` rather than
/// `v`, `r`, and `s` for the signature
interface IERC7597 {
    /// @notice Verify a signed approval permit and execute if valid
    /// @dev EOA wallet signatures should be packed in the order of r, s, v.
    /// @param owner       Token owner's address (Authorizer)
    /// @param spender     Spender's address
    /// @param value       Amount of allowance
    /// @param deadline    The time at which the signature expires (unix time), or max uint256 value to signal no
    ///                    expiration
    /// @param signature   Signature byte array signed by an EOA wallet or a contract wallet
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) external;
}
