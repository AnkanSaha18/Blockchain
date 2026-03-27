#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# DCBA Project — Chaincode Integration Test Runner
# Runs from: ~/dcba/network/
# Targets:   Hyperledger Fabric test-network (fabric-samples)
# ─────────────────────────────────────────────────────────────────────────────

# Absolute path to this script's directory (dcba/network)
DCBA_NETWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
DCBA_ROOT="$(cd "$DCBA_NETWORK_DIR/.." && pwd)"

# Path to the Hyperledger Fabric test-network (adjust if yours differs)
FABRIC_TEST_NETWORK="${HOME}/fabric/fabric-samples/test-network"

if [ ! -d "$FABRIC_TEST_NETWORK" ]; then
  echo "ERROR: Fabric test-network not found at $FABRIC_TEST_NETWORK"
  echo "       Set FABRIC_TEST_NETWORK env var to override."
  exit 1
fi

# Chaincode source lives inside the DCBA project
CHAINCODE_PATH="${DCBA_ROOT}/Blockchain/chaincode/dcba-uoc"

# ── Unique IDs per run to avoid "already exists" collisions ──────────────────
TS=$(date +%s)
UAV_ID="uav-${TS}"
ROUND_ID="round-${TS}"
ORDER_ID="order-${TS}"

# ── Step 1: Deploy chaincode ──────────────────────────────────────────────────
echo "==> Deploying chaincode from: $CHAINCODE_PATH"
cd "$FABRIC_TEST_NETWORK"
./network.sh deployCC \
  -ccn dcba-uoc \
  -ccp "$CHAINCODE_PATH" \
  -ccl go \
  -c dcbachannel \
  -ccv 2.0

# ── Step 2: Set env for peer CLI ──────────────────────────────────────────────
export PATH="${FABRIC_TEST_NETWORK}/../bin:$PATH"
export FABRIC_CFG_PATH="${FABRIC_TEST_NETWORK}/../config/"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${FABRIC_TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${FABRIC_TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

ORDERER_ARGS="-o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls \
  --cafile ${FABRIC_TEST_NETWORK}/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem"

PEER_ARGS="-C dcbachannel -n dcba-uoc \
  --peerAddresses localhost:7051 \
  --tlsRootCertFiles ${FABRIC_TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
  --peerAddresses localhost:9051 \
  --tlsRootCertFiles ${FABRIC_TEST_NETWORK}/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

invoke() {
  peer chaincode invoke $ORDERER_ARGS $PEER_ARGS -c "$1"
  sleep 5   # wait for block commit
}

query() {
  peer chaincode query -C dcbachannel -n dcba-uoc -c "$1"
}

# ── Step 3: Run test flow ─────────────────────────────────────────────────────
echo "==> UAV: $UAV_ID  |  Round: $ROUND_ID"

echo "==> Adding UAV to Bloom filter..."
invoke "{\"function\":\"DCSContract:AddUAVToBloom\",\"Args\":[\"$UAV_ID\"]}"

echo "==> Checking Bloom filter (expect: true)..."
query "{\"function\":\"DCSContract:BloomCheck\",\"Args\":[\"$UAV_ID\"]}"

echo "==> Opening round..."
invoke "{\"function\":\"DCSContract:OpenRound\",\"Args\":[\"$ROUND_ID\",\"$ORDER_ID\"]}"

echo "==> Submitting score..."
invoke "{\"function\":\"DCSContract:SubmitScore\",\"Args\":[\"$ROUND_ID\",\"$UAV_ID\",\"82\"]}"

echo "==> Closing round..."
invoke "{\"function\":\"DCSContract:CloseRound\",\"Args\":[\"$ROUND_ID\"]}"

echo "==> Getting winner..."
query "{\"function\":\"DCSContract:GetWinner\",\"Args\":[\"$ROUND_ID\"]}"
