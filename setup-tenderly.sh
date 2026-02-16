#!/usr/bin/env bash
# ============================================================================
# ProofPulse — Tenderly Virtual TestNet Setup
# Creates a Tenderly VNet (forked from Sepolia), deploys + verifies contracts,
# and produces a sourceable .env.tenderly for use with simulate-workflow.sh.
#
# Prerequisites: TENDERLY_ACCESS_KEY env var or in .env
# Usage: ./setup-tenderly.sh [--update-configs]
# ============================================================================

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_TENDERLY="$SCRIPT_DIR/.env.tenderly"
VNET_CHAIN_ID=11155111
RISK_THRESHOLD=70
UPDATE_CONFIGS=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Parse args ──────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --update-configs) UPDATE_CONFIGS=true ;;
    --help|-h)
      echo "Usage: ./setup-tenderly.sh [--update-configs]"
      echo ""
      echo "  --update-configs  Also update project.yaml, config.staging.json,"
      echo "                    and frontend/src/config/contracts.ts with Tenderly"
      echo "                    values (creates .bak backups)"
      echo "  --help            Show this help message"
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
echo "  ║   Tenderly Virtual TestNet Setup                              ║"
echo "  ║                                                               ║"
echo "  ╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================================
# Phase A: Validate Environment
# ============================================================================
header "Phase A — Validate Environment"

# Load .env if present
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
  ok "Loaded .env"
fi

# Tenderly access key
step "Checking TENDERLY_ACCESS_KEY"
if [ -z "${TENDERLY_ACCESS_KEY:-}" ]; then
  fail "TENDERLY_ACCESS_KEY is not set"
  echo ""
  echo -e "  ${BOLD}To get a Tenderly access key:${NC}"
  echo "    1. Sign up at https://dashboard.tenderly.co/register"
  echo "    2. Go to Settings → Authorization → Generate Access Token"
  echo "    3. Add to .env:  TENDERLY_ACCESS_KEY=your_token_here"
  exit 1
fi
ok "TENDERLY_ACCESS_KEY found"

# Private key
step "Checking CRE_ETH_PRIVATE_KEY"
if [ -z "${CRE_ETH_PRIVATE_KEY:-}" ]; then
  fail "CRE_ETH_PRIVATE_KEY is not set in .env"
  exit 1
fi
ok "CRE_ETH_PRIVATE_KEY found"

# Derive deployer address
DEPLOYER=$(cast wallet address --private-key "$CRE_ETH_PRIVATE_KEY" 2>/dev/null)
ok "Deployer address: $DEPLOYER"

# Required tools
step "Checking required tools"
for tool in forge cast curl jq; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool $(command -v "$tool")"
  else
    fail "$tool not found. Please install it first."
    exit 1
  fi
done

echo ""
echo -e "  ${GREEN}Environment validated.${NC}"

# ============================================================================
# Phase B: Create Tenderly Virtual TestNet
# ============================================================================
header "Phase B — Create Tenderly Virtual TestNet"

step "Creating VNet (forked from Sepolia, chain ID $VNET_CHAIN_ID)..."

VNET_RESPONSE=$(curl -s -X POST "https://api.tenderly.co/api/v1/account/me/project/project/vnets" \
  -H "X-Access-Key: $TENDERLY_ACCESS_KEY" \
  -H "Content-Type: application/json" \
  -d "$(cat <<REQEOF
{
  "slug": "proofpulse-$(date +%s)",
  "display_name": "ProofPulse TestNet",
  "fork_config": {
    "network_id": 11155111
  },
  "virtual_network_config": {
    "chain_config": {
      "chain_id": $VNET_CHAIN_ID
    }
  },
  "sync_state_config": {
    "enabled": false
  },
  "explorer_page_config": {
    "enabled": true,
    "verification_visibility": "src"
  }
}
REQEOF
)")

# Check for errors
if echo "$VNET_RESPONSE" | jq -e '.error' &>/dev/null 2>&1; then
  ERROR_MSG=$(echo "$VNET_RESPONSE" | jq -r '.error.message // .error // "Unknown error"')
  fail "Failed to create VNet: $ERROR_MSG"
  info "Full response: $VNET_RESPONSE"
  exit 1
fi

# Extract VNet ID
VNET_ID=$(echo "$VNET_RESPONSE" | jq -r '.id // empty')
if [ -z "$VNET_ID" ]; then
  fail "Failed to parse VNet ID from response"
  info "Response: $(echo "$VNET_RESPONSE" | head -c 500)"
  exit 1
