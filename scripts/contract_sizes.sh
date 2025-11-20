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

echo "Checking contract sizes..."

EIP_170_SIZE_LIMIT=24576  # 24 KB

exceeded=false

for contract in xReserve RemoteDomainDepositor UpgradeablePlaceholder; do
  deployed_size=$(jq -r '.deployedBytecode.object | (length - 2) / 2' out/$contract.sol/$contract.json)

  if [[ "$deployed_size" -gt "$EIP_170_SIZE_LIMIT" ]]; then
    echo -e "\e[31m❌ $contract (deployed bytecode size: $deployed_size) exceeds the EIP-170 size limit ($EIP_170_SIZE_LIMIT)\e[0m"
    exceeded=true
  else
    echo -e "\e[32m✅ $contract (deployed bytecode size: $deployed_size) is within the EIP-170 size limit ($EIP_170_SIZE_LIMIT)\e[0m"
  fi
done

if [ "$exceeded" = true ]; then
  exit 1
fi
