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

# update_submodules.sh
# Script to update all submodules and automatically fix CCTP compatibility issues
# Handles CCTP, Gateway, and other submodule compatibility fixes for Foundry 1.0.0

set -e

echo "🚀 Updating submodules and fixing compatibility issues..."
echo ""

# Update all submodules
echo "📦 Updating all submodules..."
git submodule update --init --recursive

echo "✅ Submodules updated successfully"
echo ""

# Fix all submodule compatibility issues
echo "🔧 Fixing submodule compatibility issues..."
if [ -f "scripts/fix_submodule_compatibility.sh" ]; then
    bash scripts/fix_submodule_compatibility.sh
else
    echo "❌ Error: scripts/fix_submodule_compatibility.sh not found"
    echo "   Please ensure the submodule compatibility fix script exists"
    exit 1
fi

echo ""
echo "🎉 All done! Submodules updated and compatibility issues fixed."
