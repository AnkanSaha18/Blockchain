#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  DCBA Project — Status Check
#  File: ~/dcba/network/status.sh
#  Usage: bash status.sh
#  Shows what is currently running and what is not.
# ═══════════════════════════════════════════════════════════════════

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[UP]  $1${NC}"; }
down() { echo -e "  ${RED}[DOWN] $1${NC}"; }
warn() { echo -e "  ${YELLOW}[WARN] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DCBA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BLOCKCHAIN_DIR="$DCBA_ROOT/Blockchain"
FABRIC_NETWORK="$HOME/fabric/fabric-samples/test-network"

echo -e "\n${BOLD}${CYAN}  DCBA Project Status — $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"

# ── Hardhat node ────────────────────────────────────────────
echo -e "${BOLD}  Ethereum (PDC)${NC}"
if curl -s -X POST http://127.0.0.1:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  >/dev/null 2>&1; then
  BLOCK=$(curl -s -X POST http://127.0.0.1:8545 \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))" 2>/dev/null || echo "?")
  ok "Hardhat node running (block #$BLOCK)"
else
  down "Hardhat node NOT running → start with: bash start_project.sh"
fi

# Deployed contracts
if [ -f "$BLOCKCHAIN_DIR/deployed-addresses.json" ]; then
  ok "Contracts deployed (deployed-addresses.json exists)"
  python3 -c "
import json
with open('$BLOCKCHAIN_DIR/deployed-addresses.json') as f:
    d = json.load(f)
for k,v in d.items():
    print(f'      {k}: {v}')
" 2>/dev/null || true
else
  down "Contracts NOT deployed yet"
fi

# Oracle bridge
echo -e "\n${BOLD}  Oracle Bridge${NC}"
if pgrep -f "bridge.js" >/dev/null 2>&1; then
  PID=$(pgrep -f "bridge.js" | head -1)
  ok "Oracle Bridge running (PID: $PID)"
else
  down "Oracle Bridge NOT running"
fi

# ── Fabric containers ───────────────────────────────────────
echo -e "\n${BOLD}  Hyperledger Fabric (UOC)${NC}"
PEERS=$(docker ps --filter "name=peer0.org1" --format "{{.Names}}" 2>/dev/null)
ORDERER=$(docker ps --filter "name=orderer.example" --format "{{.Names}}" 2>/dev/null)
if [ -n "$PEERS" ] && [ -n "$ORDERER" ]; then
  ok "Fabric network running (peer0.org1, peer0.org2, orderer)"
  # Check chaincode container
  CC=$(docker ps --filter "name=dev-peer0" --format "{{.Names}}" 2>/dev/null | head -1)
  [ -n "$CC" ] && ok "Chaincode container: $CC" || warn "Chaincode container not found (not deployed yet?)"
else
  down "Fabric network NOT running → start with: bash start_project.sh"
fi

# ── Log files ───────────────────────────────────────────────
echo -e "\n${BOLD}  Log Files${NC}"
LOG_DIR="$SCRIPT_DIR/logs"
if [ -d "$LOG_DIR" ] && ls "$LOG_DIR"/*.log >/dev/null 2>&1; then
  for f in "$LOG_DIR"/*.log; do
    SIZE=$(wc -l < "$f" 2>/dev/null || echo 0)
    echo -e "  ${CYAN}  $f${NC} ($SIZE lines)"
  done
else
  echo "  No logs yet"
fi

echo ""
echo -e "  ${BOLD}Commands:${NC}"
echo -e "  ${CYAN}bash start_project.sh${NC}              — Start everything"
echo -e "  ${CYAN}bash start_project.sh --skip-deploy${NC} — Start (contracts already deployed)"
echo -e "  ${CYAN}bash start_project.sh --tests-only${NC}  — Only run tests"
echo -e "  ${CYAN}bash start_project.sh --skip-caliper${NC}— Skip Caliper benchmark"
echo -e "  ${CYAN}bash stop_project.sh${NC}               — Stop everything"
echo -e "  ${CYAN}bash stop_project.sh --clean${NC}       — Stop + full wipe"
echo -e "  ${CYAN}bash status.sh${NC}                     — This status check"
echo -e "  ${CYAN}bash network/run_test.sh${NC}           — Fabric chaincode test only"
echo ""
