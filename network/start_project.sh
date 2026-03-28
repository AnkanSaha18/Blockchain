#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  DCBA Project — Full Start Script
#  File: ~/dcba/network/start_project.sh
#  Usage: bash start_project.sh [--skip-deploy] [--tests-only]
#
#  What this does (in order):
#   1. Check all tools are installed
#   2. Start Hyperledger Fabric test-network + dcbachannel
#   3. Deploy Go chaincode (dcba-uoc) to Fabric
#   4. Start Hardhat local Ethereum node (background)
#   5. Deploy all 7 Solidity contracts to Hardhat
#   6. Start Oracle Bridge (background)
#   7. Run full Hardhat test suite (86+ tests)
#   8. Run Fabric chaincode live tests (Bloom filter + PARS)
#   9. Run Caliper benchmark
#  10. Print final summary
# ═══════════════════════════════════════════════════════════════════

set -e  # exit on any error

# ── Colours for readable output ─────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $1 ══${NC}"; }

# ── Argument parsing ─────────────────────────────────────────
SKIP_DEPLOY=false
TESTS_ONLY=false
SKIP_CALIPER=false
for arg in "$@"; do
  case $arg in
    --skip-deploy)  SKIP_DEPLOY=true  ;;
    --tests-only)   TESTS_ONLY=true   ;;
    --skip-caliper) SKIP_CALIPER=true ;;
    --help)
      echo "Usage: bash start_project.sh [options]"
      echo "  --skip-deploy   Skip chaincode/contract deploy (use existing deployment)"
      echo "  --tests-only    Only run tests, skip network startup"
      echo "  --skip-caliper  Skip Caliper benchmark"
      exit 0
      ;;
  esac
done

# ── Paths ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DCBA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BLOCKCHAIN_DIR="$DCBA_ROOT/Blockchain"
CHAINCODE_DIR="$BLOCKCHAIN_DIR/chaincode/dcba-uoc"
FABRIC_NETWORK="$HOME/fabric/fabric-samples/test-network"
CHANNEL="dcbachannel"
CHAINCODE_NAME="dcba-uoc"
CHAINCODE_VERSION="2.0"

# PIDs of background processes — used by stop_project.sh
PID_FILE="$SCRIPT_DIR/.dcba_pids"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# ── Banner ───────────────────────────────────────────────────
echo -e "\n${BOLD}"
echo "  ██████   ██████ ██████   █████  "
echo "  ██   ██ ██      ██   ██ ██   ██ "
echo "  ██   ██ ██      ██████  ███████ "
echo "  ██   ██ ██      ██   ██ ██   ██ "
echo "  ██████   ██████ ██████  ██   ██ "
echo -e "${NC}"
echo -e "  ${CYAN}Dual-Chain Blockchain Architecture${NC}"
echo -e "  ${CYAN}BUET M.Sc. Research Project 2025-2026${NC}"
echo -e "  Starting: $(date '+%Y-%m-%d %H:%M:%S')\n"

# Clear old PIDs
echo "" > "$PID_FILE"

# ═══════════════════════════════════════════════════════════════
# STEP 0 — Pre-flight checks
# ═══════════════════════════════════════════════════════════════
step "0 — Pre-flight checks"

command -v node     >/dev/null 2>&1 || fail "Node.js not found. Install: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs"
command -v npx      >/dev/null 2>&1 || fail "npx not found (comes with Node.js)"
command -v docker   >/dev/null 2>&1 || fail "Docker not found. Install Docker first."
command -v go       >/dev/null 2>&1 || fail "Go not found. Install: sudo tar -C /usr/local -xzf go1.21.13.linux-amd64.tar.gz"
command -v python3  >/dev/null 2>&1 || fail "Python3 not found."
command -v peer     >/dev/null 2>&1 || {
  export PATH="$HOME/fabric/fabric-samples/bin:$PATH"
  command -v peer >/dev/null 2>&1 || fail "Fabric peer binary not found. Run Step 6 of setup guide."
}

