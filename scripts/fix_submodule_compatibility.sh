#!/bin/bash
# Copyright 2025 Circle Internet Group, Inc. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# fix_submodule_compatibility.sh
# Comprehensive script to fix all submodule compatibility issues for Foundry 1.0.0
# Handles CCTP and Gateway contract import path remapping and compatibility fixes

set -e

echo -e "🚀 Fixing all submodule compatibility issues for Foundry 1.0.0...\n"

TOTAL_FIXED=0

# =============================================================================
# Helper Functions
# =============================================================================

# Function to fix a specific pattern in files (idempotent)
fix_pattern() {
    local dir="$1"
    local pattern="$2"
    local replacement="$3"
    local description="$4"

    echo "🔧 $description..."

    local files_fixed=0
    local files_already_fixed=0

    # Simple, portable approach that works in all environments
    if [ -d "$dir" ]; then
        for file in $(find "$dir" -name "*.sol" -type f 2>/dev/null); do
            if [ -f "$file" ]; then
                # Check if replacement already exists (idempotent check)
                if grep -q "$replacement" "$file" 2>/dev/null; then
                    files_already_fixed=$((files_already_fixed + 1))
                # Check if original pattern exists and needs replacement
                elif grep -q "$pattern" "$file" 2>/dev/null; then
                    # Use portable sed syntax - create backup then remove it
                    sed -i.bak "s|$pattern|$replacement|g" "$file"
                    rm -f "$file.bak"
                    files_fixed=$((files_fixed + 1))
                fi
            fi
        done
    fi

    if [ "$files_fixed" -gt 0 ]; then
        echo -e "  ✅ Updated $files_fixed files\n"
        TOTAL_FIXED=$((TOTAL_FIXED + files_fixed))
    elif [ "$files_already_fixed" -gt 0 ]; then
        echo -e "  ✅ Already fixed ($files_already_fixed files already have correct imports)\n"
    else
        echo -e "  ✅ No files need fixing\n"
    fi
}

# Function to check if a submodule directory exists
check_submodule() {
    local submodule_path="$1"
    local submodule_name="$2"

    if [ ! -d "$submodule_path" ]; then
        echo "⚠️  Warning: $submodule_name directory not found at $submodule_path"
        echo "   Skipping $submodule_name compatibility fixes"
        return 1
    fi
    return 0
}

# =============================================================================
# CCTP Submodule Compatibility Fixes
# =============================================================================

