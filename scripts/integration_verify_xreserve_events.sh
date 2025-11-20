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

set -euo pipefail

# Integration test runner for verifying xReserve deployment events on a local anvil network.
#
# Steps:
# 1) Ensure anvil is running (persistent). If not, start it.
# 2) Ensure a CREATE2 factory compatible with ICreate2Factory is deployed (deploy if missing).
# 3) Compile script artifacts required by BaseBytecodeDeployScript.
# 4) Run 001_DeployXReserve.sol with ENV=LOCAL and required env vars.
# 5) Extract the proxy address and the tx hash that performed upgrade+initialize+ownership transfer from broadcast JSON.
# 6) Invoke deploy-contracts/004_VerifyXReserveDeploymentEvents.ts with those values.

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
RPC_URL_DEFAULT="http://127.0.0.1:8545"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd anvil
require_cmd forge
require_cmd cast
require_cmd jq
require_cmd yarn

# 1) Ensure anvil is running
RPC_URL="${RPC_URL:-${RPC_URL_DEFAULT}}"
if ! curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC_URL" >/dev/null 2>&1; then
  echo "Starting anvil at $RPC_URL ..."
  # If user set ANVIL_ARGS, respect it.
  anvil ${ANVIL_ARGS:-} >/tmp/anvil.log 2>&1 &
  ANVIL_PID=$!
  # Wait for RPC to come up
  for i in {1..50}; do
    if curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC_URL" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
fi

# 2) Ensure local deployer credentials and CREATE2 factory
# If not provided, default to Anvil's first deterministic account (useful in CI)
if [[ -z "${LOCAL_DEPLOYER_KEY:-}" ]]; then
  export LOCAL_DEPLOYER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
fi

if [[ -z "${LOCAL_DEPLOYER_ADDRESS:-}" ]]; then
  # Derive from private key
  LOCAL_DEPLOYER_ADDRESS=$(cast wallet address "$LOCAL_DEPLOYER_KEY")
fi

DERIVED_ADDR=$(cast wallet address "$LOCAL_DEPLOYER_KEY")
LOWER_INPUT=$(echo "$LOCAL_DEPLOYER_ADDRESS" | tr 'A-Z' 'a-z')
LOWER_DERIVED=$(echo "$DERIVED_ADDR" | tr 'A-Z' 'a-z')
if [[ "$LOWER_INPUT" != "$LOWER_DERIVED" ]]; then
  echo "Warning: LOCAL_DEPLOYER_ADDRESS does not match key-derived address. Using derived address $DERIVED_ADDR" >&2
  LOCAL_DEPLOYER_ADDRESS="$DERIVED_ADDR"
fi

X_RESERVE_OWNER_ADDRESS="${X_RESERVE_OWNER_ADDRESS:-$LOCAL_DEPLOYER_ADDRESS}"
X_RESERVE_PAUSER_ADDRESS="${X_RESERVE_PAUSER_ADDRESS:-$X_RESERVE_OWNER_ADDRESS}"
X_RESERVE_BLOCKLISTER_ADDRESS="${X_RESERVE_BLOCKLISTER_ADDRESS:-$X_RESERVE_OWNER_ADDRESS}"
X_RESERVE_REGISTRATION_MANAGER_ADDRESS="${X_RESERVE_REGISTRATION_MANAGER_ADDRESS:-$X_RESERVE_OWNER_ADDRESS}"
X_RESERVE_DOMAIN="${X_RESERVE_DOMAIN:-1}"

# Deploy local CREATE2 factory if missing
if [[ -z "${LOCAL_CREATE2_FACTORY_ADDRESS:-}" ]]; then
  echo "Deploying local Create2Factory..."

  # Try deploying with forge create first (preferred method)
  echo "  Attempting deployment via forge create..."
  DEPLOY_OUT=$(forge create \
    --rpc-url "$RPC_URL" \
    --private-key "$LOCAL_DEPLOYER_KEY" \
    lib/evm-gateway-contracts/script/Create2Factory.sol:Create2Factory \
    --constructor-args "$LOCAL_DEPLOYER_ADDRESS" \
    --broadcast 2>/dev/null || true)

  LOCAL_CREATE2_FACTORY_ADDRESS=$(echo "$DEPLOY_OUT" | { grep -Eo 'Deployed to: .*' || true; } | awk '{print $3}')

  # Fallback to cast send --create if forge create didn't broadcast
  if [[ -z "$LOCAL_CREATE2_FACTORY_ADDRESS" ]]; then
    echo "  forge create did not broadcast, falling back to cast send --create"

    # Verify bytecode exists
    BYTECODE=$(jq -r '.bytecode.object' "$ROOT_DIR/out/Create2Factory.sol/Create2Factory.json")
    if [[ -z "$BYTECODE" || "$BYTECODE" == "null" ]]; then
      echo "Error: Missing Create2Factory bytecode in out/. Run compilation first." >&2
      exit 1
    fi

    # Encode constructor arguments and deploy
    ENCODED_ARGS=$(cast abi-encode "constructor(address)" "$LOCAL_DEPLOYER_ADDRESS")
    RAW_DEPLOY_DATA="${BYTECODE}${ENCODED_ARGS#0x}"

    # Send deployment transaction
    TX_HASH=$(cast send \
      --rpc-url "$RPC_URL" \
      --private-key "$LOCAL_DEPLOYER_KEY" \
      --create "$RAW_DEPLOY_DATA" \
      --json | jq -r '.transactionHash')

    if [[ -z "$TX_HASH" || "$TX_HASH" == "null" ]]; then
      echo "Error: Failed to send factory deploy transaction." >&2
      exit 1
    fi

    # Get contract address from transaction receipt
    RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json)
    LOCAL_CREATE2_FACTORY_ADDRESS=$(echo "$RECEIPT" | jq -r '.contractAddress')

    if [[ -z "$LOCAL_CREATE2_FACTORY_ADDRESS" || "$LOCAL_CREATE2_FACTORY_ADDRESS" == "null" ]]; then
      echo "Error: Failed to get factory address from receipt." >&2
      echo "Receipt: $RECEIPT" >&2
      exit 1
    fi
  fi

  echo "  Successfully deployed Create2Factory at: $LOCAL_CREATE2_FACTORY_ADDRESS"
