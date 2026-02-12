# ProofPulse — Implementation Plan

## Overview

ProofPulse is a cross-chain Proof of Reserve verification system for Wrapped Bitcoin (WBTC). It reads reserve data from Bitcoin (via Blockstream API) and token supply from Ethereum (via EVM calls), computes a collateral health ratio, optionally queries Gemini LLM for anomaly detection, and publishes results onchain through a CRE workflow on Sepolia.

This plan follows the patterns established in the [CRE Bootcamp 2026](https://smartcontractkit.github.io/cre-bootcamp-2026/setup/welcome.html) and the [CRE official docs](https://docs.chain.link/cre).

---

## Prerequisites

| Tool              | Version   | Purpose                            |
|-------------------|-----------|------------------------------------|
| Node.js           | v20+      | Runtime                            |
| Bun               | v1.3+     | Package manager / bundler          |
| CRE CLI           | latest    | Workflow simulation & deployment   |
| Foundry (forge)   | latest    | Solidity compilation & deployment  |
| Gemini API Key    | —         | AI anomaly detection (Handler 2)   |
| Sepolia ETH       | —         | Gas for contract deployment & txs  |

---

## Phase 1: Project Scaffolding

### 1.1 Initialize CRE project structure

Create the directory layout matching the architecture doc:

```
proofpulse/
├── contracts/                          # Foundry project
│   ├── src/
│   │   ├── WBTCProofOfReserve.sol      # Consumer contract (IReceiver)
│   │   └── interfaces/
│   │       ├── IReceiver.sol
│   │       └── ReceiverTemplate.sol
│   ├── test/
│   │   └── WBTCProofOfReserve.t.sol
│   ├── foundry.toml
│   └── foundry.lock
├── my-workflow/                        # CRE workflow (TypeScript)
│   ├── main.ts                         # Entry point — registers 3 handlers
│   ├── cronCallback.ts                 # Handler 1: Cron → PoR data feed update
│   ├── logCallback.ts                  # Handler 2: Log → AI anomaly detection
│   ├── httpCallback.ts                 # Handler 3: HTTP → On-demand PoR query
│   ├── gemini.ts                       # Gemini LLM helper
│   ├── contracts/
│   │   └── abi.ts                      # ABI definitions (WBTC, AggregatorV3, PoR contract)
│   ├── config.staging.json             # Addresses, API URLs, custody addresses
│   ├── workflow.yaml                   # Workflow-specific CRE settings
│   ├── package.json
│   └── tsconfig.json
├── project.yaml                        # CRE project config (RPCs, targets)
├── secrets.yaml                        # Secret references (GEMINI_API_KEY)
├── .env.example                        # Template for environment variables
└── .gitignore
```

### 1.2 Initialize Foundry project

```bash
cd contracts/
forge init --no-commit
# Install OpenZeppelin for Ownable, IERC165
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

Configure `foundry.toml`:
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/"
]
```

### 1.3 Initialize CRE workflow

```bash
cd my-workflow/
bun init
```

`package.json` dependencies:
```json
{
  "name": "proofpulse-workflow",
  "version": "1.0.0",
  "main": "dist/main.js",
  "private": true,
  "scripts": {
    "postinstall": "bunx cre-setup"
  },
  "dependencies": {
    "@chainlink/cre-sdk": "^1.0.1"
  },
  "devDependencies": {
    "@types/bun": "1.2.21"
  }
}
```

`tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "resolveJsonModule": true,
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "."
  },
  "include": ["./**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

### 1.4 CRE configuration files

**`project.yaml`** (root):
```yaml
staging-settings:
  rpcs:
    - chain-name: ethereum-testnet-sepolia
      url: https://ethereum-sepolia-rpc.publicnode.com
```

**`secrets.yaml`** (root):
```yaml
secretsNames:
    GEMINI_API_KEY:
        - GEMINI_API_KEY_VAR
```

**`my-workflow/workflow.yaml`**:
```yaml
staging-settings:
  user-workflow:
    workflow-name: "proofpulse-staging"
    workflow-entry-point: "./main.ts"
    workflow-config-path: "./config.staging.json"
    workflow-secrets-path: "../secrets.yaml"
```

**`my-workflow/config.staging.json`**:
```json
{
  "geminiModel": "gemini-2.0-flash",
  "evms": [{
    "chainSelectorName": "ethereum-testnet-sepolia",
    "porContractAddress": "DEPLOYED_CONTRACT_ADDRESS",
    "gasLimit": "500000"
  }],
  "wbtcAddress": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
  "chainlinkPorFeed": "0xB622b7D6d9131cF6A1230EBa91E5da58dbea6F59",
  "cronSchedule": "0 * * * *",
  "blockstreamApiUrl": "https://blockstream.info/api",
  "coingeckoApiUrl": "https://api.coingecko.com/api/v3/simple/price",
  "geminiApiUrl": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
  "btcCustodyAddresses": [
    "3LYJfcfHPXYJreMsASk2jkn69LWEYKzexb",
    "bc1qa5wkgaew2dkv56kc6hp23ly7rsq3hjqmygsydj"
  ]
}
```

**`.env.example`**:
```
CRE_ETH_PRIVATE_KEY=<your-sepolia-private-key>
GEMINI_API_KEY_VAR=<your-gemini-api-key>
```

---

## Phase 2: Smart Contract (`WBTCProofOfReserve.sol`)

### 2.1 Contract interfaces

Copy `IReceiver.sol` and `ReceiverTemplate.sol` from the CRE bootcamp reference (these are the standard CRE receiver contracts that handle Forwarder authentication and `onReport()` routing).

### 2.2 Implement `WBTCProofOfReserve.sol`

The contract extends `ReceiverTemplate` and implements `_processReport()` with selector-based routing.

**State:**
```solidity
struct ReserveData {
    uint256 btcReserveSats;
    uint256 wbtcSupplySats;
    uint256 collateralRatioBps;
    uint256 btcUsdPriceCents;
    uint256 chainlinkReserveSats;
    uint256 timestamp;
}

struct RiskData {
    uint8 score;
    string recommendation;
    uint256 timestamp;
}

ReserveData public latestReserve;
ReserveData[] public reserveHistory;
RiskData public latestRisk;
```

**Forwarder-only functions** (called via `_processReport`):
- `_updateReserve(bytes calldata report)` — Decodes and stores PoR snapshot, emits `ReserveUpdated`. If ratio < 10000 bps, emits `UndercollateralizedAlert`. If divergence vs Chainlink > 5%, emits `ChainlinkDivergenceAlert`.
- `_updateRisk(bytes calldata report)` — Decodes and stores risk score + recommendation, emits `RiskUpdated`.

**Report routing in `_processReport`:**
- Prefix byte `0x01` → `_updateReserve(report[1:])`
- Prefix byte `0x02` → `_updateRisk(report[1:])`

**Public / view interface:**
- `isHealthy() → bool` — returns `latestReserve.collateralRatioBps >= 9900`
- `getLatestReserve() → ReserveData`
- `getLatestRisk() → (uint8, string)`
- `getReserveValueUsd() → uint256` — `(btcReserveSats * btcUsdPriceCents) / 1e8`
- `requestAudit(uint256 auditId)` — emits `AuditRequested(auditId)` event (triggers Handler 2)

**Events:**
- `ReserveUpdated(uint256 btcReserveSats, uint256 wbtcSupplySats, uint256 collateralRatioBps, uint256 timestamp)`
- `UndercollateralizedAlert(uint256 collateralRatioBps, uint256 timestamp)`
- `ChainlinkDivergenceAlert(uint256 ourReserve, uint256 clReserve, uint256 timestamp)`
- `RiskUpdated(uint8 score, string recommendation, uint256 timestamp)`
- `AuditRequested(uint256 indexed auditId)`

### 2.3 Unit tests (`WBTCProofOfReserve.t.sol`)

- Test `_processReport` routing with `0x01` and `0x02` prefixes
- Test `updateReserve` stores data and emits correct events
- Test `updateRisk` stores risk data
- Test `isHealthy()` returns correctly for over/under-collateralized
- Test `requestAudit` emits `AuditRequested`
- Test forwarder-only access control (reject calls from non-forwarder)

### 2.4 Deploy to Sepolia

```bash
forge create contracts/src/WBTCProofOfReserve.sol:WBTCProofOfReserve \
  --rpc-url $RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY \
  --broadcast \
  --constructor-args 0x15fc6ae953e024d975e77382eeec56a9101f9f88
```

Update `config.staging.json` with the deployed contract address.

---

## Phase 3: CRE Workflow — ABI Definitions

### 3.1 `my-workflow/contracts/abi.ts`

Define ABIs for all contracts the workflow interacts with:

1. **WBTC ABI** (Ethereum mainnet `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`):
   - `totalSupply() → uint256` (8 decimals = satoshis)

2. **Chainlink AggregatorV3 ABI** (`0xB622b7D6d9131cF6A1230EBa91E5da58dbea6F59`):
   - `latestRoundData() → (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)`

3. **WBTCProofOfReserve ABI** (deployed on Sepolia):
   - `updateReserve(uint256,uint256,uint256,uint256,uint256,uint256)` — for ABI encoding
   - `updateRisk(uint8,string,uint256)` — for ABI encoding
   - `getLatestReserve() → (uint256,uint256,uint256,uint256,uint256,uint256)` — for Handler 2 reads

These are viem-compatible ABI arrays (`const abi = [...] as const`).

---

## Phase 4: CRE Workflow — Handler 1 (Cron → PoR Data Feed)

### 4.1 `my-workflow/cronCallback.ts`

**Trigger:** Cron schedule (`"0 * * * *"` — hourly)

**Logic flow:**

1. **EVM Read: WBTC totalSupply** (DON mode)
   - `evmClient.callContract(runtime, { ... })` with encoded `totalSupply()` call
   - Target: `config.wbtcAddress` on Ethereum mainnet
   - Decode response → `wbtcSupplySats: bigint`

2. **EVM Read: Chainlink PoR Feed** (DON mode)
   - `evmClient.callContract(runtime, { ... })` with encoded `latestRoundData()` call
   - Target: `config.chainlinkPorFeed` on Ethereum mainnet
   - Decode response → `chainlinkReserveSats: bigint` (the `answer` field)

3. **HTTP: Blockstream BTC Reserves** (Node mode with identical consensus)
   - For each address in `config.btcCustodyAddresses`:
     - `httpClient.sendRequest(nodeRuntime, { url: blockstreamApiUrl/address/{addr} })`
   - Parse JSON → sum `(chain_stats.funded_txo_sum - chain_stats.spent_txo_sum)` across all addresses
   - Result: `btcReserveSats: bigint`

4. **HTTP: CoinGecko BTC/USD Price** (Node mode with identical consensus)
   - `httpClient.sendRequest(nodeRuntime, { url: coingeckoApiUrl?ids=bitcoin&vs_currencies=usd })`
   - Parse response → `btcUsdPriceCents: bigint` (price * 100)

5. **Compute collateral ratio:**
   ```
   collateralRatioBps = (btcReserveSats * 10000n) / wbtcSupplySats
   ```

6. **ABI-encode the payload:**
   ```typescript
   const callData = encodeFunctionData({
     abi: porContractAbi,
     functionName: 'updateReserve',
     args: [btcReserveSats, wbtcSupplySats, collateralRatioBps, btcUsdPriceCents, chainlinkReserveSats, timestamp]
   });
   ```

7. **Prepend prefix byte `0x01`** to the encoded calldata (for contract routing).

8. **Generate signed report:**
   ```typescript
   const report = runtime.report({
     encodedPayload: hexToBase64(prefixedCallData),
     ...
   }).result();
   ```

9. **Write report onchain:**
   ```typescript
   evmClient.writeReport(runtime, {
     receiver: config.evms[0].porContractAddress,
     report: report,
     gasConfig: { gasLimit: config.evms[0].gasLimit }
   }).result();
   ```

### 4.2 Key implementation notes

- EVM reads to mainnet contracts (WBTC, Chainlink feed) happen in DON mode — consensus is built-in.
- HTTP calls to Blockstream and CoinGecko happen in Node mode wrapped with `runtime.runInNodeMode(fn, consensusIdenticalAggregation)()`.
- The `.result()` pattern is mandatory for CRE SDK operations.
- Use `Map` instead of `Object` for any iteration to avoid non-determinism.
- WBTC uses 8 decimals (same as BTC satoshis), so `totalSupply()` returns satoshis directly.

---

## Phase 5: CRE Workflow — Handler 2 (Log → AI Anomaly Detection)

### 5.1 `my-workflow/logCallback.ts`

**Trigger:** EVM log — listens for `AuditRequested(uint256)` event on the PoR contract

**Logic flow:**

1. **Decode trigger event** — extract `auditId` from the log payload

2. **EVM Read: getLatestReserve()** (DON mode)
   - Read the current PoR data from our own contract on Sepolia
   - Decode → `ReserveData` struct values

3. **HTTP: Fresh Blockstream BTC balances** (Node mode)
   - Re-fetch BTC reserve balances (same as Handler 1 step 3)
   - Compare with the stored values for drift detection

4. **HTTP: Gemini LLM risk analysis** (Node mode via confidential HTTP)
   - Build prompt with reserve data, ratio, price, and any detected drift
   - POST to Gemini API with structured prompt
   - Parse response → `{ score: uint8 (0-100), recommendation: string }`

5. **ABI-encode the risk payload:**
   ```typescript
   const callData = encodeFunctionData({
     abi: porContractAbi,
     functionName: 'updateRisk',
     args: [score, recommendation, timestamp]
   });
   ```

6. **Prepend prefix byte `0x02`** and generate signed report

7. **Write report onchain** → `updateRisk` is called via `_processReport`

### 5.2 `my-workflow/gemini.ts`

Helper module (follows bootcamp pattern):

- `askGemini(runtime, config, question)` — retrieves `GEMINI_API_KEY` secret, builds request, calls Gemini API, parses JSON response
- System prompt instructs Gemini to analyze WBTC reserve data and return `{ "score": 0-100, "recommendation": "..." }`
- Uses `httpClient.sendRequest()` in node mode with identical consensus
- Treats the user question as untrusted (prompt injection guard)

---

## Phase 6: CRE Workflow — Handler 3 (HTTP → On-Demand Query)

### 6.1 `my-workflow/httpCallback.ts`

**Trigger:** HTTP request (API-triggered)

**Logic flow:**

1. Parse incoming HTTP payload (can be empty `{}` for default behavior)
2. Delegate to the same PoR computation logic as Handler 1
3. Write result onchain via the same report pattern
4. Return the transaction hash in the HTTP response

This handler reuses the core logic from `cronCallback.ts`. Extract shared computation into a helper function (e.g., `computePoR(runtime, config)`) that both Handler 1 and Handler 3 call.

---

## Phase 7: Workflow Entry Point (`main.ts`)

### 7.1 `my-workflow/main.ts`

```typescript
import { cre, Runner, getNetwork } from "@chainlink/cre-sdk";
import { keccak256, toHex } from "viem";
import { onCronTrigger } from "./cronCallback";
import { onLogTrigger } from "./logCallback";
import { onHttpTrigger } from "./httpCallback";

type Config = {
  geminiModel: string;
  evms: Array<{
    chainSelectorName: string;
    porContractAddress: string;
    gasLimit: string;
  }>;
  wbtcAddress: string;
  chainlinkPorFeed: string;
  cronSchedule: string;
  blockstreamApiUrl: string;
  coingeckoApiUrl: string;
  geminiApiUrl: string;
  btcCustodyAddresses: string[];
};

const AUDIT_REQUESTED_SIGNATURE = "AuditRequested(uint256)";

const initWorkflow = (config: Config) => {
  // Network setup
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: config.evms[0].chainSelectorName,
    isTestnet: true,
  });
  if (!network) throw new Error("Network not found");

  const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector);
  const httpCapability = new cre.capabilities.HTTPCapability();

  // Trigger 1: Cron
  const cronTrigger = new cre.capabilities.CronCapability().trigger({
    schedule: config.cronSchedule,
  });

  // Trigger 2: EVM Log (AuditRequested event)
  const eventHash = keccak256(toHex(AUDIT_REQUESTED_SIGNATURE));
  const logTrigger = evmClient.logTrigger({
    addresses: [config.evms[0].porContractAddress],
    topics: [{ values: [eventHash] }],
    confidence: "CONFIDENCE_LEVEL_FINALIZED",
  });

  // Trigger 3: HTTP
  const httpTrigger = httpCapability.trigger({});

  return [
    cre.handler(cronTrigger, onCronTrigger),
    cre.handler(logTrigger, onLogTrigger),
    cre.handler(httpTrigger, onHttpTrigger),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}

