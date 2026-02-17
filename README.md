<div align="center">

<img src="https://img.shields.io/badge/Chainlink-CRE-375BD2?style=for-the-badge&logo=chainlink&logoColor=white" alt="Chainlink CRE" />
<img src="https://img.shields.io/badge/Tenderly-VNet-7B3FE4?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSIxMCIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&logoColor=white" alt="Tenderly VNet" />
<img src="https://img.shields.io/badge/Gemini_AI-Risk_Engine-4285F4?style=for-the-badge&logo=google&logoColor=white" alt="Gemini AI" />
<img src="https://img.shields.io/badge/Solidity-0.8.24-363636?style=for-the-badge&logo=solidity&logoColor=white" alt="Solidity" />
<img src="https://img.shields.io/badge/Tests-62%20Passing-2ea44f?style=for-the-badge" alt="62 Tests Passing" />

<br /><br />

# ProofPulse

**Cross-Chain WBTC Proof of Reserve · AI Risk Assessment · DeFi Circuit Breaker**

A production-grade Proof of Reserve verification system for Wrapped Bitcoin, built on Chainlink's Compute Runtime Environment. ProofPulse independently verifies BTC reserves from the Bitcoin blockchain, cross-validates against on-chain WBTC supply and the Chainlink PoR oracle feed, runs AI-powered anomaly detection via Google Gemini, and publishes verified results on-chain — where the PulseGuard vault automatically protects DeFi users by blocking deposits when reserves are unhealthy.

<br />

