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

#!/usr/bin/env bash

chains=(
  local
  ethereum
  ethereum_sepolia
  arbitrum
  optimism
  arbitrum_sepolia
  optimism_sepolia
)

for chain in ${chains[@]}; do
  forge_test_args=($@)

  if [[ ${chain} != "local" ]]; then
    rpc=$(forge config --json | jq -r ".rpc_endpoints.${chain}")

    if [[ ${rpc} == "null" ]]; then
      echo "RPC not configured for ${chain}"
      exit 1
    fi

    forge_test_args+=(--fork-url ${rpc})

    if [[ ${CI} != "true" ]]; then
      block=$(jq ".${chain}" block-numbers.json)
      forge_test_args+=(--fork-block-number ${block})
    fi

    # Skip script & integration tests if not running on local network
    forge_test_args+=(--no-match-path "test/{deploy-contracts,integration}/*.t.sol")
  else
    # Skip only the DeployAndValidateIntegration tests on local as they have compiler setting conflicts
    forge_test_args+=(--no-match-path "test/integration/DeployAndValidateIntegration.t.sol")
  fi

  echo "🚀 Running tests on chain: ${chain}"
  echo

  forge test ${forge_test_args[@]}
  result=$?

  if [[ ${result} != 0 ]]; then
    echo
    echo "❌ Tests failed on chain: ${chain}"
    exit ${result}
  else
    echo "✅ Tests passed on chain: ${chain}"
  fi

  echo
done
