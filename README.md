# Circle xReserve Contracts

## Overview

**xReserve** is an interoperability infrastructure that lets blockchain teams deploy USDC-backed tokens on their own chains. It is powered by programmatic attestations and Circle-deployed smart contracts that hold USDC in reserve on source chains such as Ethereum. USDC-backed tokens deployed through xReserve are interoperable with each other and with the broader USDC network.

### Key Features

- **Cross-Domain Deposits**: Users deposit assets into the xReserve contract to initiate cross-domain transfers
- **Attestation-Based Minting**: xReserve's off-chain systems observe deposits and generate cryptographic attestations that authorize token minting on remote domains
- **Secure Withdrawals**: Users can burn reserved tokens on remote domains and withdraw the underlying assets from the reserve using multi-party attestations
- **Multi-Protocol Integration**: Seamlessly integrates with Circle's existing infrastructure including Gateway Minter, Gateway Wallet, and CCTP Token Messenger
- **Upgradeable Architecture**: Built using UUPS upgradeable proxy pattern for future extensibility

This repository contains the complete smart contract codebase for xReserve, including deployment scripts, comprehensive test suites, and development tooling.

## 🚀 Getting Started

### 1. Clone the repo and initialize submodules

```bash
git clone <your-repo-url>
cd evm-xreserve-contracts
```

### 2. Install dependencies

```bash
yarn install && yarn postinstall
```

> Ensure you're using Yarn **v4.7.0** or higher (`yarn --version`)

### 3. Install Foundry (if not already)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup --install 1.0.0
```

## 🛠 Build & Test

```bash
yarn build     # Compiles all contracts
yarn test      # Runs Foundry tests locally
yarn test:all  # Runs Foundry tests locally and on forked networks
yarn test:gas  # Includes gas reporting
```

## 🧹 Lint & Format

```bash
yarn lint         # Lint Solidity sources with Solhint
yarn lint:fix     # Auto-fix fixable lint issues
yarn format       # Check formatting using forge fmt
yarn format:fix   # Format all contracts
```

## 🗂 Repository Structure

### src/
Primary source code directory containing all smart contract implementations, interfaces, and libraries.

### test/
Contains all unit and integration tests, written using Foundry's testing framework.

### deploy-contracts/
Deployment and utility scripts for deploying and verifying contracts.

## Mining CREATE2 Salts for xReserve Proxy

To produce vanity prefixes for the xReserve proxy address, you can simulate deployments to obtain the proxy initCodeHash, then mine a `reserveProxySalt` that yields the desired prefix.

### Prefixes

| Environment | Network Type | xReserve Proxy Prefix | Notes |
|:------------------------:|:------------------------:|:------------------------:|:------------------------:|
| Production | Mainnet | 0x8888888 |  |
| Production | Testnet | 0x0088888 | Add zero byte to mainnet addresses |
| Staging | Testnet | 0x5588888 | 5 = "S" for Staging |

### Step 1: Simulate to obtain initCodeHash

Set `ENV` and `RPC_URL` (and `LOCAL_CREATE2_FACTORY_ADDRESS` if using LOCAL). Use any values for other environment variables; they do not affect the init code hash.

Run the deployment script in simulation mode (no broadcast) and capture the init code hash printed when the proxy bytecode is prepared:

```bash
ENV=$ENV forge script script/001_DeployXReserve.sol --rpc-url $RPC_URL -vv
```

Look for a log like "initCodeHash for proxy address ... below:" followed by a `bytes32` value. Copy that value and export it:

```bash
export XRESERVE_PROXY_INIT_CODE_HASH=<bytes32 from logs>
```

Also export the factory used for mining (use the value from `000_Constants.sol` for your environment, or `LOCAL_CREATE2_FACTORY_ADDRESS` when LOCAL):

```bash
export SALT_MINE_CREATE2_FACTORY_ADDRESS=<factory address>
```

Ensure `ENV` is set as well (see `.env`):

```bash
export ENV=<MAINNET_PROD|TESTNET_PROD|TESTNET_STAGING|LOCAL>
```

### Step 2: Mine the salt

Run the script to mine a salt that yields the environment-specific prefix:

```bash
yarn mine-salts
```

The command prints candidate salts. Pick one and update the corresponding constant in `script/000_Constants.sol`:

- `TESTNET_STAGING_RESERVE_PROXY_SALT`
- `TESTNET_PROD_RESERVE_PROXY_SALT`
- `MAINNET_PROD_RESERVE_PROXY_SALT`

### Step 3: Verify the prefix

Re-run the simulation to confirm that the xReserve proxy address matches the desired prefix for your environment.

Note: For verification, only ENV and RPC_URL (and LOCAL_CREATE2_FACTORY_ADDRESS/LOCAL_DEPLOYER_ADDRESS if ENV=LOCAL) will matter for the proxy's address. The other variables can be set to any value.