main();
```

---

## Phase 8: Simulation & Testing

### 8.1 Smart contract tests

```bash
cd contracts/
forge test -vvv
```

### 8.2 CRE workflow simulation

```bash
cd my-workflow/
bun install

# Handler 1: Cron trigger (PoR update)
cre workflow simulate my-workflow --broadcast
# → Select: cron-trigger

# Handler 2: Log trigger (AI audit)
# First emit the AuditRequested event:
cast send $POR_CONTRACT "requestAudit(uint256)" 1 \
  --rpc-url $RPC_URL --private-key $CRE_ETH_PRIVATE_KEY
# Then simulate:
cre workflow simulate my-workflow --broadcast
# → Select: evm-log-trigger, enter tx hash + event index 0

# Handler 3: HTTP trigger (on-demand query)
cre workflow simulate my-workflow --broadcast
# → Select: http-trigger, payload: {}
```

### 8.3 Verify onchain state

```bash
# Read latest reserve data
cast call $POR_CONTRACT "getLatestReserve()" --rpc-url $RPC_URL

# Check health
cast call $POR_CONTRACT "isHealthy()" --rpc-url $RPC_URL

# Read risk data
cast call $POR_CONTRACT "getLatestRisk()" --rpc-url $RPC_URL
```

---

## Phase 9: Frontend Dashboard (Optional / Post-Core)

React dashboard reading from the deployed contract:

- **ReserveGauge.jsx** — Circular gauge showing collateral ratio (green/yellow/red zones)
- **HistoryChart.jsx** — Timeline of `reserveHistory[]` snapshots
- **ComparisonPanel.jsx** — Side-by-side: ProofPulse computed vs Chainlink feed value
- **RiskPanel.jsx** — Latest AI risk score + recommendation + trigger audit button

Uses ethers.js or viem to call view functions on the deployed contract.

---

## Implementation Order

| Step | Task                                      | Depends On |
|------|-------------------------------------------|------------|
| 1    | Project scaffolding (dirs, configs)       | —          |
| 2    | IReceiver / ReceiverTemplate interfaces   | Step 1     |
| 3    | WBTCProofOfReserve.sol contract           | Step 2     |
| 4    | Contract unit tests                       | Step 3     |
| 5    | Deploy contract to Sepolia                | Step 4     |
| 6    | ABI definitions (`abi.ts`)                | Step 5     |
| 7    | CRE workflow package setup                | Step 1     |
| 8    | Handler 1 — Cron PoR update               | Steps 6, 7 |
| 9    | Handler 3 — HTTP on-demand (reuses H1)    | Step 8     |
| 10   | Gemini helper                             | Step 7     |
| 11   | Handler 2 — Log AI anomaly detection      | Steps 6, 10 |
| 12   | main.ts — register all 3 handlers         | Steps 8-11 |
| 13   | Simulate all handlers                     | Step 12    |
| 14   | Verify onchain state                      | Step 13    |
| 15   | Frontend dashboard (optional)             | Step 14    |

---

## Key Technical Decisions

1. **Report prefix routing** — Using `0x01` / `0x02` prefix bytes in `_processReport()` to route to `_updateReserve` / `_updateRisk` (same pattern as bootcamp's `0x01` for settlement).

2. **Mainnet reads from Sepolia workflow** — WBTC and Chainlink PoR feed are on Ethereum mainnet. CRE EVM reads can target mainnet contracts. The workflow deploys on Sepolia but reads cross-chain.

3. **Consensus strategy** — `consensusIdenticalAggregation` for HTTP calls (Blockstream, CoinGecko) to ensure all DON nodes see the same data. This is the standard approach for deterministic API responses.

4. **Non-determinism avoidance** — Use `Map` over `Object`, avoid `Promise.race`, use `.result()` pattern for all SDK operations, avoid `Date.now()` (use blockchain timestamps).

5. **Gemini via confidential HTTP** — API key retrieved via `runtime.getSecret()`, request sent through node-mode HTTP client with consensus.

---

## Risk & Mitigation

| Risk                                    | Mitigation                                         |
|-----------------------------------------|----------------------------------------------------|
| Blockstream API rate limiting           | Cache responses, use 60s cache settings in CRE     |
| CoinGecko free tier limits              | Fallback: use CoinGecko demo API key               |
| Gemini non-deterministic responses      | Force JSON-only output, validate structure          |
| Mainnet EVM reads from testnet workflow | Verify CRE supports cross-chain reads in simulation|
| Gas costs on Sepolia                    | Use faucet (faucets.chain.link)                    |
