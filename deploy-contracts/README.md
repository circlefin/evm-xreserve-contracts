# xReserve Deployment System

This directory contains a complete deployment system for the **xReserve** contract, leveraging the gateway's existing infrastructure while maintaining xReserve-specific components.

## 🏗️ How it Works

The deployment uses a sophisticated **5-step UUPS upgradeable proxy pattern** that ensures safe, deterministic, and atomic deployment:

### Deployment Steps:

1. **Deploy the UpgradeablePlaceholder implementation** - A minimal UUPS contract for initial proxy setup
2. **Deploy the xReserve implementation** - The actual implementation contract with constructor arguments
3. **Deploy the ERC1967Proxy and setup the proxy**:
   - Deploy the ERC1967 Proxy, set the implementation to UpgradeablePlaceholder and initialize the owner to Create2Factory address
   - In the same transaction, upgrade the implementation to xReserve and initialize it properly
4. **Atomic ownership transfer** - Transfer ownership from factory to the intended owner using 2-step ownership

The reason for setting the owner of UpgradeablePlaceholder to the Create2Factory address is that since the owner is part of the address computation, we use Create2Factory to avoid managing an extra EOA key.

Since the owner of UpgradeablePlaceholder is Create2Factory and only the owner can perform `upgradeToAndCall`, we use `Create2Factory.deployAndMultiCall` to upgrade to the actual implementation in the proxy deployment call.

## 📋 Prerequisites

Before deploying the contracts, ensure you have:

1. **Create a `.env` file** from `.env.example` and set up environment variables
2. **Load environment variables** by running `source .env`
3. **Verify sufficient funds** in the deployer account for the target network
4. **For contracts that require real implementations** (like supported tokens), ensure they're deployed first

## 🚀 Deploying Contracts

### Step 1: Start a Local Blockchain
*Only needed for local deployment*

Start a local RPC node at http://127.0.0.1:8545 by running:
```bash
anvil --port 8545 --host 0.0.0.0
```

### Step 2: Deploy Create2Factory Contract
*Only needed for local deployment*

Use the gateway's Create2Factory deployment:

```bash
# Deploy using gateway's Create2Factory
forge create lib/evm-gateway-contracts/script/Create2Factory.sol:Create2Factory \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $LOCAL_DEPLOYER_KEY \
  --constructor-args $LOCAL_DEPLOYER_ADDRESS \
  --broadcast
```

Add the deployed Create2Factory contract address to your `.env` file under `LOCAL_CREATE2_FACTORY_ADDRESS`.

### Step 3: Deploy Dependencies

#### For Local Testing:

**3a. Deploy Gateway Contracts**
```bash
# Deploy GatewayWallet and GatewayMinter using our helper script
forge script test/utils/DeployGatewayForLocalnet.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $LOCAL_DEPLOYER_KEY \
  --broadcast -v
```

**3b. Deploy and Configure ERC20 Token**
```bash
# Deploy ERC20Mock token for testing
forge create lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol:ERC20Mock \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $LOCAL_DEPLOYER_KEY \
  --broadcast

# Add the ERC20Mock to GatewayWallet's supported tokens
cast send <GATEWAY_WALLET_ADDRESS> "addSupportedToken(address)" <ERC20_MOCK_ADDRESS> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $LOCAL_DEPLOYER_KEY
```

**3c. Update .env with Deployed Addresses**
Update your `.env` file with the actual deployed contract addresses:
```bash
X_RESERVE_GATEWAY_WALLET_ADDRESS=<deployed_gateway_wallet_address>
X_RESERVE_GATEWAY_MINTER_ADDRESS=<deployed_gateway_minter_address>
X_RESERVE_SUPPORTED_TOKEN_1=<deployed_erc20_mock_address>
# Use deployed Create2Factory address for token messenger addresses in local testing
X_RESERVE_TOKEN_MESSENGER_ADDRESS=<create2_factory_address>
X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS=<create2_factory_address>
```

#### For Testnet/Mainnet:
Use real deployed contract addresses in your `.env` file. Ensure all dependencies are properly deployed and configured.

### Step 4: Deploy xReserve System

Deploy the complete xReserve system (includes RemoteDomainDepositor, placeholder, implementation, and proxy):

```bash
# Deploy complete xReserve system using CREATE2
ENV=LOCAL forge script deploy-contracts/001_DeployXReserve.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $LOCAL_DEPLOYER_KEY \
  --broadcast -v
```

This single script deploys:
1. **RemoteDomainDepositor implementation** - Required dependency
2. **UpgradeablePlaceholder** - Temporary implementation for proxy
3. **xReserve implementation** - Main contract logic
4. **ERC1967Proxy** - Upgradeable proxy pointing to xReserve

