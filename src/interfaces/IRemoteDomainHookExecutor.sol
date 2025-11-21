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

import {DepositParams} from "../lib/DepositParams.sol";

/// @title IRemoteDomainHookExecutor
/// @notice Interface for the RemoteDomainHookExecutor contract
interface IRemoteDomainHookExecutor {
    /// @notice Executes a hook for a remote domain
    /// @dev The implementation of this hook should treat `depositParams` as untrusted
    ///      user input and validate it accordingly. This hook is executed within
    ///      the `depositToRemote` transaction, and if it reverts, the entire
    ///      transaction will be reverted.
    /// @param depositParams The data to be passed to the hook
    function executeHook(DepositParams calldata depositParams) external;
}
