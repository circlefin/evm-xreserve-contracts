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

/// @title IGatewayWallet
/// @notice Interface for the GatewayWallet contract
interface IGatewayWallet {
    /// @notice Deposits tokens for a specific depositor
    /// @param token The address of the token to deposit
    /// @param depositor The address of the depositor
    /// @param value The amount of tokens to deposit
    function depositFor(address token, address depositor, uint256 value) external;

    /// @notice Returns the available balance of a depositor for a specific token.
    /// @param token The address of the token.
    /// @param depositor The address of the depositor.
    /// @return balance The available balance of the depositor for the token.
    function availableBalance(address token, address depositor) external view returns (uint256);
}