**Parameters:**
- `ENV`: Use `LOCAL` for local deployment. Or choose from `TESTNET_STAGING`, `TESTNET_PROD`, and `MAINNET_PROD`
- `RPC_URL`: The RPC URL for the targeted blockchain. Use `http://127.0.0.1:8545` for local deployment

The generated transaction data will be available in the `broadcast/` directory and can be used for signing.

### Step 5: Onboard Remote Domains (Testnet only)
This step registers remote domains and their required remote token mappings on the existing xReserve proxy. Run the onboarding script against a real testnet using a transient environment variable for the private key (no secrets written to `.env`).

1) Prepare environment (non-secrets only) in your `.env`:
```bash
# Core
RPC_URL=<your_testnet_rpc_url>
X_RESERVE_PROXY_ADDRESS=<xreserve_proxy_address>
X_RESERVE_REGISTRATION_MANAGER_ADDRESS=<manager_eoa_address>

# Domain 1 (repeat for 2..N)
X_RESERVE_REMOTE_DOMAIN_1=<remote_domain_id_uint32>
X_RESERVE_REMOTE_DOMAIN_1_MANAGER_ADDRESS=<address>
X_RESERVE_REMOTE_DOMAIN_1_PAUSER_ADDRESS=<address>
# Optional: hook executor (defaults to zero address if unset)
# 0x0000000000000000000000000000000000000000
X_RESERVE_REMOTE_DOMAIN_1_HOOK_EXECUTOR_ADDRESS=<address>
X_RESERVE_REMOTE_DOMAIN_1_SIGNATURE_THRESHOLD=<uint>
X_RESERVE_REMOTE_DOMAIN_1_PERSISTENT_SIGNATURE_BUFFER_DELAY_BLOCKS=<uint>
X_RESERVE_REMOTE_DOMAIN_1_ATTESTER_1=<address>
# ... optionally _ATTESTER_2 .. _ATTESTER_5

# Required token mapping for domain 1
X_RESERVE_REMOTE_DOMAIN_1_LOCAL_TOKEN=<address>
X_RESERVE_REMOTE_DOMAIN_1_REMOTE_TOKEN=<bytes32>
```

2) Set and verify your registration manager private key:
```bash
export REG_MGR_PK="0xYOUR_PRIVATE_KEY"
cast wallet address --private-key "$REG_MGR_PK"
# Ensure this equals $X_RESERVE_REGISTRATION_MANAGER_ADDRESS
```

3) Dry-run the script (no broadcast):
```bash
forge script deploy-contracts/005_OnboardRemoteDomains.s.sol:OnboardRemoteDomains \
  --rpc-url "$RPC_URL" \
  --private-key "$REG_MGR_PK" \
  -vvvv
```

4) Broadcast to the testnet using the transient variable:
```bash
forge script deploy-contracts/005_OnboardRemoteDomains.s.sol:OnboardRemoteDomains \
  --rpc-url "$RPC_URL" \
  --private-key "$REG_MGR_PK" \
  --broadcast \
  -vvvv
```

5) Clean up the private key from your environment:
```bash
unset REG_MGR_PK
```

Notes:
- The script calls `vm.startBroadcast(registrationManager)`, so the signer (derived from `REG_MGR_PK`) must equal `X_RESERVE_REGISTRATION_MANAGER_ADDRESS`.
- Configure domains sequentially using `X_RESERVE_REMOTE_DOMAIN_1_*`, `X_RESERVE_REMOTE_DOMAIN_2_*`, etc. The script stops at the first missing index and requires at least one domain.
- Keep secrets out of `.env`. Use the transient variable only for the invocation.
- The hook executor is optional; if `X_RESERVE_REMOTE_DOMAIN_1_HOOK_EXECUTOR_ADDRESS` is unset, the script defaults it to the zero address.

## ✅ Deployed Contract Validation

After deployment, validate that everything was deployed correctly using the automated validation scripts:

### Automated Validation Scripts

**002_DeployedContractBytecodeValidation.s.sol** - Validates that deployed contract bytecode matches expected bytecode:
```bash
forge script deploy-contracts/002_DeployedContractBytecodeValidation.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

**003_DeployedContractStateValidation.s.sol** - Validates deployed contract state and configuration:
```bash
forge script deploy-contracts/003_DeployedContractStateValidation.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

**004_VerifyXReserveDeploymentEvents.ts** - Verifies deployment events were emitted correctly:

**Required Arguments:**
- `--proxyAddress`: The xReserve proxy contract address
- `--deploymentTxHash`: The transaction hash of the deployment transaction

