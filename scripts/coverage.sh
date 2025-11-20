#!/usr/bin/env bash
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

set -e

echo "Generating coverage report..."

# Generate raw lcov info (exclude validation tests that depend on specific compiler settings)
# Also exclude deterministic deployment address test that hits stack depth under coverage
# Note: --no-match-path excludes from running; --skip excludes from compilation
forge coverage --report lcov \
  --no-match-path "test/integration/DeployAndValidateIntegration.t.sol|test/deploy-contracts/DeployXReserveTest.t.sol" \
  --skip "test/deploy-contracts/DeployXReserveTest.t.sol"

# Remove test and deployment script coverage (only enforce coverage on core contracts in /src)
lcov --remove lcov.info 'test/**' 'deploy-contracts/**' -o lcov.info.pruned

# Display summary
echo ""
echo "=== LCOV Summary (all contracts) ==="
lcov --summary lcov.info.pruned
echo ""

# Enforce 100% line coverage
coverage_percent=$(lcov --summary lcov.info.pruned | grep -o 'lines......: [0-9.]*%' | cut -d' ' -f2 | tr -d '%')

if (( $(echo "$coverage_percent < 100" | bc -l) )); then
  echo -e "\e[31m❌ Contracts under /src do not have 100% test coverage (${coverage_percent}%)\e[0m"
  exit 1
fi

# Generate HTML report
genhtml lcov.info.pruned --output-directory coverage

# Clean up intermediate files
rm -f lcov.info lcov.info.pruned src-only.info
