#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  DCBA Project — Full Stop / Clean Script
#  File: ~/dcba/network/stop_project.sh
#  Usage: bash stop_project.sh [--clean]
#
#  --clean  also removes Docker volumes, Fabric crypto material,
#           Hardhat cache/artifacts, and deployed-addresses.json
#           (use this for a completely fresh restart)
# ═══════════════════════════════════════════════════════════════════

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
step() { echo -e "\n${BOLD}${CYAN}══ $1 ══${NC}"; }

CLEAN_MODE=false
for arg in "$@"; do
  [ "$arg" = "--clean" ] && CLEAN_MODE=true
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DCBA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BLOCKCHAIN_DIR="$DCBA_ROOT/Blockchain"
FABRIC_NETWORK="$HOME/fabric/fabric-samples/test-network"
PID_FILE="$SCRIPT_DIR/.dcba_pids"

echo -e "\n${BOLD}${CYAN}  DCBA Project — Stopping all services${NC}\n"

# ── Stop background processes from PID file ──────────────────
step "1 — Stop background processes"

if [ -f "$PID_FILE" ]; then
  while IFS='=' read -r name pid; do
    [ -z "$pid" ] && continue
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      ok "Stopped $name (PID $pid)"
    else
      info "$name (PID $pid) was already stopped"
    fi
  done < "$PID_FILE"
  rm -f "$PID_FILE"
else
  info "No PID file found"
fi

# Kill by name as backup
pkill -f "hardhat node"   2>/dev/null && ok "Killed Hardhat node"   || true
pkill -f "bridge.js"      2>/dev/null && ok "Killed Oracle Bridge"  || true
pkill -f "fleet_sim.py"   2>/dev/null && ok "Killed Fleet simulator"|| true

# ── Stop Hyperledger Fabric network ──────────────────────────
step "2 — Stop Hyperledger Fabric Network"

if [ -d "$FABRIC_NETWORK" ]; then
  cd "$FABRIC_NETWORK"
  info "Running network.sh down..."
  ./network.sh down 2>&1 | grep -E "Removed|Stopped|Error" || true
  ok "Fabric network stopped ✓"
else
  warn "Fabric test-network directory not found at $FABRIC_NETWORK"
fi

# ── Optional full clean ───────────────────────────────────────
if [ "$CLEAN_MODE" = true ]; then
  step "3 — Full clean (--clean mode)"

  info "Removing Docker volumes and chaincode images..."
  docker volume prune -f 2>/dev/null || true
  docker rmi $(docker images "dev-peer*" -q) 2>/dev/null || true
  ok "Docker cleanup done"

  if [ -d "$BLOCKCHAIN_DIR" ]; then
    info "Removing Hardhat cache, artifacts, deployed-addresses..."
    cd "$BLOCKCHAIN_DIR"
    rm -rf cache/ artifacts/ deployed-addresses.json
    ok "Hardhat artifacts cleared"

    info "Clearing logs..."
    rm -f "$SCRIPT_DIR/logs/"*.log
    ok "Logs cleared"
  fi

  info "Removing Fabric crypto material..."
  cd "$FABRIC_NETWORK"
  rm -rf organizations/peerOrganizations/ organizations/ordererOrganizations/ \
         channel-artifacts/ system-genesis-block/ 2>/dev/null || true
  ok "Fabric crypto material cleared"

  warn "Full clean done. Next run of start_project.sh will start from scratch."
else
  step "3 — Partial state preserved"
  info "Deployed addresses and Fabric crypto material kept."
  info "Use 'bash stop_project.sh --clean' for a completely fresh restart."
fi

echo ""
echo -e "${BOLD}${GREEN}  All DCBA services stopped ✓${NC}"
echo -e "  Stopped at: $(date '+%Y-%m-%d %H:%M:%S')\n"
