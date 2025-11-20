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

# Ensure that required environment variables are set
if [ -z "$SALT_MINE_CREATE2_FACTORY_ADDRESS" ]; then
  echo "Error: SALT_MINE_CREATE2_FACTORY_ADDRESS environment variable is not set."
  exit 1
fi
if [ -z "$XRESERVE_PROXY_INIT_CODE_HASH" ]; then
  echo "Error: XRESERVE_PROXY_INIT_CODE_HASH environment variable is not set."
  exit 1
fi

# Select prefix based on environment
XRESERVE_PREFIX=""

if [[ $ENV == "MAINNET_PROD" ]]
then
  XRESERVE_PREFIX="8888888"
elif [[ $ENV == "TESTNET_PROD" ]]
then
  XRESERVE_PREFIX="0088888"
elif [[ $ENV == "TESTNET_STAGING" ]]
then
  # 5 = "S" for Staging
  XRESERVE_PREFIX="5588888"
else
  echo "Error: Unexpected environment '$ENV'. Expected MAINNET_PROD, TESTNET_PROD, or TESTNET_STAGING."
  exit 1
fi

echo "****** Mining salt for xReserve proxy... ******"
echo "Using environment: $ENV\n"

cast create2 --starts-with "$XRESERVE_PREFIX" --deployer $SALT_MINE_CREATE2_FACTORY_ADDRESS --init-code-hash $XRESERVE_PROXY_INIT_CODE_HASH


