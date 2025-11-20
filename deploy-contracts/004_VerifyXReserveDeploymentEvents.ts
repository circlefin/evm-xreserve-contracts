/**
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Verifies xReserve deployment-related events by parsing a deployment transaction receipt.
 *
 * Expected events (from the proxy address):
 * - OwnershipTransferred(address 0x0, address factory)     [emitted during placeholder init]
 * - Upgraded(address implementation)                        [emitted when proxy upgraded to final implementation]
 * - OwnershipTransferStarted(address previous, address next) [emitted when ownership transfer initiated]
 * - PauserUpdated(address oldPauser, address newPauser)     [emitted when pauser is set]
 * - BlocklisterUpdated(address oldBlocklister, address new) [emitted when blocklister is set]
 * - TokenSupported(address indexed token)                    [emitted for each configured token]
 *
 * Inputs (flags or environment):
 *   --rpcUrl                 (default: process.env.RPC_URL)
 *   --proxyAddress           (required)
 *   --deploymentTxHash       (required)
 *   --factoryAddress         (default: LOCAL_CREATE2_FACTORY_ADDRESS)
 *   --pauser                 (default: X_RESERVE_PAUSER_ADDRESS)
 *   --blocklister            (default: X_RESERVE_BLOCKLISTER_ADDRESS)
 *   --supportedTokenPrefix   (default: X_RESERVE_SUPPORTED_TOKEN_)
 *   --ownershipTransferCompleted (default: process.env.X_RESERVE_OWNERSHIP_TRANSFER_COMPLETED)
 *   --ownershipAcceptTxHash      (required if ownershipTransferCompleted is true)
 */

import 'dotenv/config';
import { Interface, JsonRpcProvider, Log } from 'ethers';

/** Ethereum address type alias for better code readability */
type Address = string;

/**
 * Represents an event
 * @property name The event name (e.g., 'Upgraded', 'OwnershipTransferred')
 * @property args The event arguments
 */
type Event = {
    name: string;
    args: unknown[];
};

/**
 * Extracts command-line argument value by flag name with optional validation
 * Supports both --flag value and --flag=value formats
 * @param flag The flag name (e.g., '--proxyAddress')
 * @param required Whether the argument is required (throws error if missing)
 * @returns The argument value or undefined if not found (and not required)
 * @throws Error if required argument is missing
 */
function getCliArg(flag: string, required: boolean = false): string | undefined {
    const idx = process.argv.findIndex((a) => a === flag || a.startsWith(`${flag}=`));
    if (idx === -1) {
        if (required) {
            throw new Error(`Missing required argument: ${flag}`);
        }
        return undefined;
    }
    const cur = process.argv[idx];
    if (cur.includes('=')) return cur.split('=').slice(1).join('=');
    return process.argv[idx + 1];
}

/**
 * Normalizes an Ethereum address to lowercase for consistent comparison
 * @param address The address to normalize
 * @returns Lowercase address or undefined if input is falsy
 */
function normalize(address: string | undefined): string | undefined {
    return address ? address.toLowerCase() : undefined;
}

/**
 * Parses a boolean value from string input
 */
function parseBool(input: string | undefined, defaultValue: boolean = false): boolean {
    if (input === undefined || input === null) return defaultValue;
    const v = String(input).trim().toLowerCase();
    return v === 'true' || v === '1' || v === 'yes' || v === 'y';
}

// EIP-1967 implementation slot
const EIP1967_IMPLEMENTATION_SLOT =
    '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';

/**
 * Retrieves the implementation address from an EIP-1967 proxy contract
 * @param provider The JSON-RPC provider for blockchain queries
 * @param proxy The proxy contract address
 * @returns The implementation contract address
 */
async function getImplementationAddress(provider: JsonRpcProvider, proxy: Address): Promise<Address> {
    const raw = await provider.getStorage(proxy, EIP1967_IMPLEMENTATION_SLOT);
    // Extract last 20 bytes (40 hex characters) from the 32-byte storage slot
    const addr = '0x' + raw.slice(26);
    return addr as Address;
}

