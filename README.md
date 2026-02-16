# ProofPulse

Cross-chain Proof of Reserve (PoR) verification system for Wrapped Bitcoin (WBTC), built on [Chainlink CRE](https://docs.chain.link/cre).

ProofPulse continuously monitors WBTC collateral health by reading BTC reserves from Bitcoin, WBTC supply from Ethereum, computing collateral ratios, comparing against the Chainlink PoR feed, and optionally running AI-powered anomaly detection via Google Gemini — then publishing verified results on-chain to Ethereum Sepolia.

## Prerequisites

| Tool | Install |
|------|---------|
| **Bun** (v1.3+) | [bun.sh](https://bun.sh) |
| **Foundry** (forge, cast) | [getfoundry.sh](https://getfoundry.sh) |
| **CRE CLI** | [CRE CLI releases](https://github.com/smartcontractkit/cre-cli/releases) |

## Setup

### 1. Clone and install dependencies

```bash
git clone <repo-url> && cd proofofpulse
cd my-workflow && bun install && cd ..
```

### 2. Configure environment variables

Create a `.env` file in the project root:

```env
# Required: Ethereum private key (funded on Sepolia for broadcast mode)
CRE_ETH_PRIVATE_KEY=your_private_key_here

# Required for AI risk assessment (Handler 2)
GEMINI_API_KEY_VAR=your_gemini_api_key_here
```

### 3. Configure RPC endpoints

Edit `project.yaml` to set your RPC endpoints for Ethereum Mainnet and Sepolia:

```yaml
staging-settings:
  rpcs:
    - chain-name: ethereum-testnet-sepolia
      url: https://ethereum-sepolia-rpc.publicnode.com
    - chain-name: ethereum-mainnet
      url: https://ethereum-rpc.publicnode.com
```

### 4. Configure contract addresses

Edit `my-workflow/config.staging.json` with your deployed contract addresses, or use the defaults (pre-deployed on Sepolia).

## Running the Project

### Smart Contract Tests

```bash
# Run all 15 tests
forge test -vvv --root contracts

# Run a single test
forge test -vvv --root contracts --match-test testUpdateReserve_storesData
```

### Workflow Simulation

All simulations are run from the **project root directory**.

#### Trigger 1 — Cron (Hourly PoR Update)

Fetches live BTC reserves, WBTC supply, Chainlink feed data, and computes collateral ratio.

```bash
echo "1" | cre workflow simulate my-workflow
```

#### Trigger 2 — Log (AI Risk Assessment via Gemini)

Requires an `AuditRequested` event on-chain. First, trigger one:

```bash
source .env
cast send 0x4177bF2196151A05A51f7928988afd3Fe7B6e949 \
  "requestAudit(uint256)" 1 \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --private-key $CRE_ETH_PRIVATE_KEY
```

Then simulate using the transaction hash from above (use `expect` for interactive prompts):

```bash
expect -c '
spawn cre workflow simulate my-workflow
expect "Enter your choice"
send "2\r"
expect "Enter transaction hash"
send "0x<YOUR_TX_HASH>\r"
expect "Enter event index"
send "0\r"
expect eof
'
```

This handler fetches fresh reserve data, queries Google Gemini for a risk score (0-100), and writes the result on-chain.

#### Trigger 3 — HTTP (On-Demand PoR)

Same computation as the cron trigger, executed on-demand:

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

### Broadcast Mode

To actually write signed reports to the Sepolia contract (requires a funded wallet):

```bash
echo "1" | cre workflow simulate my-workflow --broadcast
```

## Project Structure

```
proofofpulse/
├── contracts/                      # Foundry project
│   ├── src/
│   │   ├── WBTCProofOfReserve.sol  # CRE Receiver contract (reserve + risk storage)
│   │   └── interfaces/             # IReceiver, ReceiverTemplate (CRE standard)
│   ├── test/
│   │   └── WBTCProofOfReserve.t.sol # 15 tests (reserve, risk, access control, alerts)
│   └── foundry.toml
├── my-workflow/                    # CRE TypeScript workflow
│   ├── main.ts                     # 3 trigger handlers (cron, log, http)
│   ├── gemini.ts                   # Gemini AI helper with consensus aggregation
│   ├── config.staging.json         # Runtime config (addresses, APIs, chains)
│   └── workflow.yaml               # CRE workflow config
├── project.yaml                    # CRE project config (RPCs)
├── secrets.yaml                    # Secret references (Gemini API key)
└── .env                            # Environment variables (not committed)
```

## How It Works

```
Cron/HTTP Trigger
  ├─ Read WBTC totalSupply from Ethereum mainnet (EVM, DON consensus)
  ├─ Read Chainlink BTC reserve feed from mainnet (EVM, DON consensus)
  ├─ Fetch BTC reserves from Blockstream API (HTTP, node consensus)
  ├─ Fetch BTC/USD price from CoinGecko API (HTTP, node consensus)
  ├─ Compute collateral ratio = (BTC reserves × 10000) / WBTC supply
  ├─ Encode with 0x01 prefix
  └─ Write signed report to Sepolia contract

Log Trigger (AuditRequested event)
  ├─ Fetch fresh BTC reserves & price (drift detection)
  ├─ Read current WBTC supply & Chainlink feed
  ├─ Query Google Gemini AI for risk score (0-100) + recommendation
  ├─ Encode with 0x02 prefix
  └─ Write signed report to Sepolia contract
```

The smart contract routes incoming reports by prefix byte (`0x01` = reserve update, `0x02` = risk update) and emits alerts for undercollateralization (<100%) or Chainlink divergence (>5%).

## Rate Limits

- **CoinGecko free tier**: ~10 requests/minute. Space out trigger simulations if you hit 429 errors.
- **Gemini free tier**: Limited requests/minute. The workflow includes a fallback (score=50) when rate-limited.
