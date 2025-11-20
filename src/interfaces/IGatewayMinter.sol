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

/// @title IGatewayMinter
/// @notice Interface for the GatewayMinter contract
interface IGatewayMinter {
    /// @notice Mint funds via a signed attestation. Accepts either a single encoded `Attestation` or several in
    /// an encoded `AttestationSet`. Emits an event containing the `keccak256` hash of the encoded
    /// `TransferSpec` (which is the same for the corresponding burn that will happen on the source domain), to be
    /// used as a cross-chain identifier and for replay protection.
    ///
    /// @dev See `Attestations.sol` for encoding details
    ///
    /// @param attestationPayload   The byte-encoded attestation(s)
    /// @param signature            The signature from a valid attestation signer on `attestationPayload`
    function gatewayMint(bytes memory attestationPayload, bytes memory signature) external;
}