/**
 * Scans environment variables for supported token addresses
 * Looks for variables like X_RESERVE_SUPPORTED_TOKEN_1, X_RESERVE_SUPPORTED_TOKEN_2, etc.
 * @param prefix The environment variable prefix (e.g., 'X_RESERVE_SUPPORTED_TOKEN_')
 * @returns Array of token addresses found in environment variables
 */
function scanSupportedTokens(prefix: string): Address[] {
    const tokens: Address[] = [];
    const maxTokens = parseInt(process.env.MAX_SUPPORTED_TOKENS || '100', 10);
    for (let i = 1; i <= maxTokens; i++) {
        const v = process.env[`${prefix}${i}` as keyof NodeJS.ProcessEnv];
        if (!v) break;
        tokens.push(v);
    }
    return tokens;
}

/**
 * Compares two events for equality, handling address normalization
 * @param a The parsed event from transaction logs
 * @param b The expected event to match against
 * @returns True if events match (name and all arguments)
 */
function eventsEqual(a: Event, b: Event): boolean {
    if (a.name !== b.name) return false;
    const aArgs = a.args ? Array.from(a.args) : [];
    if (aArgs.length !== b.args.length) return false;
    for (let i = 0; i < aArgs.length; i++) {
        const av = aArgs[i];
        const bv = b.args[i];
        // Compare addresses case-insensitively, otherwise fallback to strict JSON compare
        if (typeof av === 'string' && typeof bv === 'string' && av.startsWith('0x') && bv.startsWith('0x')) {
            if (normalize(av) !== normalize(bv)) return false;
        } else if (JSON.stringify(av) !== JSON.stringify(bv)) {
            return false;
        }
    }
    return true;
}

/**
 * Searches for an expected event in the parsed events array
 * @param events Array of parsed events from transaction logs
 * @param expected The expected event to find
 * @returns Index of the matching event, or -1 if not found
 */
function findEvent(events: Event[], expected: Event): number {
    for (let i = 0; i < events.length; i++) {
        if (eventsEqual(events[i], expected)) return i;
    }
    return -1;
}

/**
 * Fetches and parses events from a transaction receipt for a specific proxy address
 * @param provider The JSON-RPC provider for blockchain queries
 * @param deploymentTxHash The transaction hash to fetch events from
 * @param proxyAddress The proxy contract address to filter events for
 * @returns Array of parsed events from the proxy address
 * @throws Error if transaction receipt is not found
 */
async function fetchEventsFromTransaction(
    provider: JsonRpcProvider,
    deploymentTxHash: string,
    proxyAddress: Address
): Promise<Event[]> {
    const receipt = await provider.getTransactionReceipt(deploymentTxHash);
    if (!receipt) throw new Error(`Transaction receipt not found for ${deploymentTxHash}`);

    const iface = new Interface([
        'event Upgraded(address indexed implementation)',
        'event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)',
        'event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner)',
        'event PauserUpdated(address indexed oldPauser, address indexed newPauser)',
        'event BlocklisterUpdated(address indexed oldBlocklister, address indexed newBlocklister)',
        'event TokenSupported(address indexed token)'
    ]);
    const proxyAddrNorm = normalize(proxyAddress);

    const parsed: Event[] = [];
    const logsFromProxy = receipt.logs.filter((l: Log) => normalize(l.address) === proxyAddrNorm);
    for (let i = 0; i < logsFromProxy.length; i++) {
        const log = logsFromProxy[i];
        try {
            const parsedLog = iface.parseLog(log);
            if (parsedLog?.name) {
                parsed.push({ name: parsedLog.name, args: Array.from(parsedLog.args || []) });
            }
        } catch (error) {
            // error on non-matching logs from the proxy address
            throw new Error(`Unexpected log from proxy address ${proxyAddress}: ${JSON.stringify(log)}. Error: ${error}`);
        }
    }

    return parsed;
}

