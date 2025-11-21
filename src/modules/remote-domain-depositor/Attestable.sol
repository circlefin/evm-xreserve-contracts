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

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AddressLib} from "src/lib/AddressLib.sol";
import {ECDSA_SIGNATURE_LENGTH} from "./../../common/Constants.sol";
import {
    EIP1271_VALID_SIGNATURE_MAGIC,
    EIP1271_INVALID_SIGNATURE_MAGIC,
    VALID_PERSISTENT_SIGNATURE_MAGIC
} from "./../../common/Constants.sol";
import {DomainManageable} from "./DomainManageable.sol";

/// @title Attestable
/// @notice Contract module for managing attesters and verifying multi-signature attestations.
/// @dev This contract implements a sophisticated multi-signature validation system with graceful configuration transitions.
///
/// Key Mechanisms:
/// 1. **Dual-Validity During Transitions**: When configuration changes occur (threshold updates or attester removal),
///    the contract maintains validity of both old and new configurations during a delay period. This prevents
///    service disruption and allows time for signature regeneration.
///
/// 2. **Signature Threshold Management**:
///    - During normal operation: Signatures must have EXACTLY the active threshold number of attesters
///    - During threshold changes: Both previous and current thresholds are valid for the delay period
///    - After delay period: Only the new threshold is valid
///    - Example: If threshold changes from 3 to 5, during the delay period, signatures with either 3 or 5 attesters are valid
///
/// 3. **Attester Management**:
///    - Enabling attesters: Takes effect immediately
///    - Disabling attesters: Attester remains valid during a configurable delay period
///    - During the delay: The attester can still sign valid attestations
///    - After the delay: The attester is fully disabled and signatures from them are rejected
///
/// 4. **Two Validation Modes**:
///    - `isValidSignature()`: Standard validation accepting attesters and thresholds in transition
///    - `isValidPersistentSignature()`: Strict validation using only target configuration (ignores delays)
///
/// 5. **Delay Configuration**:
///    - `persistentSignatureBufferDelayBlocks`: Configurable delay in blocks for all transitions
///    - Applies to both threshold changes (all changes) and attester removal
///    - Provides time for off-chain systems to adapt to configuration changes
///
/// Terminology:
/// - Persistent attesters: Attesters that remain enabled after the delay period
/// - Current signature threshold: The signature threshold that becomes active after the delay period
/// - Previous signature threshold: The signature threshold that is active during the delay period
///
/// This design ensures high availability during configuration updates while maintaining security through
/// the exact threshold requirement and ordered, unique attester signatures.
contract Attestable is DomainManageable, IERC1271 {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Constants ============

    /// @notice Minimum signature threshold for attesters
    uint256 public constant MIN_SIGNATURE_THRESHOLD = 2;

    // ============ Custom Errors ============

    /// @notice Thrown when attester is already enabled
    /// @param attester The attester address that is already enabled
    error AttesterAlreadyEnabled(address attester);

    /// @notice Thrown when signature threshold is too low for the operation
    /// @param currentCount The current number of enabled attesters
    /// @param required The required number of attesters
    error NotEnoughAttestersForSigThreshold(uint256 currentCount, uint256 required);

    /// @notice Thrown when attester is not enabled
    /// @param attester The attester address that is not enabled
    error AttesterAlreadyDisabled(address attester);

    /// @notice Thrown when signature threshold is invalid (zero)
    error SignatureThresholdZero();

    /// @notice Thrown when signature threshold is too high
    /// @param threshold The proposed threshold
    /// @param maxAllowed The maximum allowed threshold (number of enabled attesters)
    error SignatureThresholdTooHigh(uint256 threshold, uint256 maxAllowed);

    /// @notice Thrown when signature threshold is already set to the same value
    /// @param currentThreshold The current threshold value
    error SignatureThresholdAlreadySet(uint256 currentThreshold);

    /// @notice Thrown when signature threshold is below the minimum required threshold
    /// @param threshold The proposed threshold
    /// @param minThreshold The minimum required threshold
    error SignatureThresholdBelowMinimum(uint256 threshold, uint256 minThreshold);

    /// @notice Thrown when persistent signature buffer delay is already set to the same value
    /// @param currentDelay The current delay value
    error PersistentSignatureBufferDelayAlreadySet(uint256 currentDelay);

    /// @notice Thrown when persistent signature buffer delay must be greater than zero
    error PersistentSignatureBufferDelayZero();

    /// @notice Thrown when attempting to update signature threshold while another update is in progress
    /// @param pendingThreshold The pending signature threshold
    /// @param validUntilBlock The block number until which the old signature threshold will remain valid
    error SignatureThresholdUpdateInProgress(uint256 pendingThreshold, uint256 validUntilBlock);

    // ============ Events ============

    /// @notice Emitted when an attester is enabled
    /// @param attester The address of the enabled attester
    event AttesterEnabled(address indexed attester);

    /// @notice Emitted when an attester disable request is initiated
    /// @param attester The address of the attester to be disabled
    /// @param validUntilBlock The block number until which the attester remains valid
    event AttesterDisabled(address indexed attester, uint256 validUntilBlock);

    /// @notice Emitted when threshold number of attestations (m in m/n multisig) is updated
    /// @param oldSignatureThreshold The old signature threshold
    /// @param newSignatureThreshold The new signature threshold
    event SignatureThresholdUpdated(uint256 oldSignatureThreshold, uint256 newSignatureThreshold);

    /// @notice Emitted when persistent signature buffer delay is updated
    /// @param oldDelay The old buffer delay in blocks
    /// @param newDelay The new buffer delay in blocks
    event PersistentSignatureBufferDelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// @notice Initializes the `Attestable` state with time delay functionality
    /// @param _attesters The addresses of the attesters
    /// @param _signatureThreshold The threshold of signatures required to attest to a message
    /// @param _persistentSignatureBufferDelayBlocks The number of blocks to delay when disabling attesters and changing signature thresholds
    function __Attestable_init(
        address[] memory _attesters,
        uint256 _signatureThreshold,
        uint256 _persistentSignatureBufferDelayBlocks
    ) internal onlyInitializing {
        _setPersistentSignatureBufferDelay(_persistentSignatureBufferDelayBlocks);

        for (uint256 i = 0; i < _attesters.length; i++) {
            _enableAttester(_attesters[i]);
        }
        _initializeSignatureThreshold(_signatureThreshold);
    }

    // ============ View Functions ============

    /// @notice Returns the active signature threshold that will be used for signature validation
    /// @return The active signature threshold (previous threshold during delay period, otherwise target threshold)
    function signatureThreshold() external view returns (uint256) {
        AttestableStorage.Data storage $ = AttestableStorage.get();
        return block.number <= $.prevSigThresholdValidUntilBlock ? $.prevSigThreshold : $.curSigThreshold;
    }

    /// @notice Returns the block number until which the previous signature threshold remains valid
    /// @return The block number until which the previous threshold remains valid (0 if no delay in progress)
    function signatureThresholdValidUntilBlock() external view returns (uint256) {
        return AttestableStorage.get().prevSigThresholdValidUntilBlock;
    }

    /// @notice Returns the target signature threshold
    /// @return The target signature threshold (becomes active immediately if no delay, or after delay period)
    function nextSignatureThreshold() external view returns (uint256) {
        return AttestableStorage.get().curSigThreshold;
    }

    /// @notice Returns the number of enabled attesters
    /// @return The number of enabled attesters
    function numPersistentEnabledAttesters() public view returns (uint256) {
        return AttestableStorage.get().persistentEnabledAttesters.length();
    }

    /// @notice Returns whether an attester is valid for signature verification
    /// @param attester The attester address to check
    /// @return True if the attester is persistently enabled OR still within their disable delay period, false otherwise
    function isAttesterEnabled(address attester) public view returns (bool) {
        AttestableStorage.Data storage $ = AttestableStorage.get();
        return $.persistentEnabledAttesters.contains(attester) || block.number <= $.attestersValidUntilBlock[attester];
    }

    /// @notice Returns all persistently enabled attesters (excludes those being disabled)
    /// @return An array of persistently enabled attester addresses (does not include attesters in disable delay period)
    function persistentEnabledAttesters() external view returns (address[] memory) {
        return AttestableStorage.get().persistentEnabledAttesters.values();
    }

    /// @notice Returns the block number until which an attester is valid (applicable only if it is pending removal)
    /// @dev This value is only meaningful if the attester is pending removal.
    ///      Returns 0 if the attester is persistent, or was never an attester.
    /// @param attester The attester address to check
    /// @return The block number until which the attester is valid
    function attesterValidUntilBlock(address attester) external view returns (uint256) {
        return AttestableStorage.get().attestersValidUntilBlock[attester];
    }

    /// @notice Returns the persistent signature buffer delay in blocks
    /// @return The number of blocks to delay when disabling attesters and increasing signature thresholds
    function persistentSignatureBufferDelayBlocks() external view returns (uint256) {
        return AttestableStorage.get().persistentSignatureBufferDelayBlocks;
    }

    // ============ External Functions  ============

    /// @notice Enables an attester
    /// @dev Only callable by domainManager. New attester must be nonzero. This function reverts if the attester is already enabled.
    /// @param newAttester attester to enable
    function enableAttester(address newAttester) external onlyDomainManager {
        _enableAttester(newAttester);
    }

    /// @notice Disables an attester
    /// @dev Only callable by domainManager. The attester remains valid for signatures during the delay period.
    /// Disabling is not allowed if it would leave fewer than MIN_SIGNATURE_THRESHOLD persistent attesters,
    /// or fewer persistent attesters than the target signature threshold.
    /// @param attester attester to disable
    function disableAttester(address attester) external onlyDomainManager {
        AttestableStorage.Data storage data = AttestableStorage.get();
        EnumerableSet.AddressSet storage _persistentEnabledAttesters = data.persistentEnabledAttesters;

        if (!_persistentEnabledAttesters.contains(attester)) {
            revert AttesterAlreadyDisabled(attester);
        }

        uint256 _numPersistentEnabledAttesters = _persistentEnabledAttesters.length();

        // Check threshold constraints after confirming attester can be disabled
        if (_numPersistentEnabledAttesters <= data.curSigThreshold) {
            // We check against curSigThreshold (the target threshold) rather than the active threshold
            // to ensure we maintain enough attesters for the target configuration.
            revert NotEnoughAttestersForSigThreshold(_numPersistentEnabledAttesters, data.curSigThreshold);
        }

        uint256 validUntilBlock = block.number + data.persistentSignatureBufferDelayBlocks;
        data.attestersValidUntilBlock[attester] = validUntilBlock;
        _persistentEnabledAttesters.remove(attester);

        emit AttesterDisabled(attester, validUntilBlock);
    }

    /// @notice Sets the threshold of signatures required to attest to a message
    /// @dev Updates the signature threshold with a delay period for all changes (increases and decreases).
    /// During the delay, both old and new thresholds are valid for signatures.
    /// IMPORTANT: After the delay, signatures must have EXACTLY the new threshold number of attesters.
    /// @param newSignatureThreshold new signature threshold
    function setSignatureThreshold(uint256 newSignatureThreshold) external onlyDomainManager {
        _setSignatureThreshold(newSignatureThreshold);
    }

    /// @notice Sets the delay in blocks for disabling attesters and increasing signature thresholds
    /// @dev Only callable by owner. This function allows the owner to update the persistent signature buffer delay.
    /// @param newDelay The new delay in blocks
    function setPersistentSignatureBufferDelay(uint256 newDelay) external onlyOwner {
        _setPersistentSignatureBufferDelay(newDelay);
    }

    /// @notice Validates if the provided signature is valid for the given hash
    /// @dev This function implements ERC-1271 signature validation. It accepts signatures from attesters that are either:
    /// - Persistently enabled, OR
    /// - In the process of being disabled (still within their delay period)
    /// The number of signatures must EXACTLY match either:
    /// - The previous threshold (if within threshold change delay period), OR
    /// - The target threshold (if no delay or after delay period)
    /// The signature parameter should contain concatenated 65-byte ECDSA signatures from valid attesters in ascending order of their addresses.
    /// @param hash The hash of the data that was signed
    /// @param signature Concatenated signatures from persistently enabled attesters or attesters in the process of being disabled (65 bytes each, count must equal active threshold)
    /// @return magicValue Returns 0x1626ba7e if the signature is valid, 0xffffffff otherwise
    /// @custom:security Signatures must have EXACTLY the threshold number of attesters - more or fewer will be rejected
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue) {
        return _isValidSignatureHelper(hash, signature, false)
            ? EIP1271_VALID_SIGNATURE_MAGIC
            : EIP1271_INVALID_SIGNATURE_MAGIC;
    }

    /// @notice Validates if the provided signature is valid for the given hash using only persistently enabled attesters
    /// @dev This function implements stricter signature validation:
    /// - Only accepts signatures from persistently enabled attesters (excludes those being disabled, even if within delay period)
    /// - Always uses the target threshold (even during a threshold change delay period)
    /// - Number of signatures must EXACTLY match the target threshold
    /// The signature parameter should contain concatenated 65-byte ECDSA signatures from persistently enabled attesters in ascending order of their addresses.
    /// @param hash The hash of the data that was signed
    /// @param signature Concatenated signatures from persistently enabled attesters (65 bytes each, count must equal target threshold)
    /// @return magicValue Returns 0x8d3df49d if the signature is valid, 0xffffffff otherwise
    /// @custom:security Signatures must have EXACTLY the target threshold number of persistently enabled attesters
    function isValidPersistentSignature(bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue)
    {
        return _isValidSignatureHelper(hash, signature, true)
            ? VALID_PERSISTENT_SIGNATURE_MAGIC
            : EIP1271_INVALID_SIGNATURE_MAGIC;
    }

    /// @notice Internal helper to validate signatures with configurable attester checking
    /// @dev This function implements signature validation with two modes:
    /// - requirePersistence=false: Accepts attesters that are persistently enabled OR in disable delay period,
    ///   validates against either previous threshold (if in delay) or target threshold
    /// - requirePersistence=true: Only accepts persistently enabled attesters, always validates against target threshold
    /// The signature must contain EXACTLY the required number of signatures (not more, not less).
    /// @param hash The hash of the data that was signed
    /// @param signature Concatenated 65-byte ECDSA signatures from attesters in ascending order of addresses
    /// @param requirePersistence If true, use stricter validation (persistent attesters only, target threshold only)
    /// @return isValid Returns true if the signature is valid, false otherwise
    function _isValidSignatureHelper(bytes32 hash, bytes calldata signature, bool requirePersistence)
        internal
        view
        returns (bool isValid)
    {
        AttestableStorage.Data storage $ = AttestableStorage.get();

        // Load current signature threshold once from storage to avoid multiple SLOADs
        uint256 curSigThreshold = $.curSigThreshold;

        // Check module has been initialized and signature length is a valid ECDSA signature multiple
        if (curSigThreshold == 0 || signature.length % ECDSA_SIGNATURE_LENGTH != 0) {
            return false;
        }

        // Check that the number of signers is an allowed amount
        // IMPORTANT: The number of signatures must EXACTLY match the threshold (not >= threshold)
        // This means that changing the threshold will invalidate signatures with different attester counts
        uint256 numSignatures = signature.length / ECDSA_SIGNATURE_LENGTH;
        if (requirePersistence && numSignatures != curSigThreshold) {
            // When persistence is required, the number of signers must be the persistent signature threshold
            return false;
        } else if (
            !requirePersistence && numSignatures != curSigThreshold
                && (numSignatures != $.prevSigThreshold || block.number > $.prevSigThresholdValidUntilBlock)
        ) {
            // When persistence is not required, the number of signers must be either the current signature threshold or the persistent signature threshold.
            return false;
        }

        // (Attesters cannot be address(0))
        address _latestAttesterAddress = address(0);

        for (uint256 i; i < numSignatures; ++i) {
            bytes32 r;
            bytes32 s;
            uint8 v;

            // Extract signature components using assembly for gas efficiency
            assembly {
                // Calculate the position of the current signature in calldata
                // Each signature is 65 bytes (32 + 32 + 1)
                let signatureStart := add(signature.offset, mul(i, 65))
                // Load the r value (32 bytes)
                r := calldataload(signatureStart)
                // Load the s value (32 bytes)
                s := calldataload(add(signatureStart, 32))
                // Load the v value (1 byte)
                v := byte(0, calldataload(add(signatureStart, 64)))
            }
            address _recoveredAttester = ECDSA.recover(hash, v, r, s);

            // Signatures must be in increasing order of address, and may not duplicate signatures from same address
            if (_recoveredAttester <= _latestAttesterAddress) {
                return false;
            }

            // Check attester validity based on the persistence requirement
            if (requirePersistence && !$.persistentEnabledAttesters.contains(_recoveredAttester)) {
                return false;
            } else if (!requirePersistence && !isAttesterEnabled(_recoveredAttester)) {
                // When persistence is not required, attesters must either be persistently enabled or still within their disable delay period
                return false;
            }
            _latestAttesterAddress = _recoveredAttester;
        }

        return true;
    }

    // ============ Internal Utils ============

    /// @notice Internal function to enable an attester
    /// @dev Adds the attester to the persistent enabled set and clears any pending disable
    /// @dev Emits an {AttesterEnabled} event
    /// @dev Reverts if the attester address is zero or already enabled
    /// @param newAttester The address of the attester to enable
    function _enableAttester(address newAttester) internal {
        AddressLib._checkNotZeroAddress(newAttester);

        AttestableStorage.Data storage data = AttestableStorage.get();

        if (!data.persistentEnabledAttesters.add(newAttester)) {
            revert AttesterAlreadyEnabled(newAttester);
        }

        // Clear any pending disable for this attester
        delete data.attestersValidUntilBlock[newAttester];

        emit AttesterEnabled(newAttester);
    }

    /// @notice Internal function to validate a signature threshold value
    /// @dev Ensures the threshold is non-zero, meets the minimum requirement, and doesn't exceed the number of enabled attesters
    /// @dev Reverts with appropriate error if validation fails
    /// @param _signatureThreshold The signature threshold value to validate
    function _validateSignatureThreshold(uint256 _signatureThreshold) internal view {
        if (_signatureThreshold == 0) {
            revert SignatureThresholdZero();
        }

        // New signature threshold must be at least the minimum required threshold
        if (_signatureThreshold < MIN_SIGNATURE_THRESHOLD) {
            revert SignatureThresholdBelowMinimum(_signatureThreshold, MIN_SIGNATURE_THRESHOLD);
        }

        // New signature threshold cannot exceed the number of enabled attesters
        uint256 _numPersistentEnabledAttesters = numPersistentEnabledAttesters();
        if (_signatureThreshold > _numPersistentEnabledAttesters) {
            // We validate against persistent attesters only. Attesters being disabled (in delay period)
            // can still sign during their delay, so having enough persistent attesters ensures sufficient signers.
            revert SignatureThresholdTooHigh(_signatureThreshold, _numPersistentEnabledAttesters);
        }
    }

    /// @notice Internal function to initialize the signature threshold during contract setup
    /// @dev Sets the initial signature threshold without any time delay and emits an event
    /// @dev Validates the threshold value before setting it
    /// @param _newSignatureThreshold The initial signature threshold value to set
    function _initializeSignatureThreshold(uint256 _newSignatureThreshold) internal {
        _validateSignatureThreshold(_newSignatureThreshold);

        AttestableStorage.Data storage $ = AttestableStorage.get();
        $.curSigThreshold = _newSignatureThreshold;
        $.prevSigThresholdValidUntilBlock = 0;
        emit SignatureThresholdUpdated(0, _newSignatureThreshold);
    }

    /**
     * @notice Sets the threshold of signatures required to attest to a message.
     * (This is the m in m/n multisig.)
     * @dev New signature threshold must be nonzero, and must not exceed number
     * of enabled attesters.
     * WARNING: Changing the threshold (either increasing OR decreasing) will invalidate
     * any existing signatures that don't have exactly the new threshold number of attesters.
     * A delay period is applied to allow time for signature regeneration.
     * @param _newSignatureThreshold new signature threshold
     */
    function _setSignatureThreshold(uint256 _newSignatureThreshold) internal {
        _validateSignatureThreshold(_newSignatureThreshold);

        AttestableStorage.Data storage $ = AttestableStorage.get();

        // For simplicity, wait until all current signature threshold updates are finished before initiating a new one.
        if (block.number <= $.prevSigThresholdValidUntilBlock) {
            revert SignatureThresholdUpdateInProgress($.curSigThreshold, $.prevSigThresholdValidUntilBlock);
        }

        // At this point, we know there are no pending signature threshold updates. Update the signature threshold
        // immediately or schedule an update, depending on the new value.
        uint256 _oldSignatureThreshold = $.curSigThreshold;
        if (_newSignatureThreshold == _oldSignatureThreshold) {
            revert SignatureThresholdAlreadySet(_oldSignatureThreshold);
        }

        // Apply a buffer delay for ALL threshold changes (both increases and decreases)
        // to allow existing signatures time to be regenerated with the new threshold count.
        // WARNING: After the delay, signatures with a different number of attesters than the new threshold will become invalid.
        // For example, if threshold changes from 5 to 3, signatures with 4 or 5 attesters will be rejected after the delay.
        // Similarly, if threshold changes from 3 to 5, signatures with 3 or 4 attesters will be rejected after the delay.
        $.prevSigThreshold = _oldSignatureThreshold;
        $.curSigThreshold = _newSignatureThreshold;
        $.prevSigThresholdValidUntilBlock = block.number + $.persistentSignatureBufferDelayBlocks;

        emit SignatureThresholdUpdated(_oldSignatureThreshold, _newSignatureThreshold);
    }

    /**
     * @notice Sets the delay in blocks for disabling attesters and changing signature thresholds
     * @param _newDelay The new delay in blocks
     */
    function _setPersistentSignatureBufferDelay(uint256 _newDelay) internal {
        AttestableStorage.Data storage $ = AttestableStorage.get();
        uint256 _oldDelay = $.persistentSignatureBufferDelayBlocks;
        if (_newDelay == 0) {
            revert PersistentSignatureBufferDelayZero();
        }
        if (_newDelay == _oldDelay) {
            revert PersistentSignatureBufferDelayAlreadySet(_oldDelay);
        }

        $.persistentSignatureBufferDelayBlocks = _newDelay;
        emit PersistentSignatureBufferDelayUpdated(_oldDelay, _newDelay);
    }
}

/// @title AttestableStorage
/// @notice Implements the EIP-7201 storage pattern for the `Attestable` module
library AttestableStorage {
    /// @custom:storage-location erc7201:circle.xReserve.Attestable
    struct Data {
        /// Previous signature threshold (active during delay period)
        uint256 prevSigThreshold;
        /// Block number until which the previous signature threshold is valid
        uint256 prevSigThresholdValidUntilBlock;
        /// Current signature threshold (target threshold after delay if update is in progress)
        uint256 curSigThreshold;
        /// The set of persistently enabled attesters (renamed from enabledAttesters)
        EnumerableSet.AddressSet persistentEnabledAttesters;
        /// Mapping from attester address to the block number until which they remain valid when being disabled
        mapping(address => uint256) attestersValidUntilBlock;
        /// The number of blocks to delay when disabling attesters and increasing signature thresholds
        uint256 persistentSignatureBufferDelayBlocks;
    }

    /// `keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Attestable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0xf768becf40f8e6bd7b813400353588b273b55b0c5234b97c0139dfec16834f00;

    /// @notice EIP-7201 getter for the storage slot
    /// @return $ The storage struct for the `Attestable` module
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}