fi
ok "VNet created: $VNET_ID"

# Extract RPCs — Admin RPC and Public RPC from rpcs[] array
ADMIN_RPC=$(echo "$VNET_RESPONSE" | jq -r '.rpcs[] | select(.name == "Admin RPC") | .url // empty')
PUBLIC_RPC=$(echo "$VNET_RESPONSE" | jq -r '.rpcs[] | select(.name == "Public RPC") | .url // empty')

# Fallback: try positional extraction if name-based fails
if [ -z "$ADMIN_RPC" ]; then
  ADMIN_RPC=$(echo "$VNET_RESPONSE" | jq -r '.rpcs[0].url // empty')
fi
if [ -z "$PUBLIC_RPC" ]; then
  PUBLIC_RPC=$(echo "$VNET_RESPONSE" | jq -r '.rpcs[1].url // empty')
fi

if [ -z "$ADMIN_RPC" ]; then
  fail "Could not extract Admin RPC from response"
  info "Response rpcs: $(echo "$VNET_RESPONSE" | jq '.rpcs')"
  exit 1
fi

ok "Admin RPC: $ADMIN_RPC"
ok "Public RPC: ${PUBLIC_RPC:-"(not available)"}"

# Extract explorer URL
EXPLORER_URL=$(echo "$VNET_RESPONSE" | jq -r '.explorer_page_url // empty')
if [ -z "$EXPLORER_URL" ]; then
  # Construct it from the slug
  VNET_SLUG=$(echo "$VNET_RESPONSE" | jq -r '.slug // empty')
  if [ -n "$VNET_SLUG" ]; then
    EXPLORER_URL="https://dashboard.tenderly.co/explorer/vnet/$VNET_SLUG"
  fi
fi
ok "Explorer: ${EXPLORER_URL:-"(will be available after first transaction)"}"

# ============================================================================
# Phase C: Fund Deployer
# ============================================================================
header "Phase C — Fund Deployer"

step "Setting deployer balance to 100 ETH..."
FUND_RESULT=$(curl -s -X POST "$ADMIN_RPC" \
  -H "Content-Type: application/json" \
  -d "$(cat <<FUNDEOF
{
  "jsonrpc": "2.0",
  "method": "tenderly_setBalance",
  "params": ["$DEPLOYER", "0x56BC75E2D63100000"],
  "id": 1
}
FUNDEOF
)")

if echo "$FUND_RESULT" | jq -e '.result' &>/dev/null 2>&1; then
  ok "Funded $DEPLOYER with 100 ETH"
else
  fail "Failed to fund deployer"
  info "Response: $FUND_RESULT"
  exit 1
fi

# Verify balance
BALANCE=$(cast balance "$DEPLOYER" --rpc-url "$ADMIN_RPC" 2>/dev/null || echo "unknown")
ok "Balance: $BALANCE"

# ============================================================================
# Phase D: Deploy Contracts
# ============================================================================
header "Phase D — Deploy Contracts"

# Sepolia KeystoneForwarder — CRE uses this to deliver signed reports to receiver contracts
KEYSTONE_FORWARDER="0x15fC6ae953E024d975e77382eEeC56A9101f9F88"

step "Deploying WBTCProofOfReserve (forwarder = KeystoneForwarder)..."
POR_DEPLOY=$(forge create \
  --private-key "$CRE_ETH_PRIVATE_KEY" \
  --rpc-url "$ADMIN_RPC" \
  --root "$SCRIPT_DIR/contracts" \
  --broadcast \
  src/WBTCProofOfReserve.sol:WBTCProofOfReserve \
  --constructor-args "$KEYSTONE_FORWARDER" 2>&1)