**Optional Arguments:**
- `--rpcUrl`: RPC URL (defaults to `process.env.RPC_URL` or `http://localhost:8545`)
- `--factoryAddress`: Factory address (defaults to `LOCAL_CREATE2_FACTORY_ADDRESS`)
- `--pauser`: Pauser address (defaults to `X_RESERVE_PAUSER_ADDRESS`)
- `--blocklister`: Blocklister address (defaults to `X_RESERVE_BLOCKLISTER_ADDRESS`)
- `--supportedTokenPrefix`: Environment variable prefix for supported tokens (defaults to `X_RESERVE_SUPPORTED_TOKEN_`)
 - `--ownershipTransferCompleted`: Whether two-step ownership transfer has completed (defaults to `X_RESERVE_OWNERSHIP_TRANSFER_COMPLETED`)
 - `--ownershipAcceptTxHash`: Transaction hash of `acceptOwnership()` (required if `--ownershipTransferCompleted` is true)

**Required Environment Variables:**
- `X_RESERVE_OWNER_ADDRESS`: The owner address for the reserve

**Usage:**
```bash
# Basic usage (requires proxy address and deployment tx hash)
yarn verify:xreserve:events -- --proxyAddress <PROXY_ADDRESS> --deploymentTxHash <TX_HASH>

# With custom RPC URL
yarn verify:xreserve:events -- --proxyAddress <PROXY_ADDRESS> --deploymentTxHash <TX_HASH> --rpcUrl <RPC_URL>

# With custom factory address
yarn verify:xreserve:events -- --proxyAddress <PROXY_ADDRESS> --deploymentTxHash <TX_HASH> --factoryAddress <FACTORY_ADDRESS>

# After completing two-step ownership transfer
# (must provide the acceptOwnership tx hash and set the completed flag)
yarn verify:xreserve:events -- \
  --proxyAddress <PROXY_ADDRESS> \
  --deploymentTxHash <DEPLOY_TX_HASH> \
  --ownershipTransferCompleted true \
  --ownershipAcceptTxHash <ACCEPT_OWNERSHIP_TX_HASH>
```

**Integration Testing:**
For automated testing of the deployment and event verification process, use the integration script:
```bash
# Run integration test (deploys contracts and verifies deployment events)
./scripts/integration_verify_xreserve_events.sh
```

This script will:
1. Start anvil (if not running)
2. Deploy Create2Factory (if needed)
3. Deploy the complete xReserve system
4. Extract proxy address and deployment transaction hash
5. Run the deployment event verification script (`004_VerifyXReserveDeploymentEvents.ts`)
6. Complete two-step ownership transfer locally (`acceptOwnership`) and verify the final `OwnershipTransferred` event when enabled

**Note:** This integration test only covers deployment event verification. For complete validation, you should also run the bytecode and state validation scripts (`002_` and `003_`) separately.

### Manual Validation

You can also manually validate deployment using these commands:

```bash
# Check the proxy owner (should be the factory address initially)
cast call <X_RESERVE_PROXY_ADDRESS> "owner()" --rpc-url $RPC_URL

# Verify the xReserve is properly initialized and working
cast call <X_RESERVE_PROXY_ADDRESS> "domain()" --rpc-url $RPC_URL

# Check that supported tokens are configured correctly
cast call <X_RESERVE_PROXY_ADDRESS> "isTokenSupported(address)" <ERC20_MOCK_ADDRESS> --rpc-url $RPC_URL

# Verify gateway contracts are working
cast call <GATEWAY_WALLET_ADDRESS> "isTokenSupported(address)" <ERC20_MOCK_ADDRESS> --rpc-url $RPC_URL

# Check RemoteDomainDepositor has code
cast code <REMOTE_DOMAIN_DEPOSITOR_ADDRESS> --rpc-url $RPC_URL

# Verify the proxy is pointing to the correct implementation
cast call <X_RESERVE_PROXY_ADDRESS> "proxiableUUID()" --rpc-url $RPC_URL
```

**Expected Results:**
- Owner should return the factory address initially (ownership can be transferred later)
- Domain should return the configured domain ID (e.g., `1` for local)
- Token support checks should return `true` (`0x01`)
- RemoteDomainDepositor should have deployed bytecode (non-empty)
- Proxy should be upgradeable and working correctly

## 📂 Directory Structure

```
deploy-contracts/
├── 000_Constants.sol                     # Environment configuration and salts
├── 001_DeployXReserve.sol                # Complete xReserve system deployment
├── 002_DeployedContractBytecodeValidation.s.sol  # Bytecode validation script
├── 003_DeployedContractStateValidation.s.sol    # State validation script
├── 004_VerifyXReserveDeploymentEvents.ts  # Event verification script
├── BaseBytecodeDeployScript.sol          # Base deployment utilities
└── compiled-contract-artifacts/          # Pre-compiled contract artifacts
    ├── xReserve.json
    ├── RemoteDomainDepositor.json
    ├── UpgradeablePlaceholder.json
    └── ERC1967Proxy.json
```

