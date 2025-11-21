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

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {DepositIntent, DepositIntentLib} from "./../lib/DepositIntentLib.sol";

// solhint-disable gas-custom-errors

/// @title USDCx
/// @notice Example contract for minting and burning USDC-backed tokens.
///
/// @dev This contract demonstrates a reference implementation of the USDC-backed token issued by xReserve partners.
///      It is intended for illustrative purposes and is not audited or production-ready.
///      The design is portable and can be adapted to non-EVM chains using other smart contract languages.
///      Token amounts are represented as uint256 in this implementation; other platforms may use different types.
/// @dev Transfer functionality is deliberately excluded from this implementation, as transfer logic depends on
///      the specifics of each remote chain and is outside the scope of this specification.
/// @dev USDCx is a shorthand for "USDC-backed tokens issued by xReserve partners".
///      Each xReserve partner may freely choose their own token name.
contract USDCx {
    uint32 public constant SUPPORTED_VERSION = 1;

    /// =========== State Variables ===========
    address public owner; // The owner of the contract.
    uint32 public domain; // The domain identifier for the USDC-backed token.
    mapping(address => bool) public attesters; // The account that attests to deposit events on the source chain.
    mapping(bytes32 => uint256) public balances; // The balance of each account.
    mapping(bytes32 => bool) public usedNonces; // The flag to check if a deposit intent has been minted.
    uint256 public totalSupply; // The total supply of USDC-backed tokens.
    uint256 public minBurnSize; // The minimum amount of tokens that can be burned.

    /// =========== Events ===========
    event Burn(
        bytes32 depositor, uint32 remoteDomain, uint256 amount, uint32 destinationDomain, bytes32 destinationRecipient
    );

    /// =========== Constructor ===========
    /// @notice The constructor of the USDC-backed token contract.
    /// @param owner_ The owner of the contract.
    /// @param domain_ The domain of the USDC-backed token.
    /// @param initialAttester The attester authorized to sign xReserve attestations.
    constructor(address owner_, uint32 domain_, address initialAttester) {
        owner = owner_;
        domain = domain_;
        attesters[initialAttester] = true;
    }

    /// @notice Mint tokens to an account.
    /// @param depositIntentPayload The attestation payload.
    /// @param depositAttestation The signature of the attestation payload.
    /// @param feeAmount The fee to pay to the relayer.
    function mint(bytes calldata depositIntentPayload, bytes calldata depositAttestation, uint256 feeAmount) external {
        // Verify the signature of the attestation payload.
        _verifySignature(keccak256(depositIntentPayload), depositAttestation);

        // Decode the deposit intent.
        DepositIntent memory depositIntent = DepositIntentLib.decodeDepositIntent(depositIntentPayload);

        // Validate the deposit intent.
        require(depositIntent.version == SUPPORTED_VERSION, "Invalid version");
        require(depositIntent.amount > 0, "Zero value");
        require(depositIntent.remoteDomain == domain, "Invalid remote domain");
        require(depositIntent.remoteToken == _convertRemoteAddressToBytes32(address(this)), "Invalid remote token");
        require(depositIntent.amount >= depositIntent.maxFee, "Max fee cannot exceed amount");
        require(feeAmount <= depositIntent.maxFee, "Cannot charge more than max fee");
        require(!usedNonces[depositIntent.nonce], "Nonce already used");

        // NOTE: additional required input for the mint can be extracted from `depositIntent.hookData`

        /// @dev The relayer is the account that is sponsoring the mint.
        /// @dev The relayer can charge a fee up to the max fee specified in the deposit intent.
        bytes32 relayer = _convertRemoteAddressToBytes32(msg.sender);

        // Mark the nonce as used -- this prevents replay attacks.
        usedNonces[depositIntent.nonce] = true;
        // Mint the amount of tokens, minus the relayer fee, to the recipient.
        balances[depositIntent.remoteRecipient] += depositIntent.amount - feeAmount;
        // Mint the relayer fee to the relayer.
        balances[relayer] += feeAmount;
        // Update the total supply.
        totalSupply += depositIntent.amount;
    }

    /// @notice Burn tokens from an account.
    ///
    /// @dev A user holding USDC-backed tokens can burn them to receive the destination token on the destination domain.
    /// @dev The user must specify the amount of tokens to burn, the intended domain of the destination token redemption, and the recipient of the released token.
    /// @dev The total amount user burns should include any fees required to redeem tokens on the destination domain.
    /// @dev The user must have sufficient balance to burn the tokens.
    /// @dev IMPORTANT: xReserve partner chains SHOULD implement the burn function interface with the exact function interface shown below.
    ///      Strict adherence to this interface is highly encouraged for maximizing compatibility with the xReserve protocol and seamless ecosystem integration.
    ///
    /// @param amount The amount of tokens to burn.
    /// @param destinationDomain The domain of the destination token where the burnt token should be redeemed.
    /// @param destinationRecipient The recipient of the destination collateral on the destination domain.
    function burn(uint256 amount, uint32 destinationDomain, bytes32 destinationRecipient) external {
        bytes32 depositor = _convertRemoteAddressToBytes32(msg.sender);

        // Validate user-provided values.
        require(amount > 0, "Zero value");

        // A minimum burn size must be set, since burning tokens to withdraw on the destination domain incurs a required fee.
        // Burns below this minimum cannot be redeemed for withdrawal.
        require(amount >= minBurnSize, "Amount below minimum burn size");
        require(balances[depositor] >= amount, "Insufficient balance");

        // Update the balances and total supply.
        balances[depositor] -= amount;
        totalSupply -= amount;

        // Emit the burn event, which will be observed by chains that support USDC-backed tokens and submit the corresponding burn request to xReserve APIs.
        emit Burn(depositor, domain, amount, destinationDomain, destinationRecipient);
    }

    /// @notice Update the attester that is authorized to sign xReserve attestations.
    /// @param attester The attester address to update.
    /// @param attesterEnabled Whether the attester is authorized to attest to deposit events on the source chain.
    function setAttester(address attester, bool attesterEnabled) external {
        require(msg.sender == owner, "Not owner");
        attesters[attester] = attesterEnabled;
    }

    /// @notice Update the minimum burn size.
    /// @param minBurnSize_ The new minimum burn size.
    function setMinBurnSize(uint256 minBurnSize_) external {
        require(msg.sender == owner, "Not owner");
        minBurnSize = minBurnSize_;
    }

    /// @notice Verify the signature of the attestation payload.
    /// @param hash The hash of the attestation payload.
    /// @param signature The signature of the attestation payload.
    function _verifySignature(bytes32 hash, bytes memory signature) internal view {
        address recoveredSigner = ECDSA.recover(hash, signature);
        require(attesters[recoveredSigner], "Invalid attester");
    }

    /// @notice Convert a remote address to a bytes32.
    /// @dev Helper function to convert a remote address to a bytes32.
    ///      Since this contract is written in Solidity, we demonstrate a simple
    ///      conversion between the `address` type and the `bytes32` type.
    ///      For non-Solidity implementations, this conversion would be between
    ///      the address format specific to the xReserve partner chain and the `bytes32` type.
    ///      We do not dictate how this conversion is done as long as it is consistent and deterministic.
    ///      For address identifiers that exceed 32 bytes, we recommend using a keccak256 hash of the
    ///      address and attach the full address identifier in deposit intent hook data.
    /// @param remoteAddress The remote address to convert.
    /// @return The bytes32 representation of the remote address.
    function _convertRemoteAddressToBytes32(address remoteAddress) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(remoteAddress)));
    }
}
