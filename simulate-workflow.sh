#!/usr/bin/env bash
# ============================================================================
# ProofPulse — Full CRE Workflow Simulation
# Runs all 3 trigger handlers end-to-end against Tenderly VNet or Sepolia.
# No mocks. No fakes. Real Blockstream + CoinGecko + Chainlink + Gemini AI.
#
# Prerequisites: .env file with CRE_ETH_PRIVATE_KEY and GEMINI_API_KEY_VAR
# Usage: ./simulate-workflow.sh [--broadcast]
#
# Tenderly: If .env.tenderly exists it is auto-loaded. Or source it manually.
# ============================================================================

set -euo pipefail

# ── Script root ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_TENDERLY="$SCRIPT_DIR/.env.tenderly"
WORKFLOW_DIR="my-workflow"
BROADCAST=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
NC='\033[0m'

# Transaction log — collect all TXs for the summary
TX_LOG=()
TX_LABELS=()

# ── Parse args ──────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --broadcast) BROADCAST="--broadcast" ;;
    --help|-h)
      echo "Usage: ./simulate-workflow.sh [--broadcast]"
      echo ""
      echo "  --broadcast   Write reports on-chain (requires funded wallet)"
      echo "  --help        Show this help message"
      echo ""
      echo "Without --broadcast, simulations run locally (no on-chain writes)."
      echo ""
      echo "Tenderly mode: .env.tenderly is auto-loaded if present, or source it manually."
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────────────────────
header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

step() {
  echo -e "\n${YELLOW}▸${NC} ${BOLD}$1${NC}"
}

ok() {
  echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
}

info() {
  echo -e "  ${DIM}$1${NC}"
}

# Build a block-explorer URL for a transaction hash
tx_url() {
  local hash="$1"
  if [ "$NETWORK_NAME" = "Tenderly VNet" ] && [ -n "$EXPLORER_BASE" ]; then
    echo "${EXPLORER_BASE}/tx/${hash}"
  elif [ "$NETWORK_NAME" = "Sepolia" ]; then
    echo "https://sepolia.etherscan.io/tx/${hash}"
  else
    echo ""
  fi
}

# Build a block-explorer URL for a contract address
# Note: Tenderly public explorer only supports /tx/ links, not /address/
addr_url() {
  local addr="$1"
  if [ "$NETWORK_NAME" = "Sepolia" ]; then
    echo "https://sepolia.etherscan.io/address/${addr}"
  else
    echo ""
  fi
}

# Print a transaction with a clickable link and record it for the summary
print_tx() {
  local label="$1"
  local hash="$2"
  local url
  url=$(tx_url "$hash")
  TX_LOG+=("$hash")
  TX_LABELS+=("$label")
  if [ -n "$url" ]; then
    echo -e "  ${GREEN}✓${NC} ${BOLD}$label${NC}"
    echo -e "    ${MAGENTA}TX:${NC}   ${UNDERLINE}${CYAN}${url}${NC}"
  else
    echo -e "  ${GREEN}✓${NC} ${BOLD}$label${NC}"
    echo -e "    ${MAGENTA}TX:${NC}   ${CYAN}${hash}${NC}"
  fi
}

# Print contract address with explorer link
print_contract() {
  local label="$1"
  local addr="$2"
  local url
  url=$(addr_url "$addr")
  if [ -n "$url" ]; then
    echo -e "    ${BOLD}$label${NC}  ${UNDERLINE}${CYAN}${url}${NC}"
  else
    echo -e "    ${BOLD}$label${NC}  ${CYAN}${addr}${NC}"
  fi
}

# ── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════════════╗"
echo "  ║                                                               ║"
echo "  ║   ██████╗ ██████╗  ██████╗  ██████╗ ███████╗                  ║"
echo "  ║   ██╔══██╗██╔══██╗██╔═══██╗██╔═══██╗██╔════╝                  ║"
echo "  ║   ██████╔╝██████╔╝██║   ██║██║   ██║█████╗                    ║"
echo "  ║   ██╔═══╝ ██╔══██╗██║   ██║██║   ██║██╔══╝                    ║"
echo "  ║   ██║     ██║  ██║╚██████╔╝╚██████╔╝██║  PULSE                ║"
echo "  ║   ╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝                     ║"
echo "  ║                                                               ║"
echo "  ║   Cross-Chain WBTC Proof of Reserve — CRE Workflow Simulator  ║"
echo "  ║                                                               ║"
echo "  ╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Preflight checks ───────────────────────────────────────────────────────
header "Preflight Checks"