POR_ADDRESS=$(echo "$POR_DEPLOY" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$POR_ADDRESS" ]; then
  fail "WBTCProofOfReserve deployment failed"
  echo "$POR_DEPLOY" | tail -10
  exit 1
fi
ok "WBTCProofOfReserve deployed to: $POR_ADDRESS"

step "Deploying PulseGuard (porAddress=$POR_ADDRESS, threshold=$RISK_THRESHOLD)..."
GUARD_DEPLOY=$(forge create \
  --private-key "$CRE_ETH_PRIVATE_KEY" \
  --rpc-url "$ADMIN_RPC" \
  --root "$SCRIPT_DIR/contracts" \
  --broadcast \
  src/PulseGuard.sol:PulseGuard \
  --constructor-args "$POR_ADDRESS" "$RISK_THRESHOLD" 2>&1)

GUARD_ADDRESS=$(echo "$GUARD_DEPLOY" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$GUARD_ADDRESS" ]; then
  fail "PulseGuard deployment failed"
  echo "$GUARD_DEPLOY" | tail -10
  exit 1
fi
ok "PulseGuard deployed to: $GUARD_ADDRESS"

# Verify contracts are reachable
step "Verifying deployed contracts..."
POR_CHECK=$(cast call "$POR_ADDRESS" "isHealthy()" --rpc-url "$ADMIN_RPC" 2>&1) || true
if [[ "$POR_CHECK" == *"0x"* ]]; then
  ok "WBTCProofOfReserve responding"
else
  fail "WBTCProofOfReserve not responding"
fi

GUARD_CHECK=$(cast call "$GUARD_ADDRESS" "depositsAllowed()" --rpc-url "$ADMIN_RPC" 2>&1) || true
if [[ "$GUARD_CHECK" == *"0x"* ]]; then
  ok "PulseGuard responding"
else
  fail "PulseGuard not responding"
fi

# ============================================================================
# Phase E: Verify Contracts on Tenderly
# ============================================================================
header "Phase E — Verify Contracts on Tenderly Explorer"

step "Verifying WBTCProofOfReserve..."
VERIFY_POR=$(forge verify-contract "$POR_ADDRESS" \
  src/WBTCProofOfReserve.sol:WBTCProofOfReserve \
  --root "$SCRIPT_DIR/contracts" \
  --chain "$VNET_CHAIN_ID" \
  --verifier custom \
  --verifier-url "$ADMIN_RPC/verify/etherscan" \
  --constructor-args "$(cast abi-encode "constructor(address)" "$KEYSTONE_FORWARDER")" 2>&1) || true

if echo "$VERIFY_POR" | grep -qi "success\|submitted\|already verified"; then
  ok "WBTCProofOfReserve verified"
else
  echo -e "  ${YELLOW}⚠${NC} Verification may have failed (non-blocking):"
  echo "$VERIFY_POR" | tail -3 | while IFS= read -r line; do info "$line"; done
fi

step "Verifying PulseGuard..."
VERIFY_GUARD=$(forge verify-contract "$GUARD_ADDRESS" \
  src/PulseGuard.sol:PulseGuard \
  --root "$SCRIPT_DIR/contracts" \
  --chain "$VNET_CHAIN_ID" \
  --verifier custom \
  --verifier-url "$ADMIN_RPC/verify/etherscan" \
  --constructor-args "$(cast abi-encode "constructor(address,uint8)" "$POR_ADDRESS" "$RISK_THRESHOLD")" 2>&1) || true

if echo "$VERIFY_GUARD" | grep -qi "success\|submitted\|already verified"; then
  ok "PulseGuard verified"
else
  echo -e "  ${YELLOW}⚠${NC} Verification may have failed (non-blocking):"
  echo "$VERIFY_GUARD" | tail -3 | while IFS= read -r line; do info "$line"; done
fi

# ============================================================================
# Phase F: Write .env.tenderly
# ============================================================================
header "Phase F — Write .env.tenderly"

cat > "$ENV_TENDERLY" <<ENVEOF
# ProofPulse — Tenderly Virtual TestNet Configuration
# Generated by setup-tenderly.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Source this file before running simulate-workflow.sh:
#   source .env.tenderly

# Tenderly VNet RPC (used by simulate-workflow.sh and cast)
TENDERLY_RPC=$ADMIN_RPC

# Deployed contract addresses on Tenderly VNet
TENDERLY_POR=$POR_ADDRESS
TENDERLY_GUARD=$GUARD_ADDRESS

# VNet metadata
TENDERLY_VNET_ID=$VNET_ID
TENDERLY_CHAIN_ID=$VNET_CHAIN_ID
TENDERLY_EXPLORER=${EXPLORER_URL:-}
TENDERLY_VIRTUAL_TESTNET_RPC_URL=$ADMIN_RPC
ENVEOF

ok "Written to $ENV_TENDERLY"

# ============================================================================
# Phase G (optional): Update CRE + frontend configs
# ============================================================================
if [ "$UPDATE_CONFIGS" = true ]; then
  header "Phase G — Update Project Configs (--update-configs)"

  # project.yaml — swap Sepolia RPC for Tenderly Admin RPC
  step "Updating project.yaml..."
  if [ -f "$SCRIPT_DIR/project.yaml" ]; then
    cp "$SCRIPT_DIR/project.yaml" "$SCRIPT_DIR/project.yaml.bak"
    sed -i.tmp "s|url: https://ethereum-sepolia-rpc.publicnode.com|url: $ADMIN_RPC|" "$SCRIPT_DIR/project.yaml"
    rm -f "$SCRIPT_DIR/project.yaml.tmp"
    ok "project.yaml updated (backup: project.yaml.bak)"
  else
    fail "project.yaml not found"
  fi

  # config.staging.json — swap contract addresses
  step "Updating my-workflow/config.staging.json..."
  CONFIG_FILE="$SCRIPT_DIR/my-workflow/config.staging.json"
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    # Replace WBTCProofOfReserve address
    sed -i.tmp "s/0x4177bF2196151A05A51f7928988afd3Fe7B6e949/$POR_ADDRESS/gi" "$CONFIG_FILE"
    # Replace PulseGuard address
    sed -i.tmp "s/0x887dC9BF62755dCbb0A3d93028fCAd741585106E/$GUARD_ADDRESS/gi" "$CONFIG_FILE"
    rm -f "$CONFIG_FILE.tmp"
    ok "config.staging.json updated (backup: config.staging.json.bak)"
  else
    info "config.staging.json not found (skipped)"
  fi

  # frontend/src/config/contracts.ts — swap addresses and RPC
  step "Updating frontend/src/config/contracts.ts..."
  FRONTEND_CONFIG="$SCRIPT_DIR/frontend/src/config/contracts.ts"
  if [ -f "$FRONTEND_CONFIG" ]; then
    cp "$FRONTEND_CONFIG" "$FRONTEND_CONFIG.bak"
    sed -i.tmp "s|https://ethereum-sepolia-rpc.publicnode.com|$ADMIN_RPC|" "$FRONTEND_CONFIG"
    sed -i.tmp "s/11155111/$VNET_CHAIN_ID/" "$FRONTEND_CONFIG"
    sed -i.tmp "s/0x4177bF2196151A05A51f7928988afd3Fe7B6e949/$POR_ADDRESS/gi" "$FRONTEND_CONFIG"
    sed -i.tmp "s/0x887dC9BF62755dCbb0A3d93028fCAd741585106E/$GUARD_ADDRESS/gi" "$FRONTEND_CONFIG"
    rm -f "$FRONTEND_CONFIG.tmp"
    ok "contracts.ts updated (backup: contracts.ts.bak)"
  else
    info "frontend/src/config/contracts.ts not found (skipped)"
  fi
fi

# ============================================================================
# Summary
# ============================================================================
header "Setup Complete"

echo ""
echo -e "  ${GREEN}${BOLD}Tenderly Virtual TestNet is ready!${NC}"
echo ""
echo -e "  ${BOLD}VNet Details:${NC}"
echo -e "    Chain ID:    ${CYAN}$VNET_CHAIN_ID${NC}"
echo -e "    Admin RPC:   ${CYAN}$ADMIN_RPC${NC}"
echo -e "    Public RPC:  ${CYAN}${PUBLIC_RPC:-"(not available)"}${NC}"
if [ -n "${EXPLORER_URL:-}" ]; then
  echo -e "    Explorer:    ${CYAN}$EXPLORER_URL${NC}"
fi
echo ""
echo -e "  ${BOLD}Deployed Contracts:${NC}"
echo -e "    WBTCProofOfReserve: ${CYAN}$POR_ADDRESS${NC}"
echo -e "    PulseGuard:         ${CYAN}$GUARD_ADDRESS${NC}"
echo ""
echo -e "  ${BOLD}Next Steps:${NC}"
echo ""
echo -e "    ${YELLOW}1.${NC} Source the environment:"
echo -e "       ${BOLD}source .env.tenderly${NC}"
echo ""
echo -e "    ${YELLOW}2.${NC} Run the workflow simulation against Tenderly:"
echo -e "       ${BOLD}./simulate-workflow.sh --broadcast${NC}"
echo ""
if [ "$UPDATE_CONFIGS" = false ]; then
  echo -e "    ${YELLOW}3.${NC} (Optional) Update all project configs to point to Tenderly:"
  echo -e "       ${BOLD}./setup-tenderly.sh --update-configs${NC}"
  echo ""
fi
echo -e "  ${BOLD}Environment saved to:${NC} .env.tenderly"
echo ""