[**Live Demo**](https://proof-of-pulse.ibxlab.com/) · [**Video Demo**](https://youtu.be/-WxFKCXXVgE) · [**CRE Integration PR**](https://github.com/aliveevie/proof-of-pulse/pull/1) · [**Tenderly Integration PR**](https://github.com/aliveevie/proof-of-pulse/pull/2)

<br />

<a href="https://youtu.be/-WxFKCXXVgE">
  <img src="https://img.shields.io/badge/▶_Watch_Demo-YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="Watch Demo on YouTube" />
</a>
&nbsp;
<a href="https://proof-of-pulse.ibxlab.com/">
  <img src="https://img.shields.io/badge/🌐_Live_Dashboard-proof--of--pulse.ibxlab.com-0070f3?style=for-the-badge" alt="Live Dashboard" />
</a>

</div>

<br />

---

## Overview

WBTC holds billions in value as the leading wrapped BTC on Ethereum, yet verifying its reserves requires trusting a single custodian's attestation. ProofPulse changes that:

- **Independent verification** — reads BTC custody balances directly from Bitcoin via Blockstream, not from the custodian
- **Cross-source validation** — compares independent data against the Chainlink PoR feed, alerting on >5% divergence
- **AI anomaly detection** — uses Gemini AI to analyze reserve patterns and flag risks that rule-based systems miss
- **On-chain transparency** — all results are stored on-chain with full history, queryable by any DeFi protocol
- **DeFi circuit breaker** — PulseGuard automatically pauses deposits when reserves are unhealthy, protecting users in real time
- **Three trigger modes** — automated hourly updates, on-demand HTTP requests, and event-driven AI audits

---

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

---

## Deployed Contracts (Sepolia)

| Contract | Address | Explorer |
|----------|---------|----------|
| **WBTCProofOfReserve** | `0x4177bF2196151A05A51f7928988afd3Fe7B6e949` | [Etherscan](https://sepolia.etherscan.io/address/0x4177bF2196151A05A51f7928988afd3Fe7B6e949) |
| **PulseGuard** | `0x887dC9BF62755dCbb0A3d93028fCAd741585106E` | [Etherscan](https://sepolia.etherscan.io/address/0x887dC9BF62755dCbb0A3d93028fCAd741585106E) |

**Tenderly VNet Deployments:**

| Contract | Address |
|----------|---------|
| **WBTCProofOfReserve** | `0x3C4f266542EEE824303F39189CdeBF9530FEFd73` |
| **PulseGuard** | `0x97999Af8E10B03A5f8eC8bC8ADFF7B0679b6EA11` |

---

## Quick Start

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Bun** | 1.3+ | [bun.sh](https://bun.sh) |
| **Foundry** (forge, cast) | Latest | [getfoundry.sh](https://getfoundry.sh) |
| **CRE CLI** | 1.0.9+ | [CRE CLI releases](https://github.com/smartcontractkit/cre-cli/releases) |
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org) |

### 1. Clone & Install

```bash
git clone https://github.com/aliveevie/proof-of-pulse.git && cd proof-of-pulse

# CRE workflow dependencies
cd my-workflow && bun install && cd ..

# Frontend dependencies
cd frontend && npm install && cd ..
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
# Required — Ethereum private key (funded on Sepolia for broadcast mode)
CRE_ETH_PRIVATE_KEY=your_private_key_here

# Required for AI risk assessment (Handler 2)
GEMINI_API_KEY_VAR=your_gemini_api_key_here
```

> Get a free Gemini API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey)

### 3. Run the Full Simulation

The simulation script runs all three CRE handlers end-to-end — preflight checks, live data fetching, DON consensus simulation, and on-chain verification:

```bash
# Simulation only (no on-chain writes)
./simulate-workflow.sh

# With broadcast (writes to Sepolia)
./simulate-workflow.sh --broadcast
```

<details>
<summary><strong>What the simulation does step by step</strong></summary>

1. **Preflight checks** — validates `.env`, verifies CLI tools (`cre`, `cast`, `bun`, `expect`), pings deployed contracts, tests Gemini API key
2. **Reads current on-chain state** — reserve snapshot count, deposit status, PulseGuard health
3. **Handler 1 (Cron)** — fetches BTC reserves from Blockstream, price from CoinGecko, WBTC supply from Ethereum, Chainlink PoR feed → computes collateral ratio → signs `0x01` report
4. **Handler 2 (Log)** — emits `AuditRequested` event on-chain, CRE log trigger picks it up, fetches fresh data, calls Gemini AI for risk score → signs `0x02` report
5. **Handler 3 (HTTP)** — same as Handler 1 but via HTTP trigger for external integrations
6. **On-chain verification** — reads back contract state to confirm `isHealthy()`, `depositsAllowed()`, and `riskThreshold()`

</details>

### 4. Run Smart Contract Tests

```bash
# All 62 tests (29 PoR + 33 PulseGuard)
forge test -vvv --root contracts
```

### 5. Launch the Frontend

```bash
cd frontend && npm run dev
```

Open `http://localhost:5173` and connect MetaMask to Sepolia.

---

## Tenderly Virtual TestNet

ProofPulse supports deployment to a [Tenderly Virtual TestNet](https://docs.tenderly.co/virtual-testnets) — a fork of Sepolia with a built-in block explorer, contract verification, and unlimited faucet.

```bash
# 1. Create VNet, fund wallet, deploy + verify contracts
./setup-tenderly.sh

# 2. Load the Tenderly environment
source .env.tenderly

# 3. Run the full 3-handler CRE workflow against Tenderly
./simulate-workflow.sh --broadcast

# 4. Test edge cases with state overrides
./test-edge-cases.sh
```

### Transaction Simulator

The frontend includes a **Tenderly VNet Transaction Simulator** — preview any PulseGuard transaction before executing on-chain. Select Deposit / Withdraw / Check Health and see:

- Whether the transaction would **succeed or revert**
- **Decoded revert reasons** (e.g., `ReservesUnhealthy`, `CircuitBreakerIsActive`)
- **Gas estimates** for successful transactions
- **Live contract state** (depositsAllowed, isHealthy, collateral ratio, risk score)

### Edge Case Testing with State Overrides

`./test-edge-cases.sh` uses `eth_call` state overrides to test scenarios impossible on regular Sepolia:

| Scenario | Override | Result |
|----------|----------|--------|
| **Undercollateralization** | `collateralRatioBps → 5000 (50%)` | `isHealthy()=false`, deposits blocked |
| **AI Risk Spike** | `latestRisk.score → 95` | Circuit breaker would trip |
| **Combined Stress** | Both overrides simultaneously | Multi-layer protection validated |
| **Verification** | None | Confirms actual state unchanged |

---

## Data Sources

| Source | Data | Consensus |
|--------|------|-----------|
| **Blockstream API** | BTC custody address balances | Median aggregation |
| **CoinGecko API** | BTC/USD price | Median aggregation |
| **Ethereum Mainnet** | WBTC `totalSupply()` | DON consensus |
| **Chainlink PoR Feed** | BTC reserve `latestRoundData()` | DON consensus |
| **Google Gemini AI** | Risk score (0–100) + recommendation | Median (score) + identical (text) |

---

## Chainlink CRE Integration

### CRE Capabilities Used

| Capability | Usage |
|-----------|-------|
| **CronCapability** | Hourly scheduled PoR verification |
| **EVMClient.callContract()** | Read WBTC `totalSupply()` and Chainlink `latestRoundData()` with DON consensus |
| **EVMClient.logTrigger()** | Listen for `AuditRequested` events on Sepolia |
| **EVMClient.writeReport()** | Submit signed reports to the Receiver contract |
| **HTTPClient.sendRequest()** | Fetch BTC reserves and price with node consensus aggregation |
| **HTTPCapability** | On-demand HTTP trigger for ad-hoc PoR checks |
| **runtime.report()** | Generate signed EVM reports (ECDSA + keccak256) |
| **ConsensusAggregationByFields** | Median aggregation for numeric data, identical match for strings |

### Files Using Chainlink

| File | Usage |
|------|-------|
| [`my-workflow/main.ts`](my-workflow/main.ts) | CRE SDK workflow — 3 trigger handlers, DON consensus EVM reads, signed report generation |
| [`my-workflow/gemini.ts`](my-workflow/gemini.ts) | CRE HTTPClient with ConsensusAggregationByFields for Gemini AI calls |
| [`contracts/src/WBTCProofOfReserve.sol`](contracts/src/WBTCProofOfReserve.sol) | CRE Receiver — extends `ReceiverTemplate` (KeystoneForwarder access control) |
| [`contracts/src/PulseGuard.sol`](contracts/src/PulseGuard.sol) | DeFi consumer — reads `isHealthy()` and `getLatestRisk()` to gate vault operations |
| [`contracts/src/interfaces/ReceiverTemplate.sol`](contracts/src/interfaces/ReceiverTemplate.sol) | Chainlink CRE `IReceiver` with forwarder authentication |
| [`contracts/abi/AggregatorV3.ts`](contracts/abi/AggregatorV3.ts) | Chainlink AggregatorV3 ABI for `latestRoundData()` |

---

## On-Chain Alerts

| Event | Trigger |
|-------|---------|
| **`UndercollateralizedAlert`** | Collateral ratio drops below 100% |
| **`ChainlinkDivergenceAlert`** | Blockstream vs Chainlink reserves diverge >5% |
| **`RiskUpdated`** | Gemini AI completes risk assessment |
| **`CircuitBreakerTriggered`** | PulseGuard auto-pauses deposits |

---

## End-to-End CRE Integration

<table>
<tr>
<td>

### [PR #1 — Full CRE Workflow Implementation](https://github.com/aliveevie/proof-of-pulse/pull/1)

Complete implementation of the 3-handler CRE workflow, Solidity contracts, React dashboard, and simulation infrastructure.

**Core CRE Workflow:**
| File | What it does |
|------|-------------|
| `my-workflow/main.ts` | 3 trigger handlers — Cron, Log, HTTP — with DON consensus and signed report generation |
| `my-workflow/gemini.ts` | Gemini AI integration with CRE HTTP consensus aggregation |
| `my-workflow/workflow.yaml` | CRE workflow targets configuration |
| `my-workflow/config.staging.json` | Runtime config — contract addresses, API URLs, chain selectors |
| `project.yaml` | CRE project config with RPC endpoints |
| `secrets.yaml` | CRE secret references |

**Smart Contracts (62 tests):**
| File | What it does |
|------|-------------|
| `contracts/src/WBTCProofOfReserve.sol` | CRE Receiver — prefix-byte routing, reserve + risk storage, health checks, alerts |
| `contracts/src/PulseGuard.sol` | Circuit breaker vault — gates deposits on `isHealthy()` and AI risk score |
| `contracts/src/interfaces/ReceiverTemplate.sol` | Chainlink KeystoneForwarder access control base |
| `contracts/test/WBTCProofOfReserve.t.sol` | 29 tests — boundaries, overflow, edge cases |
| `contracts/test/PulseGuard.t.sol` | 33 tests — deposits, withdrawals, circuit breaker |

**Frontend Dashboard:**
| File | What it does |
|------|-------------|
| `frontend/src/hooks/useContracts.ts` | All contract reads/writes, wallet connection, 30s auto-refresh |
| `frontend/src/components/ReserveCard.tsx` | Collateral ratio, BTC data, health badge |
| `frontend/src/components/RiskCard.tsx` | AI risk score meter, recommendation |
| `frontend/src/components/VaultCard.tsx` | PulseGuard vault, deposits, circuit breaker |
| `frontend/src/components/HistoryChart.tsx` | Time-series charts from on-chain history (Recharts) |
| `frontend/src/components/ContractExplorer.tsx` | Raw contract call viewer |
| `frontend/src/components/ActivityLog.tsx` | Live activity feed |

**Simulation:**
| File | What it does |
|------|-------------|
| `simulate-workflow.sh` | Full 3-handler CRE simulation with preflight checks and on-chain verification |

</td>
</tr>
</table>

<table>
<tr>
<td>

### [PR #2 — Tenderly Virtual TestNet Integration](https://github.com/aliveevie/proof-of-pulse/pull/2)

Deep Tenderly integration — transaction simulation, state override edge case testing, and one-command VNet deployment.

**New Files:**
| File | What it does |
|------|-------------|
| `setup-tenderly.sh` | One-command VNet creation, wallet funding, contract deployment + verification |
| `test-edge-cases.sh` | State override edge case testing (4 scenarios) |
| `contracts/script/Deploy.s.sol` | Foundry deploy script with Sepolia KeystoneForwarder |
| `frontend/src/components/TenderlySimulator.tsx` | Transaction simulation UI with Tenderly branding |
| `frontend/src/hooks/useSimulation.ts` | EVM `eth_call` simulation logic |

**Modified Files:**
| File | Change |
|------|--------|
| `simulate-workflow.sh` | Auto-loads `.env.tenderly`, adds Tenderly Explorer TX links |
| `frontend/src/App.tsx` | Added simulator component |
| `frontend/src/index.css` | Tenderly simulator styles (purple accent) |
| `frontend/src/config/contracts.ts` | Tenderly VNet RPC + contract addresses |
| `project.yaml` | Staging RPC pointed to Tenderly VNet |
| `my-workflow/config.staging.json` | PoR contract address for Tenderly deployment |

</td>
</tr>
</table>

---

## Project Structure

```
proof-of-pulse/
├── contracts/                          # Foundry smart contracts
│   ├── src/
│   │   ├── WBTCProofOfReserve.sol      # CRE Receiver — reserve + risk storage
│   │   ├── PulseGuard.sol              # DeFi circuit breaker vault
│   │   └── interfaces/                 # Chainlink CRE interfaces
│   ├── test/                           # 62 Solidity tests
│   ├── script/Deploy.s.sol             # Foundry deployment script
│   └── abi/                            # TypeScript ABI exports
├── my-workflow/                        # CRE TypeScript workflow
│   ├── main.ts                         # 3 trigger handlers (cron, log, http)
│   ├── gemini.ts                       # Gemini AI with CRE consensus
│   ├── workflow.yaml                   # CRE workflow config
│   └── config.staging.json             # Runtime config
├── frontend/                           # React + Vite + TypeScript dashboard
│   ├── src/
│   │   ├── components/                 # Reserve, Risk, Vault, Chart, Simulator
│   │   ├── hooks/                      # useContracts, useSimulation
│   │   └── config/contracts.ts         # ABIs and addresses
├── simulate-workflow.sh                # Full 3-handler CRE simulation
├── setup-tenderly.sh                   # Tenderly VNet setup + deploy
├── test-edge-cases.sh                  # State override edge case testing
├── project.yaml                        # CRE project config
└── secrets.yaml                        # CRE secret references
```

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Three trigger types** | Cron for baseline monitoring, Log for user-initiated AI audits, HTTP for integrations |
| **5% divergence threshold** | Balances sensitivity vs noise — accounts for timing differences between sources |
| **99% health threshold** | 1% buffer for BTC block confirmation lag vs WBTC mint/burn settlement |
| **Prefix-byte routing** | Single contract entry point with extensible report types (`0x01` reserve, `0x02` risk) |
| **Blockstream as BTC source** | Public, non-custodian data — independent verification, not attestation |
| **Withdrawals always allowed** | User safety first — PulseGuard never locks funds, only blocks new deposits |

---

## License

MIT