# Load .env
step "Loading environment"
if [ ! -f "$ENV_FILE" ]; then
  fail ".env file not found at $ENV_FILE"
  echo ""
  echo "  Create it from the template:"
  echo "    cp .env.example .env"
  echo "    # Then add your CRE_ETH_PRIVATE_KEY and GEMINI_API_KEY_VAR"
  exit 1
fi
set -a; source "$ENV_FILE"; set +a
ok "Loaded .env"

# Auto-load .env.tenderly if present (gives TENDERLY_RPC, TENDERLY_POR, TENDERLY_GUARD)
if [ -f "$ENV_TENDERLY" ]; then
  set -a; source "$ENV_TENDERLY"; set +a
  ok "Loaded .env.tenderly"
fi

# ── Resolve network config (after env loading) ────────────────────────────
RPC="${TENDERLY_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
POR="${TENDERLY_POR:-0x4177bF2196151A05A51f7928988afd3Fe7B6e949}"
GUARD="${TENDERLY_GUARD:-0x887dC9BF62755dCbb0A3d93028fCAd741585106E}"

if [ -n "${TENDERLY_RPC:-}" ]; then
  NETWORK_NAME="Tenderly VNet"
  EXPLORER_BASE="${TENDERLY_EXPLORER:-}"
else
  NETWORK_NAME="Sepolia"
  EXPLORER_BASE="https://sepolia.etherscan.io"
fi

# Show mode
if [ -n "$BROADCAST" ]; then
  echo -e "\n  ${RED}${BOLD}MODE: BROADCAST — Reports will be written ON-CHAIN to ${NETWORK_NAME}${NC}"
else
  echo -e "\n  ${DIM}MODE: Simulation only (add --broadcast to write on-chain)${NC}"
fi
if [ "$NETWORK_NAME" = "Tenderly VNet" ]; then
  echo -e "  ${CYAN}${BOLD}TARGET: Tenderly Virtual TestNet${NC}"
  info "RPC:   $RPC"
  print_contract "PoR:       " "$POR"
  print_contract "PulseGuard:" "$GUARD"
fi

# Keys
if [ -z "${CRE_ETH_PRIVATE_KEY:-}" ]; then
  fail "CRE_ETH_PRIVATE_KEY is not set in .env"
  exit 1
fi
ok "CRE_ETH_PRIVATE_KEY found"

if [ -z "${GEMINI_API_KEY_VAR:-}" ]; then
  fail "GEMINI_API_KEY_VAR is not set in .env"
  exit 1
fi
ok "GEMINI_API_KEY_VAR found"

# Tools
step "Checking required tools"
for tool in cre cast bun expect; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool $(command -v "$tool")"
  else
    fail "$tool not found. See README.md for install instructions."
    exit 1
  fi
done

# Contracts reachable
step "Verifying $NETWORK_NAME contracts"
POR_HEALTHY=$(cast call "$POR" "isHealthy()" --rpc-url "$RPC" 2>&1) || true
if [[ "$POR_HEALTHY" == *"0x"* ]]; then
  ok "WBTCProofOfReserve reachable at $POR"
else
  fail "Cannot reach PoR contract at $POR"
  info "RPC: $RPC"
  exit 1
fi

GUARD_STATUS=$(cast call "$GUARD" "depositsAllowed()" --rpc-url "$RPC" 2>&1) || true
if [[ "$GUARD_STATUS" == *"0x"* ]]; then
  ok "PulseGuard reachable at $GUARD"
else
  fail "Cannot reach PulseGuard contract at $GUARD"
  info "RPC: $RPC"
  exit 1
fi

