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

import {IRemoteDomainHookExecutor} from "./../../src/interfaces/IRemoteDomainHookExecutor.sol";
import {DepositParams} from "./../../src/lib/DepositParams.sol";
import {xReserve} from "../../src/xReserve.sol";

/// @title AlwaysSucceedsRemoteDomainHookExecutor
/// @notice A mock remote domain hook executor that always succeeds
contract AlwaysSucceedsRemoteDomainHookExecutor is IRemoteDomainHookExecutor {
    function executeHook(DepositParams calldata depositParams) external pure {
        // Do nothing
    }
}

/// @title AlwaysFailsRemoteDomainHookExecutor
/// @notice A mock remote domain hook executor that always fails
contract AlwaysFailsRemoteDomainHookExecutor is IRemoteDomainHookExecutor {
    error HookExecutionFailed(bytes hookData);

    function executeHook(DepositParams calldata depositParams) external pure {
        revert HookExecutionFailed(depositParams.hookData);
    }
}

contract ReentrantRemoteDomainHookExecutor is IRemoteDomainHookExecutor {
    xReserve private reserve;

    constructor(xReserve xReserve_) {
        reserve = xReserve_;
    }

    function executeHook(DepositParams calldata depositParams) external {
        reserve.depositToRemote(
            depositParams.value,
            depositParams.remoteDomain,
            depositParams.remoteRecipient,
            depositParams.localToken,
            depositParams.maxFee,
            depositParams.hookData
        );
    }
}