ok "Node.js  : $(node --version)"
ok "Go       : $(go version | awk '{print $3}')"
ok "Docker   : $(docker --version | awk '{print $3}' | tr -d ',')"
ok "Python3  : $(python3 --version)"
ok "Peer     : $(peer version 2>&1 | grep 'Version:' | awk '{print $2}')"

[ -d "$FABRIC_NETWORK" ]  || fail "Fabric test-network not found at $FABRIC_NETWORK"
[ -d "$BLOCKCHAIN_DIR" ]  || fail "Blockchain project not found at $BLOCKCHAIN_DIR"
[ -d "$CHAINCODE_DIR" ]   || fail "Go chaincode not found at $CHAINCODE_DIR"

ok "All tools present ✓"

# ═══════════════════════════════════════════════════════════════
# STEP 1 — Build Go chaincode (verify it compiles)
# ═══════════════════════════════════════════════════════════════
step "1 — Build Go chaincode"

cd "$CHAINCODE_DIR"

info "Checking go.mod version..."
# go.mod must say 'go 1.21' not 'go 1.21.13' (Fabric Docker rejects patch version)
if grep -q "^go 1\.[0-9]*\.[0-9]" go.mod; then
  warn "go.mod has patch version — fixing to major.minor only..."
  sed -i 's/^go \([0-9]*\.[0-9]*\)\.[0-9]*/go \1/' go.mod
  ok "go.mod fixed"
fi

info "Running go mod tidy..."
go mod tidy 2>&1 | tail -5
info "Compiling chaincode..."
go build ./... && ok "Go chaincode compiles successfully ✓"

# ═══════════════════════════════════════════════════════════════
# STEP 2 — Start Hyperledger Fabric Network
# ═══════════════════════════════════════════════════════════════
step "2 — Hyperledger Fabric Network"

if [ "$TESTS_ONLY" = true ]; then
  warn "Skipping network startup (--tests-only mode)"
else
  cd "$FABRIC_NETWORK"

  info "Stopping any previous network..."
  ./network.sh down 2>/dev/null || true
  sleep 2

  info "Starting network and creating $CHANNEL..."
  ./network.sh up createChannel -c "$CHANNEL" 2>&1 | tee "$LOG_DIR/fabric_network.log" | grep -E "✔|Channel|ERROR|error" || true

  # Verify containers are up
  CONTAINERS=$(docker ps --format "{{.Names}}" | grep -cE "peer0\.(org1|org2)|orderer\.example" || echo 0)
  [ "$CONTAINERS" -ge 3 ] || fail "Fabric containers did not start (expected 3, got $CONTAINERS)"
  ok "Fabric network running — $CONTAINERS containers up ✓"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 3 — Deploy Go Chaincode to Fabric
# ═══════════════════════════════════════════════════════════════
step "3 — Deploy Chaincode to Fabric ($CHAINCODE_NAME v$CHAINCODE_VERSION)"

if [ "$SKIP_DEPLOY" = true ] || [ "$TESTS_ONLY" = true ]; then
  warn "Skipping chaincode deploy"
else
  cd "$FABRIC_NETWORK"

  info "Deploying $CHAINCODE_NAME v$CHAINCODE_VERSION to $CHANNEL..."
  ./network.sh deployCC \
    -ccn "$CHAINCODE_NAME" \
    -ccp "$CHAINCODE_DIR" \
    -ccl go \
    -c "$CHANNEL" \
    -ccv "$CHAINCODE_VERSION" \
    2>&1 | tee "$LOG_DIR/chaincode_deploy.log" | grep -E "committed|Approved|ERROR|error|failed" || true

  # Verify deployment
  cd "$FABRIC_NETWORK"
  export PATH="${FABRIC_NETWORK}/../bin:$PATH"
  export FABRIC_CFG_PATH="${FABRIC_NETWORK}/../config/"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID="Org1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="${FABRIC_NETWORK}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
  export CORE_PEER_MSPCONFIGPATH="${FABRIC_NETWORK}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
  export CORE_PEER_ADDRESS=localhost:7051

  QUERY_RESULT=$(peer chaincode query -C "$CHANNEL" -n "$CHAINCODE_NAME" \
    -c '{"function":"DCSContract:GetReputation","Args":["test-uav"]}' 2>/dev/null || echo "ERROR")
  [ "$QUERY_RESULT" != "ERROR" ] && ok "Chaincode deployed and responding ✓" || warn "Chaincode deploy may have issues — check $LOG_DIR/chaincode_deploy.log"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 4 — Start Hardhat Local Ethereum Node (background)
