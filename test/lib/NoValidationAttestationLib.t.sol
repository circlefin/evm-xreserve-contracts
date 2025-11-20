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

import {ATTESTATION_SET_MAGIC} from "@gateway/src/lib/Attestations.sol";
import {Cursor} from "@gateway/src/lib/Cursor.sol";
import {TransferSpecLib} from "@gateway/src/lib/TransferSpecLib.sol";
import {Test} from "forge-std/Test.sol";
import {NoValidationAttestationLib} from "src/lib/NoValidationAttestationLib.sol";

contract NoValidationAttestationLibHarness {
    using NoValidationAttestationLib for bytes;
    using NoValidationAttestationLib for Cursor;

    function makeCursor(bytes memory data) external pure returns (Cursor memory) {
        return NoValidationAttestationLib.cursor(data);
    }

    function next(Cursor memory c) external pure returns (bytes29) {
        return NoValidationAttestationLib.next(c);
    }
}

contract NoValidationAttestationLibTest is Test {
    NoValidationAttestationLibHarness private harness;

    function setUp() public {
        harness = new NoValidationAttestationLibHarness();
    }

    function test_next_reverts_whenCursorDone_attestationSetEmpty() public {
        // Encode an empty AttestationSet header: magic + numAttestations (0)
        bytes memory emptySet = abi.encodePacked(ATTESTATION_SET_MAGIC, uint32(0));

        // Build cursor via the lightweight lib; should be immediately done
        Cursor memory c = harness.makeCursor(emptySet);
        assertTrue(c.done, "cursor.done should be true for empty set");

        vm.expectRevert(TransferSpecLib.CursorOutOfBounds.selector);
        harness.next(c);
    }
}
