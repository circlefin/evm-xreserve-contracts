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

set -e

filename="block-numbers.json"
chains=$(forge config --json | jq -r '.rpc_endpoints | keys[]')
new_block_numbers=""

function append() {
  new_block_numbers+="$1"
}

append "{"

first_time=true

for chain in ${chains[@]}; do
  rpc=$(forge config --json | jq -r ".rpc_endpoints.${chain}")
  block=$(cast block-number --rpc-url ${rpc})

  echo Latest block on ${chain} is ${block}

  if $first_time; then
    first_time=false
  else
    append ","
  fi

  append "\"${chain}\": ${block}"
done

append "}"

echo
echo "Updating block-numbers.json:"
echo

echo "${new_block_numbers}" | jq | tee block-numbers.json