/**
 * Convenience wrapper to fetch and merge events from multiple transactions
 */
async function fetchEventsFromTransactions(
    provider: JsonRpcProvider,
    txHashes: string[],
    proxyAddress: Address
): Promise<Event[]> {
    const all: Event[] = [];
    for (const h of txHashes) {
        if (!h) continue;
        const events = await fetchEventsFromTransaction(provider, h, proxyAddress);
        all.push(...events);
    }
    return all;
}

/**
 * Constructs the expected events array for xReserve deployment verification
 * @param implAddress The implementation contract address
 * @param factoryAddress The factory contract address
 * @param ownerAddress The owner address
 * @param pauser The pauser address
 * @param blocklister The blocklister address
 * @param supportedTokens Array of supported token addresses
 * @returns Array of expected events
 */
function buildExpectedEvents(
    implAddress: Address,
    factoryAddress: Address,
    ownerAddress: Address,
    pauser: Address,
    blocklister: Address,
    supportedTokens: Address[],
    ownershipTransferCompleted: boolean
): Event[] {

    const expected: Event[] = [];

    // Expected events from proxy construction and upgrade flow
    expected.push({ name: 'OwnershipTransferred', args: ['0x0000000000000000000000000000000000000000', factoryAddress] });
    expected.push({ name: 'Upgraded', args: [implAddress] });
    expected.push({ name: 'OwnershipTransferStarted', args: [factoryAddress, ownerAddress] });
    if (ownershipTransferCompleted) {
        // After completion we expect the final ownership transfer event to the designated owner
        expected.push({ name: 'OwnershipTransferred', args: [factoryAddress, ownerAddress] });
    }
    expected.push({ name: 'PauserUpdated', args: ['0x0000000000000000000000000000000000000000', pauser] });
    expected.push({ name: 'BlocklisterUpdated', args: ['0x0000000000000000000000000000000000000000', blocklister] });
    for (const token of supportedTokens) {
        expected.push({ name: 'TokenSupported', args: [token] });
    }

    return expected;
}

/**
 * Prints the verification report including configuration, parsed events, and verification results
 * @param proxyAddress The proxy contract address
 * @param implAddress The implementation contract address
 * @param factoryAddress The factory contract address
 * @param pauser The pauser address
 * @param blocklister The blocklister address
 * @param supportedTokens Array of supported token addresses
 * @param parsed Array of parsed events from transaction logs
 * @param expected Array of expected events
 * @param foundEvents Array of found events
 * @param missingEvents Array of missing events
 * @returns True if verification passed, false otherwise
 */
function printVerificationReport(
    proxyAddress: Address,
    implAddress: Address,
    factoryAddress: Address,
    pauser: Address,
    blocklister: Address,
    supportedTokens: Address[],
    parsed: Event[],
    expected: Event[],
    foundEvents: Event[],
    missingEvents: Event[]
): boolean {
    // Output report
    console.log('xReserve Deployment Event Verification');
    console.log('Proxy Address:', proxyAddress);
    console.log('Implementation Address (EIP-1967):', implAddress);
    console.log('Factory Address:', factoryAddress);
    console.log('Pauser:', pauser);
    console.log('Blocklister:', blocklister);
    console.log('Supported Tokens:', supportedTokens);
    console.log('');

    console.log('All parsed proxy events (from receipt):');
    parsed.forEach((e, i) => {
        console.log(`${i}. ${e.name}`, e.args);
    });
    console.log('');

    const success = missingEvents.length === 0;
    console.log('Expected events and status:');

    // Use already computed verification results instead of searching again
    for (const exp of expected) {
        const foundEvent = foundEvents.find(fe => eventsEqual(fe, exp));
        const status = foundEvent ? 'FOUND' : 'MISSING';
        console.log(`- ${exp.name}(${exp.args.map((a) => String(a)).join(', ')}) -> ${status}`);
    }
    console.log('');

    if (success) {
        console.log('✅ Verification PASSED. All expected deployment events are present.');
    } else {
        console.error('❌ Verification FAILED. Missing events above.');
    }
    return success;
}