# ═══════════════════════════════════════════════════════════════
step "4 — Hardhat Local Ethereum Node"

if [ "$TESTS_ONLY" = true ]; then
  warn "Skipping Hardhat node startup (--tests-only mode)"
else
  cd "$BLOCKCHAIN_DIR"

  # Kill any existing Hardhat node
  pkill -f "hardhat node" 2>/dev/null || true
  sleep 1

  info "Starting Hardhat node in background..."
  npx hardhat node > "$LOG_DIR/hardhat_node.log" 2>&1 &
  HARDHAT_PID=$!
  echo "HARDHAT_PID=$HARDHAT_PID" >> "$PID_FILE"

  # Wait for node to be ready
  info "Waiting for Hardhat node to be ready..."
  for i in $(seq 1 15); do
    if curl -s -X POST http://127.0.0.1:8545 \
      -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      >/dev/null 2>&1; then
      ok "Hardhat node running (PID: $HARDHAT_PID) ✓"
      break
    fi
    sleep 1
    if [ $i -eq 15 ]; then
      fail "Hardhat node did not start in time. Check $LOG_DIR/hardhat_node.log"
    fi
  done
fi

# ═══════════════════════════════════════════════════════════════
# STEP 5 — Deploy Solidity Smart Contracts to Hardhat
# ═══════════════════════════════════════════════════════════════
step "5 — Deploy Solidity Contracts (SC-1 through SC-7)"

if [ "$SKIP_DEPLOY" = true ] || [ "$TESTS_ONLY" = true ]; then
  warn "Skipping contract deploy"
  [ -f "$BLOCKCHAIN_DIR/deployed-addresses.json" ] || fail "deployed-addresses.json not found. Run without --skip-deploy first."
  info "Using existing deployed-addresses.json"
else
  cd "$BLOCKCHAIN_DIR"

  info "Deploying all 7 contracts..."
  npx hardhat run scripts/deploy.js --network localhost \
    2>&1 | tee "$LOG_DIR/contract_deploy.log"

  [ -f "deployed-addresses.json" ] || fail "Deploy failed — deployed-addresses.json not created"
  ok "All 7 contracts deployed ✓"

  # Show deployed addresses
  echo ""
  cat deployed-addresses.json
  echo ""
fi

# ═══════════════════════════════════════════════════════════════
# STEP 6 — Start Oracle Bridge (background)
# ═══════════════════════════════════════════════════════════════
step "6 — Oracle Bridge (PDC → UOC)"

if [ "$TESTS_ONLY" = true ]; then
  warn "Skipping Oracle Bridge startup (--tests-only mode)"
else
  cd "$BLOCKCHAIN_DIR"

  [ -f "oracle/bridge.js" ] || fail "Oracle bridge not found at oracle/bridge.js"

  # Kill any existing bridge
  pkill -f "bridge.js" 2>/dev/null || true
  sleep 1

  info "Starting Oracle Bridge in background..."
  node oracle/bridge.js > "$LOG_DIR/oracle_bridge.log" 2>&1 &
  BRIDGE_PID=$!
  echo "BRIDGE_PID=$BRIDGE_PID" >> "$PID_FILE"
  sleep 2

  if kill -0 $BRIDGE_PID 2>/dev/null; then
    ok "Oracle Bridge running (PID: $BRIDGE_PID) ✓"
  else
    warn "Oracle Bridge may have crashed — check $LOG_DIR/oracle_bridge.log"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# STEP 7 — Run Hardhat Test Suite
# ═══════════════════════════════════════════════════════════════
step "7 — Hardhat Test Suite (Smart Contracts)"

cd "$BLOCKCHAIN_DIR"