fix_cctp_compatibility() {
    echo -e "🔄 CCTP Submodule Compatibility Fixes\n"

    if ! check_submodule "lib/evm-cctp-contracts" "CCTP"; then
        return
    fi

    # 1. Fix CCTP Source Contract Pragma Statements
    echo -e "📝 Step 1: Fixing CCTP source contract pragma statements"
    fix_pattern "lib/evm-cctp-contracts/src" "pragma solidity 0\.7\.6;" "pragma solidity ^0.8.0;" "Fixing pragma 0.7.6"

    # 2. Fix OpenZeppelin Pragma Statements in CCTP Dependencies
    if [ -d "lib/evm-cctp-contracts/lib/openzeppelin-contracts" ]; then
        echo "📝 Step 2: Fixing OpenZeppelin pragma statements in CCTP dependencies"
        fix_pattern "lib/evm-cctp-contracts/lib/openzeppelin-contracts" "pragma solidity >=0\.6\.0 <0\.8\.0;" "pragma solidity ^0.8.0;" "Fixing pragma >=0.6.0 <0.8.0"
        fix_pattern "lib/evm-cctp-contracts/lib/openzeppelin-contracts" "pragma solidity >=0\.6\.2 <0\.8\.0;" "pragma solidity ^0.8.0;" "Fixing pragma >=0.6.2 <0.8.0"
    else
        echo "📝 Step 2: Fixing OpenZeppelin pragma statements in CCTP dependencies"
        echo -e "  ⚠️  OpenZeppelin contracts not found in CCTP - skipping\n"
    fi

    # 3. Fix OpenZeppelin Import Paths in CCTP Source
    echo "📝 Step 3: Fixing OpenZeppelin import paths in CCTP source contracts"
    fix_pattern "lib/evm-cctp-contracts/src" "@openzeppelin/contracts/" "@openzeppelin-cctp/contracts/" "Fixing OpenZeppelin import paths"

    # 4. Fix Memview Import Paths
    echo "📝 Step 4: Fixing memview import paths in CCTP contracts"
    fix_pattern "lib/evm-cctp-contracts/src" "@memview-sol/contracts/TypedMemView\.sol" "@memview-sol/TypedMemView.sol" "Fixing memview import paths"

    # 5. Fix Solidity 0.7.x -> 0.8.x Compatibility Issues
    echo "📝 Step 5: Fixing Solidity 0.8.x compatibility issues"
    fix_pattern "lib/evm-cctp-contracts" "return msg\.sender;" "return payable(msg.sender);" "Fixing msg.sender compatibility"

    # 6. Update CCTP Remappings
    echo "📝 Step 6: Updating CCTP remappings"
    echo "  ⚠️  Updating CCTP remappings for OpenZeppelin and Memview"
    cat > "lib/evm-cctp-contracts/remappings.txt" << EOF
@memview-sol/=lib/memview-sol
@openzeppelin-cctp/=lib/openzeppelin-contracts/
ds-test/=lib/ds-test/src/
EOF
    echo -e "  ✅ Updated remappings.txt with correct paths\n"
}

# =============================================================================
# Gateway Submodule Compatibility Fixes
# =============================================================================

fix_gateway_compatibility() {
    echo -e "🔄 Gateway Submodule Compatibility Fixes\n"

    if ! check_submodule "lib/evm-gateway-contracts" "Gateway"; then
        return
    fi

    # 1. Fix Gateway Library Import Paths
    echo -e "📝 Step 1: Fixing Gateway library import paths"

    # Core library imports
    fix_pattern "lib/evm-gateway-contracts" "src/lib/TransferSpec\.sol" "@gateway/src/lib/TransferSpec.sol" "Fixing TransferSpec import path"
    fix_pattern "lib/evm-gateway-contracts" "src/lib/BurnIntentLib\.sol" "@gateway/src/lib/BurnIntentLib.sol" "Fixing BurnIntentLib import path"
    fix_pattern "lib/evm-gateway-contracts" "src/lib/BurnIntents\.sol" "@gateway/src/lib/BurnIntents.sol" "Fixing BurnIntents import path"
    fix_pattern "lib/evm-gateway-contracts" "src/lib/Attestations\.sol" "@gateway/src/lib/Attestations.sol" "Fixing Attestations import path"
    fix_pattern "lib/evm-gateway-contracts" "src/lib/AttestationLib\.sol" "@gateway/src/lib/AttestationLib.sol" "Fixing AttestationLib import path"
    fix_pattern "lib/evm-gateway-contracts" "src/lib/AddressLib\.sol" "@gateway/src/lib/AddressLib.sol" "Fixing AddressLib import path"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "🔍 Scanning for submodules that need compatibility fixes..."
    echo ""

    # Fix CCTP compatibility issues
    fix_cctp_compatibility

    # Fix Gateway compatibility issues
    fix_gateway_compatibility

    # Summary
    echo "📊 Summary:"
    echo -e "  • Total files fixed: $TOTAL_FIXED\n"

    if [ "$TOTAL_FIXED" -gt 0 ]; then
        echo -e "✅ All submodule compatibility issues fixed! \n"
        echo "🔄 You can now run:"
        echo "  forge build"
        echo ""
        echo "💡 If you still encounter issues, try:"
        echo "  forge clean && forge build"
    else
        echo "✅ No compatibility issues found - all submodules are ready to use!"
    fi
}

# Run the main function
main "$@"