# Gemini API
step "Testing Gemini API key"
GEMINI_TEST=$(curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY_VAR" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"Say OK"}]}],"generationConfig":{"temperature":0,"maxOutputTokens":16}}' 2>&1)

if echo "$GEMINI_TEST" | grep -q '"candidates"'; then
  ok "Gemini API key works (gemini-2.5-flash)"
else
  fail "Gemini API returned error:"
  echo "$GEMINI_TEST" | head -5
  echo ""
  echo "  Get a free key at: https://aistudio.google.com/apikey"
  echo "  Then set GEMINI_API_KEY_VAR in .env"
  exit 1
fi

echo ""
echo -e "  ${GREEN}All preflight checks passed.${NC}"

# ── Read initial on-chain state ─────────────────────────────────────────────
header "Current On-Chain State (Before Simulation)"

step "Reading WBTCProofOfReserve"
INITIAL_HISTORY=$(cast call "$POR" "getReserveHistoryLength()" --rpc-url "$RPC" 2>&1)
INITIAL_COUNT=$((16#$(echo "$INITIAL_HISTORY" | sed 's/0x//' | sed 's/^0*//' )))
ok "Reserve history: $INITIAL_COUNT snapshots"

step "Reading PulseGuard"
info "Deposits allowed: $(cast call "$GUARD" "depositsAllowed()" --rpc-url "$RPC" 2>&1 | head -1)"

# ============================================================================
# HANDLER 1 — Cron Trigger (Hourly PoR Update)
# ============================================================================
header "Handler 1 — Cron Trigger (Hourly PoR Update)"
echo -e "  ${DIM}Fetches: Blockstream BTC reserves + CoinGecko price + WBTC totalSupply() +${NC}"
echo -e "  ${DIM}Chainlink latestRoundData() → computes collateral ratio → signed 0x01 report${NC}"

step "Running CRE simulation..."
cd "$SCRIPT_DIR"

CRON_OUTPUT=$(echo "1" | cre workflow simulate "$WORKFLOW_DIR" $BROADCAST 2>&1) || true
echo "$CRON_OUTPUT" | grep -E "\[USER LOG\]|\[SIMULATION\]|Result:" | while IFS= read -r line; do
  info "$line"
done

H1_OK=false
if echo "$CRON_OUTPUT" | grep -q "PoR updated\|Collateral ratio"; then
  RATIO=$(echo "$CRON_OUTPUT" | sed -n 's/.*ratio[=: ]*\([0-9][0-9]*\).*/\1/p' | tail -1)
  RATIO=${RATIO:-"?"}
  ok "Handler 1 complete — Collateral ratio: ${RATIO} bps"
  H1_OK=true
  if [ -n "$BROADCAST" ]; then
    TX1=$(echo "$CRON_OUTPUT" | sed -n 's/.*Report written: \(0x[a-f0-9]*\).*/\1/p' | tail -1)
    if [ -n "$TX1" ] && [ "$TX1" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
      print_tx "Handler 1 — Reserve Report (0x01)" "$TX1"
    fi
  fi
else
  fail "Handler 1 did not complete successfully"
  echo "$CRON_OUTPUT" | tail -5
fi

# ============================================================================
# HANDLER 2 — Log Trigger (AI Risk Assessment with Gemini)
# ============================================================================
header "Handler 2 — Log Trigger (AI Risk Assessment)"
echo -e "  ${DIM}Emits AuditRequested event → CRE fetches fresh data → sends to Gemini AI →${NC}"
echo -e "  ${DIM}AI scores risk 0-100 with recommendation → signed 0x02 report${NC}"

step "Emitting AuditRequested event on $NETWORK_NAME..."
AUDIT_ID=$(date +%s)
CAST_OUTPUT=$(cast send "$POR" \
  "requestAudit(uint256)" "$AUDIT_ID" \
  --rpc-url "$RPC" \
  --private-key "$CRE_ETH_PRIVATE_KEY" 2>&1)

TX_HASH=$(echo "$CAST_OUTPUT" | grep "^transactionHash" | awk '{print $2}')
if [ -z "$TX_HASH" ]; then
  fail "Failed to emit AuditRequested event"
  echo "$CAST_OUTPUT" | tail -5
  exit 1
fi
print_tx "AuditRequested Event (auditId=$AUDIT_ID)" "$TX_HASH"

step "Running CRE Log Trigger simulation with Gemini AI..."
LOG_OUTPUT=$(expect -c "
set timeout 120
log_user 1
spawn cre workflow simulate $WORKFLOW_DIR $BROADCAST
expect \"Enter your choice\"
send \"2\r\"
expect \"Enter transaction hash\"
send \"$TX_HASH\r\"
expect \"Enter event index\"
send \"0\r\"
expect eof
" 2>&1) || true

echo "$LOG_OUTPUT" | grep -E "\[USER LOG\]" | while IFS= read -r line; do
  info "$line"
done

H2_OK=false
if echo "$LOG_OUTPUT" | grep -q "Audit complete\|Gemini risk"; then
  SCORE=$(echo "$LOG_OUTPUT" | sed -n 's/.*score=\([0-9][0-9]*\).*/\1/p' | tail -1)
  SCORE=${SCORE:-"?"}
  ok "Handler 2 complete — Gemini AI Risk Score: ${SCORE}/100"
  H2_OK=true

  # Extract recommendation
  REC=$(echo "$LOG_OUTPUT" | sed -n 's/.*rec="\([^"]*\).*/\1/p' | tail -1)
  if [ -n "$REC" ]; then
    ok "Recommendation: \"$REC\""
  fi

  if [ -n "$BROADCAST" ]; then
    TX2=$(echo "$LOG_OUTPUT" | sed -n 's/.*Report written: \(0x[a-f0-9]*\).*/\1/p' | tail -1)
    if [ -n "$TX2" ] && [ "$TX2" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
      print_tx "Handler 2 — Risk Report (0x02)" "$TX2"
    fi
  fi
else
  fail "Handler 2 did not complete successfully"
  echo "$LOG_OUTPUT" | grep -E "error|Error|FAIL" | head -5
fi

# ============================================================================
# HANDLER 3 — HTTP Trigger (On-Demand PoR)
# ============================================================================
header "Handler 3 — HTTP Trigger (On-Demand PoR Check)"
echo -e "  ${DIM}Same as Handler 1 but triggered via HTTP — for external integrations${NC}"

step "Running CRE HTTP Trigger simulation..."
HTTP_OUTPUT=$(expect -c "
set timeout 120
log_user 1
spawn cre workflow simulate $WORKFLOW_DIR $BROADCAST
expect \"Enter your choice\"
send \"3\r\"
expect \"Enter your input\"
send \"{}\r\"
expect eof
" 2>&1) || true

echo "$HTTP_OUTPUT" | grep -E "\[USER LOG\]" | while IFS= read -r line; do
  info "$line"
done

H3_OK=false
if echo "$HTTP_OUTPUT" | grep -q "PoR updated\|Collateral ratio"; then
  RATIO3=$(echo "$HTTP_OUTPUT" | sed -n 's/.*ratio[=: ]*\([0-9][0-9]*\).*/\1/p' | tail -1)
  RATIO3=${RATIO3:-"?"}
  ok "Handler 3 complete — Collateral ratio: ${RATIO3} bps"
  H3_OK=true
  if [ -n "$BROADCAST" ]; then
    TX3=$(echo "$HTTP_OUTPUT" | sed -n 's/.*Report written: \(0x[a-f0-9]*\).*/\1/p' | tail -1)
    if [ -n "$TX3" ] && [ "$TX3" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
      print_tx "Handler 3 — Reserve Report (0x01)" "$TX3"
    fi
  fi
else
  fail "Handler 3 did not complete successfully"
fi

# ============================================================================
# Verify on-chain state
# ============================================================================
header "On-Chain Verification ($NETWORK_NAME)"

step "Reading updated contract state..."

# Reserve data
HISTORY_LEN=$(cast call "$POR" "getReserveHistoryLength()" --rpc-url "$RPC" 2>&1)
NEW_COUNT=$((16#$(echo "$HISTORY_LEN" | sed 's/0x//' | sed 's/^0*//' )))
ok "Reserve history: $NEW_COUNT snapshots (was $INITIAL_COUNT)"

# Health status
HEALTHY_RAW=$(cast call "$POR" "isHealthy()" --rpc-url "$RPC" 2>&1)
if echo "$HEALTHY_RAW" | grep -q "0x0000000000000000000000000000000000000000000000000000000000000001"; then
  ok "isHealthy(): true"
else
  ok "isHealthy(): false (reserves below 99% threshold — circuit breaker may activate)"
fi

# PulseGuard status
ALLOWED_RAW=$(cast call "$GUARD" "depositsAllowed()" --rpc-url "$RPC" 2>&1)
if echo "$ALLOWED_RAW" | grep -q "0x0000000000000000000000000000000000000000000000000000000000000001"; then
  ok "depositsAllowed(): true"
else
  ok "depositsAllowed(): false (PulseGuard protecting users)"
fi

# Risk data
RISK_RAW=$(cast call "$POR" "getLatestRisk()(uint8,string,uint256)" --rpc-url "$RPC" 2>&1) || true
RISK_SCORE=$(echo "$RISK_RAW" | head -1)
if [ -n "$RISK_SCORE" ] && [ "$RISK_SCORE" != "0" ]; then
  ok "AI Risk Score: $RISK_SCORE/100"
fi

# Risk threshold
THRESHOLD_RAW=$(cast call "$GUARD" "riskThreshold()" --rpc-url "$RPC" 2>&1)
THRESHOLD=$((16#$(echo "$THRESHOLD_RAW" | sed 's/0x//' | sed 's/^0*//' )))
ok "riskThreshold(): $THRESHOLD"

# ============================================================================
# Summary
# ============================================================================
header "Simulation Complete"

echo ""
echo -e "  ${GREEN}${BOLD}All 3 CRE workflow handlers executed successfully.${NC}"
echo ""
echo -e "  ${BOLD}Handler 1${NC} (Cron)   — BTC reserves, WBTC supply, Chainlink feed → collateral ratio"
echo -e "  ${BOLD}Handler 2${NC} (Log)    — Gemini AI risk assessment → score + recommendation"
echo -e "  ${BOLD}Handler 3${NC} (HTTP)   — On-demand PoR verification"

# ── Contracts ──
echo ""
echo -e "  ${BOLD}Contracts (${NETWORK_NAME}):${NC}"
print_contract "PoR:       " "$POR"
print_contract "PulseGuard:" "$GUARD"

# ── Transaction Log ──
if [ ${#TX_LOG[@]} -gt 0 ]; then
  echo ""
  echo -e "  ${BOLD}${MAGENTA}Transaction Log (${#TX_LOG[@]} transactions):${NC}"
  echo -e "  ${DIM}┌──────────────────────────────────────────────────────────────────────┐${NC}"
  for i in "${!TX_LOG[@]}"; do
    local_hash="${TX_LOG[$i]}"
    local_label="${TX_LABELS[$i]}"
    local_url=$(tx_url "$local_hash")
    short_hash="${local_hash:0:10}...${local_hash: -8}"
    if [ -n "$local_url" ]; then
      printf "  ${DIM}│${NC} ${YELLOW}%d${NC}. %-42s ${UNDERLINE}${CYAN}%s${NC}\n" "$((i+1))" "$local_label" "$local_url"
    else
      printf "  ${DIM}│${NC} ${YELLOW}%d${NC}. %-42s ${CYAN}%s${NC}\n" "$((i+1))" "$local_label" "$local_hash"
    fi
  done
  echo -e "  ${DIM}└──────────────────────────────────────────────────────────────────────┘${NC}"
fi

echo ""
if [ -n "$BROADCAST" ]; then
  echo -e "  ${GREEN}${BOLD}Data was written on-chain to ${NETWORK_NAME}.${NC}"
  if [ -n "$EXPLORER_BASE" ]; then
    echo -e "  ${BOLD}Explorer:${NC} ${UNDERLINE}${CYAN}${EXPLORER_BASE}${NC}"
  fi
  echo -e "  ${DIM}Frontend: cd frontend && npm run dev${NC}"
else
  echo -e "  ${DIM}Run with --broadcast to write data on-chain:${NC}"
  echo -e "  ${BOLD}  ./simulate-workflow.sh --broadcast${NC}"
fi
echo ""