info "Running all Hardhat tests..."
TEST_OUTPUT=$(npx hardhat test 2>&1 | tee "$LOG_DIR/hardhat_tests.log")
echo "$TEST_OUTPUT" | tail -20

# Extract pass/fail counts
PASSING=$(echo "$TEST_OUTPUT" | grep -oP '\d+ passing' | grep -oP '\d+' || echo "0")
FAILING=$(echo "$TEST_OUTPUT" | grep -oP '\d+ failing'  | grep -oP '\d+' || echo "0")

if [ "$FAILING" -eq 0 ] 2>/dev/null; then
  ok "Hardhat tests: $PASSING passing, $FAILING failing ✓"
else
  warn "Hardhat tests: $PASSING passing, $FAILING FAILING ← check $LOG_DIR/hardhat_tests.log"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 8 — Integration Test (end-to-end flow)
# ═══════════════════════════════════════════════════════════════
step "8 — End-to-End Integration Test"

if [ "$TESTS_ONLY" = false ]; then
  cd "$BLOCKCHAIN_DIR"

  info "Running full DCBA flow (deploy → register → prescribe → deliver)..."
  npx hardhat run scripts/test_flow.js --network localhost \
    2>&1 | tee "$LOG_DIR/integration_test.log"

  grep -q "Full DCBA flow completed successfully" "$LOG_DIR/integration_test.log" \
    && ok "Integration test passed ✓" \
    || warn "Integration test issues — check $LOG_DIR/integration_test.log"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 9 — Fabric Chaincode Live Tests (Bloom Filter + PARS)
# ═══════════════════════════════════════════════════════════════
step "9 — Fabric Chaincode Live Tests"

cd "$FABRIC_NETWORK"
export PATH="${FABRIC_NETWORK}/../bin:$PATH"
export FABRIC_CFG_PATH="${FABRIC_NETWORK}/../config/"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${FABRIC_NETWORK}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${FABRIC_NETWORK}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

TS=$(date +%s)
UAV_ID="uav-$TS"
ROUND_ID="round-$TS"
ORDER_ID="order-$TS"

INVOKE_BASE="peer chaincode invoke \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile ${FABRIC_NETWORK}/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem \
  -C $CHANNEL -n $CHAINCODE_NAME \
  --peerAddresses localhost:7051 \
  --tlsRootCertFiles ${FABRIC_NETWORK}/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
  --peerAddresses localhost:9051 \
  --tlsRootCertFiles ${FABRIC_NETWORK}/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

fabric_invoke() {
  $INVOKE_BASE -c "$1" 2>&1 | grep -v "^$" | tail -2
  sleep 3
}
fabric_query() {
  peer chaincode query -C "$CHANNEL" -n "$CHAINCODE_NAME" -c "$1" 2>/dev/null
}

echo ""
info "[Bloom Filter Test]"

info "  Adding $UAV_ID to Bloom filter..."
fabric_invoke "{\"function\":\"DCSContract:AddUAVToBloom\",\"Args\":[\"$UAV_ID\"]}"

BLOOM_RESULT=$(fabric_query "{\"function\":\"DCSContract:BloomCheck\",\"Args\":[\"$UAV_ID\"]}")
[ "$BLOOM_RESULT" = "true" ] \
  && ok "  Bloom filter check: $UAV_ID → true ✓" \
  || warn "  Bloom filter check returned: $BLOOM_RESULT"

info "  Opening DCS round $ROUND_ID..."
fabric_invoke "{\"function\":\"DCSContract:OpenRound\",\"Args\":[\"$ROUND_ID\",\"$ORDER_ID\"]}"

info "  Submitting score 82 (should pass both phases)..."
SUBMIT_OUTPUT=$(fabric_invoke "{\"function\":\"DCSContract:SubmitScore\",\"Args\":[\"$ROUND_ID\",\"$UAV_ID\",\"82\"]}" 2>&1)
echo "  $SUBMIT_OUTPUT"

info "  Closing round..."
fabric_invoke "{\"function\":\"DCSContract:CloseRound\",\"Args\":[\"$ROUND_ID\"]}"

