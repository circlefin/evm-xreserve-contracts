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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";
import {Domain, DomainStorage} from "src/modules/x-reserve/Domain.sol";

contract DomainHarness is Domain {
    function initialize(uint32 domain) public initializer {
        __Domain_init(domain);
    }

    // Exposes storage for testing
    function getStorageSlot() public pure returns (bytes32) {
        return DomainStorage.SLOT;
    }

    // Exposes storage data for testing
    function getStorageData() public view returns (uint32) {
        return DomainStorage.get().domain;
    }
}

contract DomainTest is Test {
    uint32 private testDomain = 99;

    DomainHarness private domainHarness;

    function setUp() public {
        domainHarness = new DomainHarness();
    }

    function test_initialize_setsNonZeroDomain() public {
        assertEq(domainHarness.domain(), 0, "Domain should be 0 before initialization.");
        domainHarness.initialize(testDomain);
        assertEq(domainHarness.domain(), testDomain, "Domain should be set to the initialized domain.");
    }

    function test_initialize_setsZeroDomain() public {
        assertEq(domainHarness.domain(), 0, "Domain should be 0 before initialization.");
        domainHarness.initialize(0);
        assertEq(domainHarness.domain(), 0, "Domain should still be 0 after initialization.");
    }

    // Test multiple initialization attempts should fail
    function test_initialize_revertsOnSecondCall() public {
        domainHarness.initialize(testDomain);
        assertEq(domainHarness.domain(), testDomain, "First initialization should succeed.");

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        domainHarness.initialize(testDomain + 1);
    }

    // Test maximum uint32 domain value
    function test_initialize_setsMaxDomain() public {
        uint32 maxDomain = type(uint32).max;
        domainHarness.initialize(maxDomain);
        assertEq(domainHarness.domain(), maxDomain, "Domain should be set to max uint32.");
    }

    // Test storage slot calculation
    function test_getStorageSlot_returnsCorrectSlot() public view {
        bytes32 actualSlot = domainHarness.getStorageSlot();
        assertEq(
            actualSlot,
            keccak256(abi.encode(uint256(keccak256(bytes("circle.xReserve.Domain"))) - 1)) & ~bytes32(uint256(0xff)),
            "Storage slot should match expected EIP-7201 slot."
        );
    }

    // Test storage consistency
    function test_domain_returnsConsistentValue() public {
        uint32 testDomainValue = 123;
        domainHarness.initialize(testDomainValue);

        // Verify both ways of accessing storage return the same value
        assertEq(domainHarness.domain(), testDomainValue, "Public domain() should return correct value.");
        assertEq(domainHarness.getStorageData(), testDomainValue, "Storage data should match domain().");
    }

    // Fuzz test for various domain values
    function testFuzz_initialize_setsAnyDomain(uint32 fuzzDomain) public {
        domainHarness.initialize(fuzzDomain);
        assertEq(domainHarness.domain(), fuzzDomain, "Domain should be set to fuzzed value.");
    }

    // Test edge case: boundary values
    function test_initialize_handlesBoundaryValues() public {
        uint32[4] memory testValues = [0, 1, type(uint32).max - 1, type(uint32).max];

        for (uint256 i = 0; i < testValues.length; i++) {
            // Deploy new instance for each test
            DomainHarness newHarness = new DomainHarness();
            uint32 testValue = testValues[i];

            newHarness.initialize(testValue);
            assertEq(newHarness.domain(), testValue, "Boundary value should be set correctly.");
        }
    }

    // Test uninitialized state behavior
    function test_domain_returnsZeroWhenUninitialized() public {
        // Fresh contract should have domain 0
        DomainHarness freshHarness = new DomainHarness();
        assertEq(freshHarness.domain(), 0, "Uninitialized domain should be 0.");
    }
}
