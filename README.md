# ProofPulse — Cross-Chain WBTC Proof of Reserve with AI Risk Assessment

**A custom Proof of Reserve data feed for Wrapped Bitcoin (WBTC), built on [Chainlink CRE](https://docs.chain.link/cre), combining multi-source on-chain verification with AI-powered anomaly detection and a DeFi circuit breaker.**

ProofPulse monitors WBTC collateral health by independently verifying BTC reserves from the Bitcoin blockchain, comparing against both on-chain WBTC supply and the Chainlink PoR oracle feed, and using Google Gemini AI to detect anomalies — publishing verified results on-chain to Ethereum Sepolia. The **PulseGuard** vault contract consumes this data to automatically protect DeFi users by blocking deposits when reserves are unhealthy.

## Why ProofPulse?

WBTC holds billions in value as the leading wrapped BTC on Ethereum, yet verifying its reserves requires trusting a single custodian's attestation. ProofPulse provides:

- **Independent verification** — reads BTC custody balances directly from Bitcoin via Blockstream, not from the custodian
- **Cross-source validation** — compares independent data against the Chainlink PoR feed, alerting on >5% divergence
- **AI anomaly detection** — uses Gemini AI to analyze reserve patterns and flag risks that rule-based systems miss
- **On-chain transparency** — all results are stored on-chain with full history, queryable by any DeFi protocol
- **DeFi circuit breaker** — PulseGuard automatically pauses deposits when reserves are unhealthy, protecting users in real time
- **Three trigger modes** — automated hourly updates, on-demand HTTP requests, and event-driven AI audits

## Live Deployment (Sepolia)

| Contract | Address | Etherscan |
|----------|---------|-----------|
| **WBTCProofOfReserve** | `0x4177bF2196151A05A51f7928988afd3Fe7B6e949` | [View](https://sepolia.etherscan.io/address/0x4177bF2196151A05A51f7928988afd3Fe7B6e949) |
| **PulseGuard** | `0x887dC9BF62755dCbb0A3d93028fCAd741585106E` | [View](https://sepolia.etherscan.io/address/0x887dC9BF62755dCbb0A3d93028fCAd741585106E) |

The frontend dashboard is a React + Vite app in [`frontend/`](frontend/). Run `cd frontend && npm install && npm run dev` to start it locally, then connect MetaMask to Sepolia to interact with the live contracts.

## Tenderly Virtual TestNet

ProofPulse supports deployment to a [Tenderly Virtual TestNet](https://docs.tenderly.co/virtual-testnets) — a fork of Sepolia with a built-in block explorer, contract verification, and unlimited faucet. This is ideal for testing the full CRE workflow end-to-end without spending real testnet ETH.

### Prerequisites

- **Tenderly Access Key** — Sign up at [dashboard.tenderly.co/register](https://dashboard.tenderly.co/register), then go to **Settings → Authorization → Generate Access Token**
- Add to `.env`: `TENDERLY_ACCESS_KEY=your_token_here`

### Quick Start

```bash
# 1. Create VNet, fund wallet, deploy + verify contracts
./setup-tenderly.sh

# 2. Load the Tenderly environment (RPC, contract addresses)
source .env.tenderly

# 3. Run the full 3-handler CRE workflow against Tenderly
./simulate-workflow.sh --broadcast
```

The setup script will print a **Tenderly Explorer link** where you can view all transactions and verified contract source code.

### How It Works

- **Reads** (WBTC `totalSupply()`, Chainlink feed, Blockstream, CoinGecko) → **real Ethereum Mainnet** (unchanged)
- **Writes** (reserve reports, risk assessments) → **Tenderly VNet** (forked Sepolia)

When you `source .env.tenderly`, the `simulate-workflow.sh` script automatically uses the Tenderly RPC and contract addresses instead of Sepolia defaults. To also update `project.yaml`, `config.staging.json`, and the frontend config, run:

```bash
./setup-tenderly.sh --update-configs
```

This creates `.bak` backups of all modified files.

### Deep Tenderly Integrations

#### Transaction Simulator (Frontend)

The dashboard includes a **Tenderly VNet Transaction Simulator** — a purple-themed card that previews any PulseGuard transaction before executing it on-chain. Select Deposit / Withdraw / Check Health, and the simulator runs a full EVM `eth_call` against the Tenderly VNet to show:

- Whether the transaction would **succeed or revert**
- **Decoded revert reasons** (e.g., `ReservesUnhealthy`, `CircuitBreakerIsActive`)
- **Gas estimates** for successful transactions
- **Live contract state** (depositsAllowed, isHealthy, collateral ratio, risk score, vault total)

This demonstrates why Tenderly VNets are superior to regular testnets: full EVM simulation with zero gas cost and no state changes.

#### Edge Case Testing with State Overrides

```bash
./test-edge-cases.sh
```

Uses `eth_call` state overrides (a Tenderly VNet capability) to test scenarios that are **impossible on regular Sepolia**:

| Scenario | Override | Result |
|----------|----------|--------|
| **Undercollateralization** | `collateralRatioBps → 5000 (50%)` | `isHealthy()=false`, deposits blocked, deposit() reverts |
| **AI Risk Spike** | `latestRisk.score → 95` | `checkHealth()` would trip circuit breaker |
| **Combined Stress** | Both overrides simultaneously | Multi-layer protection validated |
| **State Verification** | None | Confirms actual VNet state is unchanged |

No mock contracts needed. No state mutations. The script directly overrides storage slots in `eth_call` to validate PulseGuard's circuit breaker protection against compound failures — then proves the real state was never touched.

## Architecture

```
┌────────────────────────── CRE Workflow (WASM, DON Consensus) ──────────────────────────┐
│                                                                                         │
│  Handler 1: Cron (hourly)          Handler 2: Log (audit)        Handler 3: HTTP        │
│  ┌──────────────────────┐          ┌──────────────────────┐      ┌──────────────────┐   │
│  │ Blockstream API ─┐   │          │ Fresh HTTP data ─┐   │      │ Same as Handler 1│   │
│  │ CoinGecko API  ──┤   │          │ On-chain reserve ─┤  │      │ (on-demand)      │   │
│  │ WBTC supply    ──┤   │          │ Gemini AI ────────┤  │      └──────────────────┘   │
│  │ Chainlink feed ──┘   │          │ Risk score (0-100)┘  │                              │
│  │ → Collateral ratio   │          │ → Risk assessment    │                              │
│  │ → 0x01 report        │          │ → 0x02 report        │                              │
│  └──────────┬───────────┘          └──────────┬───────────┘                              │
│             │                                  │                                         │
└─────────────┼──────────────────────────────────┼─────────────────────────────────────────┘
              │                                  │
              ▼                                  ▼
   ┌──────────────────────────────────────────────────────────┐
   │              WBTCProofOfReserve.sol (Sepolia)            │
   │                                                          │
   │  0x01 → _updateReserve()   0x02 → _updateRisk()         │
   │  • Store reserve snapshot   • Store AI risk score        │
   │  • Check <100% collateral   • Store recommendation       │
   │  • Check >5% CL divergence  • Emit RiskUpdated           │
   │  • Emit alerts if needed                                 │
   │                                                          │
   │  Views: isHealthy() | getLatestReserve() | getLatestRisk │
   │  Action: requestAudit() → emits AuditRequested event     │
   └──────────────────────┬───────────────────────────────────┘
                          │ reads
                          ▼
   ┌──────────────────────────────────────────────────────────┐
   │                PulseGuard.sol (Sepolia)                  │
   │            DeFi Circuit Breaker Vault                    │
   │                                                          │
   │  deposit()  → checks isHealthy() + circuit breaker       │
   │  withdraw() → always allowed (user safety first)         │
   │  checkHealth() → trips breaker on unhealthy/high risk    │
   │                                                          │
   │  Automatically protects DeFi users from reserve issues   │
   └──────────────────────────────────────────────────────────┘
```

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Three trigger types** | Cron for baseline monitoring, Log for user-initiated AI audits, HTTP for integrations |
| **5% divergence threshold** | Balances sensitivity vs noise — accounts for timing differences between data sources |
| **99% health threshold** | 1% buffer for BTC block confirmation lag vs WBTC mint/burn settlement timing |
| **Gemini AI for risk** | Complements rule-based checks with pattern recognition across multiple data dimensions |
| **Prefix-byte routing** | Single contract entry point with extensible report types (0x01 reserve, 0x02 risk) |
| **Blockstream as BTC source** | Public, non-custodian data source — independent verification, not attestation |
| **Withdrawals always allowed** | User safety first — PulseGuard never locks funds, only blocks new deposits |

## Chainlink Integration

### Files Using Chainlink

| File | Chainlink Usage |
|------|----------------|
| [`my-workflow/main.ts`](my-workflow/main.ts) | CRE SDK workflow — `CronCapability`, `EVMClient`, `HTTPClient`, `ConsensusAggregationByFields`, `Runner`, DON consensus for EVM reads, signed report generation via `runtime.report()` |
| [`my-workflow/gemini.ts`](my-workflow/gemini.ts) | CRE SDK HTTP consensus — `HTTPClient.sendRequest()` with `ConsensusAggregationByFields` for Gemini AI calls |
| [`contracts/src/WBTCProofOfReserve.sol`](contracts/src/WBTCProofOfReserve.sol) | CRE Receiver contract — extends `ReceiverTemplate` (Chainlink KeystoneForwarder access control) |
| [`contracts/src/PulseGuard.sol`](contracts/src/PulseGuard.sol) | DeFi consumer of PoR data — reads `isHealthy()` and `getLatestRisk()` to gate vault operations |
| [`contracts/src/interfaces/ReceiverTemplate.sol`](contracts/src/interfaces/ReceiverTemplate.sol) | Chainlink CRE interface — `IReceiver` implementation with forwarder authentication |
| [`contracts/src/interfaces/IReceiver.sol`](contracts/src/interfaces/IReceiver.sol) | Chainlink CRE interface — `onReport()` standard |
| [`contracts/abi/AggregatorV3.ts`](contracts/abi/AggregatorV3.ts) | Chainlink AggregatorV3 ABI — used to read `latestRoundData()` from the BTC reserve price feed |
| [`contracts/abi/WBTCProofOfReserve.ts`](contracts/abi/WBTCProofOfReserve.ts) | ABI for the CRE Receiver contract |
| [`my-workflow/workflow.yaml`](my-workflow/workflow.yaml) | CRE workflow configuration (staging/production targets) |
| [`project.yaml`](project.yaml) | CRE project configuration (RPC endpoints, chain selectors) |
| [`secrets.yaml`](secrets.yaml) | CRE secrets configuration |

### CRE Capabilities Used

- **CronCapability** — Hourly scheduled PoR verification
- **EVMClient.callContract()** — Read WBTC `totalSupply()` and Chainlink `latestRoundData()` with DON consensus
- **EVMClient.logTrigger()** — Listen for `AuditRequested` events on Sepolia
- **EVMClient.writeReport()** — Submit signed reports to the Receiver contract
- **HTTPClient.sendRequest()** — Fetch BTC reserves and price with node consensus aggregation
- **HTTPCapability** — On-demand HTTP trigger for ad-hoc PoR checks
- **runtime.report()** — Generate signed EVM reports (ECDSA + keccak256)
- **ConsensusAggregationByFields** — Median aggregation for numeric data, identical match for strings

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Bun** | 1.3+ | [bun.sh](https://bun.sh) |
| **Foundry** (forge, cast) | Latest | [getfoundry.sh](https://getfoundry.sh) |
| **CRE CLI** | 1.0.9+ | [CRE CLI releases](https://github.com/smartcontractkit/cre-cli/releases) |
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org) (for the frontend) |

## Setup

### 1. Clone and install

```bash
git clone <repo-url> && cd proofofpulse

# Install CRE workflow dependencies
cd my-workflow && bun install && cd ..

# Install frontend dependencies
cd frontend && npm install && cd ..
```

### 2. Environment variables

```bash
cp .env.example .env
```

Edit `.env` with your keys:

```env
# Required: Ethereum private key (funded on Sepolia for broadcast mode)
CRE_ETH_PRIVATE_KEY=your_private_key_here

# Required for AI risk assessment (Handler 2)
GEMINI_API_KEY_VAR=your_gemini_api_key_here
```

Get a free Gemini API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).

### 3. RPC endpoints

Public defaults are included in `project.yaml`. To use custom RPCs, edit:

```yaml
staging-settings:
  rpcs:
    - chain-name: ethereum-testnet-sepolia
      url: https://ethereum-sepolia-rpc.publicnode.com
    - chain-name: ethereum-mainnet
      url: https://ethereum-rpc.publicnode.com
```

## Running the Project

### Smart Contract Tests

```bash
# Run all 62 tests (PoR: 29 tests, PulseGuard: 33 tests)
forge test -vvv --root contracts

# Run only PoR tests
forge test -vvv --root contracts --match-contract WBTCProofOfReserveTest

# Run only PulseGuard tests
forge test -vvv --root contracts --match-contract PulseGuardTest

# Run a specific test
forge test -vvv --root contracts --match-test test_fullScenario_healthyToUnhealthyAndBack
```

### CRE Workflow Simulations

All simulation commands run from the **project root**. Each simulates the full CRE workflow pipeline: data fetch → DON consensus → signed report generation → on-chain delivery.

---

#### Handler 1 — Cron Trigger (Hourly PoR Update)

Fetches live BTC reserves from Blockstream, BTC/USD price from CoinGecko, WBTC `totalSupply()` from Ethereum mainnet, and Chainlink `latestRoundData()` — then computes the collateral ratio and generates a signed 0x01 report.

```bash
echo "1" | cre workflow simulate my-workflow
```

**Expected output:**

```
[SIMULATION] Running trigger trigger=cron-trigger@1.0.0
[USER LOG] Running CronTrigger — hourly PoR update
[USER LOG] Fetching BTC reserves and price...
[USER LOG] BTC reserves: 6820000677083 sats, price: 6875000 cents
[USER LOG] WBTC supply: 12119565562622
[USER LOG] Chainlink reserve: 15313507536303
[USER LOG] Collateral ratio: 5627 bps
[USER LOG] Report written: 0x000...

Workflow Simulation Result:
 "PoR updated: ratio=5627bps"
```

---

#### Handler 2 — Log Trigger (AI Risk Assessment with Gemini)

This trigger listens for `AuditRequested` events on Sepolia. It fetches fresh reserve data, sends it to Google Gemini AI for analysis, and writes a signed 0x02 risk report.

**Step 1: Emit an `AuditRequested` event on Sepolia**

```bash
source .env
cast send 0x4177bF2196151A05A51f7928988afd3Fe7B6e949 \
  "requestAudit(uint256)" 1 \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --private-key $CRE_ETH_PRIVATE_KEY
```

Copy the transaction hash from the output (e.g. `transactionHash  0xabc123...`).

**Step 2: Simulate the CRE Log Trigger with that transaction**

```bash
expect -c '
spawn cre workflow simulate my-workflow
expect "Enter your choice"
send "2\r"
expect "Enter transaction hash"
send "0x<PASTE_YOUR_TX_HASH_HERE>\r"
expect "Enter event index"
send "0\r"
expect eof
'
```

**Expected output:**

```
[SIMULATION] Running trigger trigger=evm:ChainSelector:...LogTrigger
[USER LOG] Running LogTrigger — AI risk assessment
[USER LOG] Fetching fresh reserve data for AI analysis...
[USER LOG] Calling Gemini AI for risk assessment...
[USER LOG] Gemini risk score: 25, recommendation: "Reserves appear adequate..."
[USER LOG] Risk report written

Workflow Simulation Result:
 "Risk assessed: score=25"
```

> **Note:** If Gemini returns 429 (rate limited), the workflow gracefully falls back to score=0 with a clear error message. This is intentional — the fallback is safe (score=0 means no risk detected).

---

#### Handler 3 — HTTP Trigger (On-Demand PoR Check)

Same logic as Handler 1 but triggered on-demand via HTTP. Useful for integrations that need a fresh PoR check outside the hourly cron schedule.

```bash
expect -c '
spawn cre workflow simulate my-workflow
expect "Enter your choice"
send "3\r"
expect "Enter your input"
send "{}\r"
expect eof
'
```

**Expected output:** Same as Handler 1 — fetches live data, computes ratio, generates signed report.

---

### Broadcast Mode (Live On-Chain Writes)

In broadcast mode, the CRE simulation actually submits the signed report to the deployed contract on Sepolia. This writes real data on-chain.

```bash
# Broadcast a cron trigger (writes reserve data to Sepolia)
echo "1" | cre workflow simulate my-workflow --broadcast
```

After broadcast, verify the on-chain data:

```bash
# Read the latest reserve from the deployed contract
cast call 0x4177bF2196151A05A51f7928988afd3Fe7B6e949 \
  "getLatestReserve()" \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Check if reserves are healthy
cast call 0x4177bF2196151A05A51f7928988afd3Fe7B6e949 \
  "isHealthy()" \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Check the reserve history length
cast call 0x4177bF2196151A05A51f7928988afd3Fe7B6e949 \
  "getReserveHistoryLength()" \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Check if PulseGuard allows deposits
cast call 0x887dC9BF62755dCbb0A3d93028fCAd741585106E \
  "depositsAllowed()" \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Get full vault status
cast call 0x887dC9BF62755dCbb0A3d93028fCAd741585106E \
  "getVaultStatus()" \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

### Frontend Dashboard

```bash
cd frontend
npm install
npm run dev
```

Open `http://localhost:5173` in a browser. Connect MetaMask to Sepolia to interact with the live contracts.

**Dashboard features:**
- **Reserve Health** — Collateral ratio with progress bar, BTC reserves vs WBTC supply, Chainlink comparison, health badge
- **AI Risk Assessment** — Gemini risk score meter (0-100), recommendation text, Request AI Audit button
- **PulseGuard Vault** — Deposit/withdraw, circuit breaker status, blocked deposit explanation, wallet balance
- **Tenderly Transaction Simulator** — Preview deposit/withdraw/health-check outcomes via `eth_call` on the VNet before executing
- **Reserve History Chart** — Time-series visualization of collateral ratio, reserves, and BTC price from on-chain history (3 views: ratio, reserves comparison, price)
- **Contract Data Explorer** — Raw values from all 8+ contract calls, expandable
- **Live Activity Log** — Real-time feed of all actions and data refreshes

To build for production: `npm run build` (outputs to `frontend/dist/`).

### Deploying Contracts

The PoR contract and PulseGuard are already deployed on Sepolia. To redeploy:

```bash
source .env

# Deploy WBTCProofOfReserve (replace FORWARDER with CRE KeystoneForwarder address)
forge create --private-key "$CRE_ETH_PRIVATE_KEY" \
  --rpc-url "https://ethereum-sepolia-rpc.publicnode.com" \
  --broadcast \
  src/WBTCProofOfReserve.sol:WBTCProofOfReserve \
  --constructor-args "FORWARDER_ADDRESS"

# Deploy PulseGuard (with PoR address and risk threshold 70)
forge create --private-key "$CRE_ETH_PRIVATE_KEY" \
  --rpc-url "https://ethereum-sepolia-rpc.publicnode.com" \
  --broadcast \
  src/PulseGuard.sol:PulseGuard \
  --constructor-args "POR_ADDRESS" "70"
```

### Interacting with Deployed Contracts (cast)

```bash
source .env
RPC="https://ethereum-sepolia-rpc.publicnode.com"
POR="0x4177bF2196151A05A51f7928988afd3Fe7B6e949"
GUARD="0x887dC9BF62755dCbb0A3d93028fCAd741585106E"

# Request an AI audit (emits AuditRequested event for CRE Log Trigger)
cast send $POR "requestAudit(uint256)" 42 --rpc-url $RPC --private-key $CRE_ETH_PRIVATE_KEY

# Try depositing into PulseGuard (will revert if reserves are unhealthy)
cast send $GUARD "deposit()" --value 0.001ether --rpc-url $RPC --private-key $CRE_ETH_PRIVATE_KEY

# Trigger a health check on PulseGuard (trips circuit breaker if unhealthy)
cast send $GUARD "checkHealth()" --rpc-url $RPC --private-key $CRE_ETH_PRIVATE_KEY

# Withdraw from PulseGuard (always succeeds — user safety first)
cast send $GUARD "withdraw(uint256)" 1000000000000000 --rpc-url $RPC --private-key $CRE_ETH_PRIVATE_KEY
```

## Project Structure

```
proofofpulse/
├── contracts/                          # Foundry smart contract project
│   ├── src/
│   │   ├── WBTCProofOfReserve.sol      # CRE Receiver: reserve + risk storage, alerts
│   │   ├── PulseGuard.sol              # DeFi circuit breaker vault consuming PoR data
│   │   └── interfaces/
│   │       ├── IReceiver.sol           # Chainlink CRE standard interface
│   │       └── ReceiverTemplate.sol    # Forwarder-only access control base
│   ├── test/
│   │   ├── WBTCProofOfReserve.t.sol    # 29 tests (boundaries, overflow, edge cases)
│   │   └── PulseGuard.t.sol            # 33 tests (deposits, withdrawals, circuit breaker)
│   ├── abi/                            # TypeScript ABI exports for workflow
│   └── foundry.toml
├── my-workflow/                        # CRE TypeScript workflow
│   ├── main.ts                         # Three trigger handlers (cron, log, http)
│   ├── gemini.ts                       # Gemini AI integration with consensus
│   ├── workflow.yaml                   # CRE workflow targets
│   ├── config.staging.json             # Staging config
│   └── config.production.json          # Production config
├── frontend/                           # React + Vite + TypeScript dashboard
│   ├── src/
│   │   ├── App.tsx                     # Main app layout
│   │   ├── hooks/
│   │   │   ├── useContracts.ts         # All contract reads, writes, wallet connection
│   │   │   └── useSimulation.ts        # Tenderly VNet transaction simulation logic
│   │   ├── components/
│   │   │   ├── ReserveCard.tsx         # Collateral ratio, BTC data, health badge
│   │   │   ├── RiskCard.tsx            # AI risk score meter, recommendation
│   │   │   ├── VaultCard.tsx           # PulseGuard vault, deposits, circuit breaker
│   │   │   ├── TenderlySimulator.tsx   # Tenderly VNet transaction simulator
│   │   │   ├── HistoryChart.tsx        # Time-series chart (recharts) from on-chain data
│   │   │   ├── ContractExplorer.tsx    # Raw contract call values display
│   │   │   └── ActivityLog.tsx         # Live activity feed
│   │   ├── config/contracts.ts         # ABIs and deployed addresses
│   │   └── utils.ts                    # BTC/USD formatters
│   └── package.json
├── simulate-workflow.sh                # Full 3-handler CRE simulation (auto-detects Tenderly)
├── setup-tenderly.sh                   # Automated Tenderly VNet setup + deploy
├── test-edge-cases.sh                  # Tenderly state override edge case testing
├── project.yaml                        # CRE project config (RPCs)
├── secrets.yaml                        # CRE secret references
├── .env.example                        # Environment variable template
└── CLAUDE.md                           # Development guide
```

## Data Sources

| Source | Data | Access Method | Consensus |
|--------|------|---------------|-----------|
| **Blockstream API** | BTC custody address balances | HTTP (node mode) | Median aggregation |
| **CoinGecko API** | BTC/USD price | HTTP (node mode) | Median aggregation |
| **Ethereum Mainnet** | WBTC `totalSupply()` | EVM read (DON mode) | Built-in DON consensus |
| **Chainlink PoR Feed** | BTC reserve `latestRoundData()` | EVM read (DON mode) | Built-in DON consensus |
| **Google Gemini AI** | Risk score + recommendation | HTTP (node mode) | Median (score) + identical (text) |

## On-Chain Alerts

The smart contract automatically emits alerts:

- **`UndercollateralizedAlert`** — When collateral ratio drops below 100% (BTC reserves < WBTC supply)
- **`ChainlinkDivergenceAlert`** — When independently-verified BTC reserves diverge from Chainlink's feed by >5%
- **`RiskUpdated`** — When Gemini AI completes a risk assessment (score 0=safe, 100=critical)
- **`CircuitBreakerTriggered`** — When PulseGuard auto-pauses deposits due to unhealthy reserves or high AI risk

DeFi protocols can subscribe to these events to automatically pause lending, adjust LTVs, or trigger liquidation safeguards.

## Rate Limits

- **CoinGecko free tier**: ~10 requests/minute. Space out trigger simulations.
- **Gemini free tier**: Limited RPM. The workflow gracefully handles 429 errors with a safe fallback (score=0, "API unavailable").

## License

MIT