WINNER=$(fabric_query "{\"function\":\"DCSContract:GetWinner\",\"Args\":[\"$ROUND_ID\"]}")
echo ""
info "  Winner result: $WINNER"
echo "$WINNER" | grep -q "$UAV_ID" \
  && ok "  DCS round winner correct ✓" \
  || warn "  Winner check: $WINNER"

echo ""
info "[PARS Priority Queue Test]"
info "  Submitting CRITICAL order (parsScore=95) and LOW order (parsScore=20)..."
fabric_invoke "{\"function\":\"OrdersContract:SubmitOrder\",\"Args\":[\"$ORDER_ID-low\",\"hp-001\",\"patient-001\",\"rx-001\",\"20\",\"Vitamins\",\"warehouse-001\",\"ds-001\"]}"
fabric_invoke "{\"function\":\"OrdersContract:SubmitOrder\",\"Args\":[\"$ORDER_ID-critical\",\"hp-001\",\"patient-001\",\"rx-002\",\"95\",\"Insulin\",\"warehouse-001\",\"ds-001\"]}"

PRIORITY=$(fabric_query "{\"function\":\"OrdersContract:GetHighestPriorityOrder\",\"Args\":[\"$ORDER_ID-low\",\"$ORDER_ID-critical\"]}" 2>/dev/null || echo "query_failed")
info "  Highest priority order: $PRIORITY"
echo "$PRIORITY" | grep -qi "critical\|95" \
  && ok "  PARS priority queue correct — CRITICAL dispatched first ✓" \
  || warn "  PARS result: $PRIORITY (check manually)"

# ═══════════════════════════════════════════════════════════════
# STEP 10 — DCS Scalability Benchmark (Python)
# ═══════════════════════════════════════════════════════════════
step "10 — DCS Scalability Benchmark"

cd "$BLOCKCHAIN_DIR"

if [ -f "simulation/fleet_sim.py" ]; then
  info "Running DCS fleet simulation (10, 25, 50, 75, 100 UAVs)..."
  python3 simulation/fleet_sim.py 2>&1 | tee "$LOG_DIR/dcs_benchmark.log"
  ok "DCS benchmark complete ✓"
else
  warn "simulation/fleet_sim.py not found — skipping"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 11 — Caliper Benchmark (optional)
# ═══════════════════════════════════════════════════════════════
step "11 — Hyperledger Caliper Benchmark"

if [ "$SKIP_CALIPER" = true ]; then
  warn "Skipping Caliper benchmark (--skip-caliper flag)"
elif [ -f "$BLOCKCHAIN_DIR/benchmark/benchmark.yaml" ]; then
  cd "$BLOCKCHAIN_DIR"
  info "Running Caliper benchmark (this takes ~2-3 minutes)..."
  npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig benchmark/network.yaml \
    --caliper-benchconfig benchmark/benchmark.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled \
    2>&1 | tee "$LOG_DIR/caliper.log" | grep -E "Throughput|Latency|pass|fail|Error|summary" || true
  ok "Caliper benchmark complete ✓"
else
  warn "benchmark/benchmark.yaml not found — skipping Caliper"
fi

# ═══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  DCBA Project — Startup Complete!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Hardhat node  :${NC} http://127.0.0.1:8545"
echo -e "  ${CYAN}Fabric channel:${NC} $CHANNEL"
echo -e "  ${CYAN}Chaincode     :${NC} $CHAINCODE_NAME v$CHAINCODE_VERSION"
echo -e "  ${CYAN}Addresses     :${NC} $BLOCKCHAIN_DIR/deployed-addresses.json"
echo ""
echo -e "  ${CYAN}Logs saved to :${NC} $LOG_DIR/"
ls "$LOG_DIR"/*.log 2>/dev/null | sed 's/^/    /'
echo ""
echo -e "  ${CYAN}Running processes:${NC}"
cat "$PID_FILE" 2>/dev/null | grep -v "^$" | sed 's/^/    /'
echo ""
echo -e "  To stop everything: ${YELLOW}bash stop_project.sh${NC}"
echo -e "  Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