fi

# 3) Compile script artifacts (needed by BaseBytecodeDeployScript)
if [[ -x "$ROOT_DIR/scripts/compile_artifacts.sh" ]]; then
  "$ROOT_DIR/scripts/compile_artifacts.sh"
else
  echo "Warning: scripts/compile_artifacts.sh not found or not executable. Proceeding."
fi

# 3.5) Deploy a mock ERC20 token for testing TokenSupported event
echo "Deploying mock ERC20 token..."

# Get the bytecode for ERC20Mock
ERC20_MOCK_BYTECODE=$(jq -r '.bytecode.object' "$ROOT_DIR/out/ERC20Mock.sol/ERC20Mock.json")

if [[ -z "$ERC20_MOCK_BYTECODE" || "$ERC20_MOCK_BYTECODE" == "null" ]]; then
  echo "Error: Missing ERC20Mock bytecode. Run forge build first." >&2
  exit 1
fi

# Deploy using cast send --create
TX_HASH=$(cast send \
  --rpc-url "$RPC_URL" \
  --private-key "$LOCAL_DEPLOYER_KEY" \
  --create "$ERC20_MOCK_BYTECODE" \
  --json | jq -r '.transactionHash')

if [[ -z "$TX_HASH" || "$TX_HASH" == "null" ]]; then
  echo "Error: Failed to send ERC20Mock deploy transaction." >&2
  exit 1
fi

# Get contract address from transaction receipt
RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json)
MOCK_TOKEN_ADDRESS=$(echo "$RECEIPT" | jq -r '.contractAddress')

if [[ -z "$MOCK_TOKEN_ADDRESS" || "$MOCK_TOKEN_ADDRESS" == "null" ]]; then
  echo "Error: Failed to get ERC20Mock address from receipt." >&2
  exit 1
fi
echo "  Mock ERC20 token deployed at: $MOCK_TOKEN_ADDRESS"

# Set the token as a supported token for deployment
export X_RESERVE_SUPPORTED_TOKEN_1="$MOCK_TOKEN_ADDRESS"

# 4) Run deployment script with ENV=LOCAL
echo "Running 001_DeployXReserve.sol ..."

# Provide sane defaults for required constructor immutables if not set
X_RESERVE_GATEWAY_MINTER_ADDRESS="${X_RESERVE_GATEWAY_MINTER_ADDRESS:-$LOCAL_DEPLOYER_ADDRESS}"
X_RESERVE_GATEWAY_WALLET_ADDRESS="${X_RESERVE_GATEWAY_WALLET_ADDRESS:-$LOCAL_DEPLOYER_ADDRESS}"
X_RESERVE_TOKEN_MESSENGER_ADDRESS="${X_RESERVE_TOKEN_MESSENGER_ADDRESS:-$LOCAL_DEPLOYER_ADDRESS}"
X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS="${X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS:-$LOCAL_DEPLOYER_ADDRESS}"
ENV=LOCAL \
RPC_URL="$RPC_URL" \
LOCAL_CREATE2_FACTORY_ADDRESS="$LOCAL_CREATE2_FACTORY_ADDRESS" \
LOCAL_DEPLOYER_ADDRESS="$LOCAL_DEPLOYER_ADDRESS" \
X_RESERVE_OWNER_ADDRESS="$X_RESERVE_OWNER_ADDRESS" \
X_RESERVE_PAUSER_ADDRESS="$X_RESERVE_PAUSER_ADDRESS" \
X_RESERVE_BLOCKLISTER_ADDRESS="$X_RESERVE_BLOCKLISTER_ADDRESS" \
X_RESERVE_REGISTRATION_MANAGER_ADDRESS="$X_RESERVE_REGISTRATION_MANAGER_ADDRESS" \
X_RESERVE_DOMAIN="$X_RESERVE_DOMAIN" \
X_RESERVE_GATEWAY_MINTER_ADDRESS="$X_RESERVE_GATEWAY_MINTER_ADDRESS" \
X_RESERVE_GATEWAY_WALLET_ADDRESS="$X_RESERVE_GATEWAY_WALLET_ADDRESS" \
X_RESERVE_TOKEN_MESSENGER_ADDRESS="$X_RESERVE_TOKEN_MESSENGER_ADDRESS" \
X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS="$X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS" \
X_RESERVE_SUPPORTED_TOKEN_1="$X_RESERVE_SUPPORTED_TOKEN_1" \
forge script deploy-contracts/001_DeployXReserve.sol:DeployXReserve \
  --rpc-url "$RPC_URL" \
  --private-key "$LOCAL_DEPLOYER_KEY" \
  --broadcast \
  -vvv | tee /tmp/deploy_xreserve.out

