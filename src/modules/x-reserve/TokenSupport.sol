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

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {Immutables} from "./Immutables.sol";

/// @title TokenSupport
///
/// @notice Manages a set of tokens that are supported, and allows the owner to mark new tokens as supported
abstract contract TokenSupport is Ownable2StepUpgradeable, Immutables {
    using SafeERC20 for IERC20;

    /// Emitted when a token is added to the set of supported tokens
    ///
    /// @param token   The token that is now supported
    event TokenSupported(address indexed token);

    /// Thrown when an unsupported token is used
    ///
    /// @param token   The unsupported token
    error UnsupportedToken(address token);

    /// Initializes supported tokens
    ///
    /// @param supportedTokens_   The initially-supported tokens
    function __TokenSupport_init(address[] calldata supportedTokens_) internal onlyInitializing {
        for (uint256 i = 0; i < supportedTokens_.length; i++) {
            _addSupportedToken(supportedTokens_[i]);
        }
    }

    /// Whether or not a token is supported
    ///
    /// @param token   The token to check
    /// @return        `true` if the token is supported, `false` otherwise
    function isTokenSupported(address token) public view returns (bool) {
        return TokenSupportStorage.get().supportedTokens[token];
    }

    /// Marks a token as supported. Once supported, tokens cannot be un-supported.
    ///
    /// @dev May only be called by the `owner` role
    ///
    /// @param token   The token to be added
    function addSupportedToken(address token) external onlyOwner {
        _addSupportedToken(token);
    }

    /// Internal function to add a supported token
    ///
    /// @param token   The token to be added
    function _addSupportedToken(address token) internal {
        AddressLib._checkNotZeroAddress(token);

        TokenSupportStorage.Data storage $ = TokenSupportStorage.get();
        if (!$.supportedTokens[token]) {
            $.supportedTokens[token] = true;
            emit TokenSupported(token);

            // Set unlimited allowances for relevant contracts
            _setUnlimitedAllowances(token);
        }
    }

    /// Reverts if the given token is not supported
    ///
    /// @param token   The token to check
    function _ensureTokenSupported(address token) internal view {
        if (!isTokenSupported(token)) {
            revert UnsupportedToken(token);
        }
    }

    /// @notice Sets unlimited allowances for a token to relevant contracts
    ///
    /// @param token The token to set allowances for
    function _setUnlimitedAllowances(address token) internal {
        // Set unlimited allowance for gatewayWallet, CCTP, and CCTP V2
        IERC20(token).forceApprove(address(gatewayWallet), type(uint256).max);
        IERC20(token).forceApprove(address(tokenMessenger), type(uint256).max);
        IERC20(token).forceApprove(address(tokenMessengerV2), type(uint256).max);
    }
}

/// @title TokenSupportStorage
///
/// @notice Implements the EIP-7201 storage pattern for the `TokenSupport` module
library TokenSupportStorage {
    /// @custom:storage-location erc7201:circle.xReserve.TokenSupport
    struct Data {
        /// Whether or not a token is supported
        mapping(address token => bool supported) supportedTokens;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.TokenSupport"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x3630dbf8799c23cdb29523cafe2b04203ab0622ee7e77cc015c2780e9d22b100;

    /// EIP-7201 getter for the storage slot
    ///
    /// @return $   The storage struct for the `TokenSupport` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