**Deployment Order:**
1. **test/utils/DeployGatewayForLocalnet.sol** - Deploy gateway dependencies (local only)
2. **001_DeployXReserve.sol** - Deploy complete xReserve system (RemoteDomainDepositor, placeholder, implementation, proxy)
3. **002_DeployedContractBytecodeValidation.s.sol** - Validate deployed contract bytecode matches expected bytecode
4. **003_DeployedContractStateValidation.s.sol** - Validate deployed contract state and configuration
5. **004_VerifyXReserveDeploymentEvents.ts** - Verify deployment events were emitted correctly

## 📝 Complete Local Deployment Summary

For a complete local deployment from scratch:

1. **Start anvil**: `anvil &`
2. **Deploy Create2Factory**: Use gateway's factory contract
3. **Deploy Gateway contracts**: Run `test/utils/DeployGatewayForLocalnet.sol`
4. **Deploy and configure ERC20Mock**: Deploy token and add to GatewayWallet
5. **Update .env**: Add all deployed addresses
6. **Deploy xReserve system**: Run `001_DeployXReserve.sol` (includes RemoteDomainDepositor)
7. **Validate bytecode**: Run `002_DeployedContractBytecodeValidation.s.sol`
8. **Validate state**: Run `003_DeployedContractStateValidation.s.sol`
9. **Verify events**: Run `004_VerifyXReserveDeploymentEvents.ts`

This creates a fully functional xReserve system with deterministic addresses using the proven CREATE2 factory pattern, with comprehensive validation at each step.

## 🔧 Environment Variables

All required environment variables are documented in `.env.example`. Key variables include:

### Core Configuration
- `ENV`: Deployment environment (`LOCAL`, `TESTNET_STAGING`, `TESTNET_PROD`, `MAINNET_PROD`)
- `RPC_URL`: RPC endpoint for the target network
- `LOCAL_CREATE2_FACTORY_ADDRESS`: Address of the deployed Create2Factory (local only)
- `LOCAL_DEPLOYER_ADDRESS`: Address authorized to use the factory (local only)
- `LOCAL_DEPLOYER_KEY`: Private key for local deployment

### xReserve Configuration
- `X_RESERVE_OWNER_ADDRESS`: Final owner of the xReserve (uses 2-step ownership)
- `X_RESERVE_OWNERSHIP_TRANSFER_COMPLETED`: Set to `true` once `acceptOwnership()` has been executed; used by validation scripts to expect final ownership state and event
- `X_RESERVE_PAUSER_ADDRESS`: Address that can pause the reserve
- `X_RESERVE_BLOCKLISTER_ADDRESS`: Address that can blocklist addresses
- `X_RESERVE_REGISTRATION_MANAGER_ADDRESS`: Address that can register remote domains/tokens
- `X_RESERVE_DOMAIN`: Domain ID for this reserve instance
- `X_RESERVE_SUPPORTED_TOKEN_1`: Address of supported ERC20 token (supports up to 1 tokens)

### Constructor Dependencies (Immutable)
- `X_RESERVE_GATEWAY_MINTER_ADDRESS`: Gateway minter contract
- `X_RESERVE_GATEWAY_WALLET_ADDRESS`: Gateway wallet contract
- `X_RESERVE_TOKEN_MESSENGER_ADDRESS`: Token messenger contract
- `X_RESERVE_TOKEN_MESSENGER_V2_ADDRESS`: Token messenger v2 contract
- `X_RESERVE_REMOTE_DOMAIN_DEPOSITOR_IMPL_ADDRESS`: Remote domain depositor implementation

### Verification
- `ETHERSCAN_API_KEY`: API key for contract verification (works for both mainnet and testnet)

## 🧪 Testing

Run the deployment tests:

```bash
forge test --match-path test/script/DeployXReserveTest.t.sol -v
```

## 🔄 Multi-Environment Support

The system supports multiple deployment environments with different configurations:

- **LOCAL**: For local development and testing
- **TESTNET_STAGING**: For staging environment testing
- **TESTNET_PROD**: For production-like testnet deployment
- **MAINNET_PROD**: For mainnet production deployment

Each environment has its own salt configuration for deterministic address generation.

## 🛡️ Security Features

- **Deterministic addresses** using CREATE2 for predictable deployments
- **Atomic initialization** ensures consistent state during deployment
- **2-step ownership transfer** prevents accidental ownership loss
- **Factory-based deployment** eliminates need for managing additional EOA keys
- **Leverages proven gateway infrastructure** while maintaining xReserve-specific components
- **Distinct salts** for placeholder and implementation to prevent address collisions


## 🔧 Troubleshooting

### Common Issues and Solutions
**Problem: `UnsupportedToken` error**
**Solution**: Add the token to GatewayWallet before xReserve deployment:
```bash
cast send <GATEWAY_WALLET_ADDRESS> "addSupportedToken(address)" <TOKEN_ADDRESS> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```