# 5) Extract tx hash and proxy address from broadcast JSON
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
BROADCAST_DIR="$ROOT_DIR/broadcast/001_DeployXReserve.sol/$CHAIN_ID"
RUN_JSON=$(ls -t "$BROADCAST_DIR"/run-*.json 2>/dev/null | head -n1 || true)
if [[ -z "$RUN_JSON" ]]; then
  echo "Could not find broadcast run JSON under $BROADCAST_DIR" >&2
  exit 1
fi

UPGRADED_TOPIC=$(cast keccak "Upgraded(address)")
OTS_TOPIC=$(cast keccak "OwnershipTransferStarted(address,address)")

# Find the receipt that includes both Upgraded and OwnershipTransferStarted (proxy deployAndMultiCall tx)
DEPLOY_TX_HASH=$(jq -r \
  --arg U "$UPGRADED_TOPIC" --arg O "$OTS_TOPIC" '
  .receipts[] | select((.logs | any(.topics[0] == $U)) and (.logs | any(.topics[0] == $O))) | .transactionHash' "$RUN_JSON" | head -n1)

if [[ -z "$DEPLOY_TX_HASH" || "$DEPLOY_TX_HASH" == "null" ]]; then
  echo "Failed to locate the deploy-and-upgrade tx hash in $RUN_JSON" >&2
  exit 1
fi

# Get the proxy address from the Upgraded log in that receipt
PROXY_ADDRESS=$(jq -r \
  --arg U "$UPGRADED_TOPIC" --arg TX "$DEPLOY_TX_HASH" '
  .receipts[] | select(.transactionHash == $TX) | .logs[] | select(.topics[0] == $U) | .address' "$RUN_JSON" | head -n1)

if [[ -z "$PROXY_ADDRESS" || "$PROXY_ADDRESS" == "null" ]]; then
  echo "Failed to extract proxy address from Upgraded event in $RUN_JSON" >&2
  exit 1
fi

echo "Proxy Address: $PROXY_ADDRESS"
echo "Deployment Tx: $DEPLOY_TX_HASH"

# 6) Complete ownership transfer (two-step) and run the TS verifier

# Perform acceptOwnership as the pending owner (defaults to LOCAL_DEPLOYER)
echo "Accepting ownership on proxy ..."
ACCEPT_TX_HASH=$(cast send \
  --rpc-url "$RPC_URL" \
  --private-key "$LOCAL_DEPLOYER_KEY" \
  "$PROXY_ADDRESS" \
  "acceptOwnership()" \
  --json | jq -r '.transactionHash')

if [[ -z "$ACCEPT_TX_HASH" || "$ACCEPT_TX_HASH" == "null" ]]; then
  echo "Error: Failed to send acceptOwnership transaction." >&2
  exit 1
fi
echo "  Ownership accepted in tx: $ACCEPT_TX_HASH"

export RPC_URL
export LOCAL_CREATE2_FACTORY_ADDRESS="$LOCAL_CREATE2_FACTORY_ADDRESS"
export X_RESERVE_OWNER_ADDRESS
export X_RESERVE_PAUSER_ADDRESS
export X_RESERVE_BLOCKLISTER_ADDRESS
export X_RESERVE_SUPPORTED_TOKEN_1
export X_RESERVE_OWNERSHIP_TRANSFER_COMPLETED="true"

echo "Running 004_VerifyXReserveDeploymentEvents.ts ..."
yarn verify:xreserve:events -- --proxyAddress "$PROXY_ADDRESS" --deploymentTxHash "$DEPLOY_TX_HASH" --ownershipTransferCompleted true --ownershipAcceptTxHash "$ACCEPT_TX_HASH"

echo "Done."
exit 0