async function main() {
    // Parse CLI arguments and environment variables
    const rpcUrl = getCliArg('--rpcUrl') || process.env.RPC_URL || 'http://localhost:8545';
    const proxyAddress = getCliArg('--proxyAddress', true) as Address;
    const deploymentTxHash = getCliArg('--deploymentTxHash', true)!;

    const factoryAddress = (getCliArg('--factoryAddress') ||
        process.env.LOCAL_CREATE2_FACTORY_ADDRESS) as Address | undefined;

    const pauser = (getCliArg('--pauser') || process.env.X_RESERVE_PAUSER_ADDRESS) as Address | undefined;
    const blocklister = (getCliArg('--blocklister') || process.env.X_RESERVE_BLOCKLISTER_ADDRESS) as Address | undefined;
    const tokenPrefix = getCliArg('--supportedTokenPrefix') || 'X_RESERVE_SUPPORTED_TOKEN_';

    const ownershipTransferCompleted = parseBool(
        getCliArg('--ownershipTransferCompleted') || process.env.X_RESERVE_OWNERSHIP_TRANSFER_COMPLETED,
        false
    );
    const ownershipAcceptTxHash = getCliArg('--ownershipAcceptTxHash');

    if (!factoryAddress) throw new Error('Missing factory address. Provide --factoryAddress or set LOCAL_CREATE2_FACTORY_ADDRESS.');
    if (!pauser) throw new Error('Missing pauser. Provide --pauser or set X_RESERVE_PAUSER_ADDRESS.');
    if (!blocklister) throw new Error('Missing blocklister. Provide --blocklister or set X_RESERVE_BLOCKLISTER_ADDRESS.');

    const ownerAddress = process.env.X_RESERVE_OWNER_ADDRESS;
    if (!ownerAddress) throw new Error('Missing required environment variable: X_RESERVE_OWNER_ADDRESS.');

    // Fetch and parse events from the relevant transaction(s)
    const provider = new JsonRpcProvider(rpcUrl);
    const txHashes: string[] = [deploymentTxHash];
    if (ownershipTransferCompleted) {
        if (!ownershipAcceptTxHash) {
            throw new Error('ownershipTransferCompleted is true, but --ownershipAcceptTxHash was not provided.');
        }
        txHashes.push(ownershipAcceptTxHash);
    }
    const parsed = await fetchEventsFromTransactions(provider, txHashes, proxyAddress);

    // Build expected events
    const supportedTokens = scanSupportedTokens(tokenPrefix);
    if (supportedTokens.length === 0) {
        throw new Error(`No supported tokens found. At least one token must be specified with environment variable prefix: ${tokenPrefix}`);
    }
    const implAddress = await getImplementationAddress(provider, proxyAddress);
    const expected = buildExpectedEvents(
        implAddress,
        factoryAddress,
        ownerAddress,
        pauser,
        blocklister,
        supportedTokens,
        ownershipTransferCompleted
    );

    // Verify all expected events are present
    const missingEvents: Event[] = [];
    const foundEvents: Event[] = [];

    for (const exp of expected) {
        const idx = findEvent(parsed, exp);
        if (idx === -1) {
            missingEvents.push(exp);
        } else {
            foundEvents.push(exp);
        }
    }

    // Output report
    const success = printVerificationReport(
        proxyAddress,
        implAddress,
        factoryAddress,
        pauser,
        blocklister,
        supportedTokens,
        parsed,
        expected,
        foundEvents,
        missingEvents
    );

    if (!success) {
        process.exitCode = 1;
        return;
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});


