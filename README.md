# DCBA — Dual-Chain Blockchain Architecture for Drone-Based Medical Delivery

A hybrid blockchain system that combines **Ethereum smart contracts** (Patient Data Chain) and **Hyperledger Fabric chaincode** (UAV Operational Chain) to enable secure, privacy-preserving, and auditable drone delivery of medical supplies.

---

## Table of Contents

1. [PROJECT Overview](#1-project-overview)
2. [System Architecture](#2-system-architecture)
3. [Why Two Blockchains?](#3-why-two-blockchains)
4. [Patient Data Chain — Ethereum Smart Contracts](#4-patient-data-chain--ethereum-smart-contracts)
5. [UAV Operational Chain — Hyperledger Fabric Chaincode](#5-uav-operational-chain--hyperledger-fabric-chaincode)
6. [Cross-Chain Oracle Bridge](#6-cross-chain-oracle-bridge)
7. [End-to-End Medical Delivery Flow](#7-end-to-end-medical-delivery-flow)
8. [Directory Structure](#8-directory-structure)
9. [Prerequisites](#9-prerequisites)
10. [Setup & Deployment — Ethereum (PDC)](#10-setup--deployment--ethereum-pdc)
11. [Setup & Deployment — Hyperledger Fabric (UOC)](#11-setup--deployment--hyperledger-fabric-uoc)
12. [Running Benchmarks (Hyperledger Caliper)](#12-running-benchmarks-hyperledger-caliper)
13. [Smart Contract Reference](#13-smart-contract-reference)
14. [Chaincode Reference](#14-chaincode-reference)
15. [Security Design](#15-security-design)
16. [Gas Costs](#16-gas-costs)
17. [Known Issues & Bug Fixes](#17-known-issues--bug-fixes)

---

## 1. Project Overview

DCBA solves the problem of transporting urgent medical supplies (drugs, vaccines, blood) to patients using autonomous drones, while ensuring:

- **Patient privacy** — medical data is encrypted off-chain (IPFS); only hashes live on-chain
- **Regulatory auditability** — every GPS coordinate, status change, and access event is permanently recorded
- **Fair UAV selection** — drones compete transparently via a Drone Capability Score (DCS) system
- **SLA enforcement** — delivery deadlines are encoded on-chain based on medical urgency (PARS score)
- **Cross-chain integrity** — a prescription issued by a doctor on the medical chain can only trigger one delivery on the operational chain (replay-attack prevention)

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DCBA Dual-Chain Architecture                     │
│                                                                       │
│  ┌──────────────────────────────┐   SC7 Oracle   ┌────────────────── │
│  │   PDC — Patient Data Chain   │◄──────────────►│ UOC — UAV Ops    │
│  │   (Ethereum / EVM)           │   (Bridge)     │ Chain (Fabric)   │
│  │                              │                │                   │
│  │  SC1 Identity Registry       │                │  DCSContract      │
│  │  SC2 Patient Consent         │                │  (dcs_scoring.go) │
│  │  SC3 Medical Records         │                │                   │
│  │  SC4 DCS Scoring             │                │  LifecycleContract│
│  │  SC5 Delivery Orders         │                │  (delivery_       │
│  │  SC6 Delivery Lifecycle      │                │   lifecycle.go)   │
│  │  SC7 Oracle Bridge           │                │                   │
│  └──────────────────────────────┘                └───────────────────┘
│                                                                       │
│  Off-chain Storage: IPFS (encrypted medical data + GPS coordinates)   │
└─────────────────────────────────────────────────────────────────────┘
```

### Actors

| Actor | Role | Abbreviation |
|-------|------|-------------|
| Trusted Authority | Governs identity registry; registers/revokes all actors | TA |
| Healthcare Provider | Doctor/hospital; writes medical records, submits delivery orders | HP |
| Patient | Grants consent; confirms delivery | PAT |
| Warehouse | Confirms drug stock availability | WH |
| Drone Station | Runs DCS scoring rounds; assigns UAVs; creates deliveries | DS |
| UAV | Autonomous drone; competes for missions; logs GPS during flight | UAV |
| Regulatory Auditor | Read-only access to full audit trail | AUD |

---

## 3. Why Two Blockchains?

| Concern | Ethereum (PDC) | Hyperledger Fabric (UOC) |
|---------|---------------|--------------------------|
| **Privacy** | Patient consent gates all access | Permissioned — only registered orgs |
| **Data type** | Business logic, identity, consent | High-frequency operational data (GPS logs ~1/sec) |
| **Transaction volume** | Low (records, orders) | High (GPS, status updates) |
| **Finality** | Probabilistic (PoW/PoS) | Immediate (Raft/BFT consensus) |
| **Auditability** | Public, tamper-evident | Channel-scoped, org-controlled |

Ethereum handles the **trustless, public business logic** (who can deliver what, to whom, under what consent). Hyperledger Fabric handles the **high-throughput operational tracking** (live flight data, GPS streams) that would be prohibitively expensive on Ethereum.

---

## 4. Patient Data Chain — Ethereum Smart Contracts

Seven Solidity contracts deployed in strict dependency order:

### SC1 — Identity Registry (`SC1_IdentityRegistry.sol`)

**Purpose:** The root-of-trust for the entire system. Every other contract calls back to SC1 to verify actor identity before executing sensitive operations.

**How it works:**
- The Trusted Authority (TA) calls `register(address, role, name)` to onboard actors
- Seven roles: `PATIENT`, `HEALTHCARE_PROVIDER`, `UAV`, `WAREHOUSE`, `DRONE_STATION`, `AUDITOR`, `TA`
- `isActive(address)` and `getRole(address)` are read by SC2–SC6 before every state-changing call
- TA can `revoke(address)` to immediately remove a compromised actor's privileges
- TA role is transferable via `transferTA(newTA)`

**Why it's needed:** Without a shared identity layer, each contract would need its own allowlist. SC1 centralises this so revoking one actor instantly cuts their access across all contracts.

### SC2 — Patient Consent (`SC2_PatientConsent.sol`)

**Purpose:** Implements patient-controlled, time-limited access tokens for medical data. Doctors cannot write or read a patient's records without an active consent token.

**How it works:**
- Patient calls `grantAccess(hpAddress, duration)` where `duration = 0` means indefinite
- HP calls `hasAccess(patient, hp)` — SC3 checks this before writing any record
- Patient can `revokeAccess(hpAddress)` at any time
- `getConsentInfo()` returns the token's creation time, expiry, and active status

**Why it's needed:** Medical data is sensitive. This contract enforces GDPR-style "right to access" at the smart-contract level — not just UI-level gatekeeping.

### SC3 — Medical Records (`SC3_MedicalRecords.sol`)

**Purpose:** Permanent, tamper-evident storage of medical record metadata. Actual data lives on IPFS (encrypted); only the hash is stored on-chain.

**How it works:**
- HP calls `addRecord(patient, ipfsHash, pars, prescriptionHash)` — three checks run:
  1. HP is registered and active (SC1)
  2. HP has patient's consent (SC2)
  3. PARS score is 0–100 (valid urgency rating)
- After storing the record, SC3 automatically calls `SC7.registerHash(prescriptionHash)` to link it to the delivery chain
- `getRecord(recordId)` returns the IPFS hash, PARS score, author, and timestamp
- `getParsLabel(pars)` returns human-readable triage: `CRITICAL / HIGH / MODERATE / LOW`

**Why it's needed:** Provides an immutable audit trail of every medical record. Patients, auditors, and courts can verify that a record existed at a specific time without seeing the actual medical content.

### SC4 — DCS Scoring (`SC4_DCSScoring.sol`)

**Purpose:** A competitive scoring mechanism to select the best-capable UAV for each mission.

**How it works:**
- `computeScore(speed, payload, battery, cpu, ram)` calculates a weighted score:
  ```
  DCS = (speed×30 + payload×25 + battery×20 + cpu×15 + ram×10) / 100
  ```
- Drone Station calls `openRound(orderId)` to start a scoring window
- Each UAV calls `submitScore(roundId, dcsScore)` — one submission per UAV per round
- DS calls `closeRound(roundId)` — winner is the highest score
- Winner's address is returned and used for UAV assignment
- `updateReputation(uavId, delta)` accumulates lifetime performance (+1 per success, −1 per deviation or failure)

**Why it's needed:** Without a transparent scoring system, the DS could arbitrarily assign missions. On-chain scoring ensures the best-qualified UAV is always selected and the process is auditable.

### SC5 — Delivery Orders (`SC5_DeliveryOrders.sol`)

**Purpose:** The order management contract that bridges medical urgency to operational SLA.

**How it works:**
- HP calls `submitOrder(patient, prescriptionHash, pars)` — verifies prescription via SC7
- PARS score determines SLA deadline automatically:

| PARS Tier | Range | SLA Deadline |
|-----------|-------|-------------|
| CRITICAL  | 90–100 | 3 minutes |
| HIGH      | 70–89  | 10 minutes |
| MODERATE  | 40–69  | 30 minutes |
| LOW       | 0–39   | 2 hours |

- `confirmStock(orderId)` — Warehouse confirms drug availability
- `assignUAV(orderId, uavAddress)` — DS assigns the DCS winner
- `updateStatus(orderId, status)` — tracks order through: `PENDING → CONFIRMED → DISPATCHED → IN_FLIGHT → DELIVERED / FAILED`

**Why it's needed:** Encodes the urgency-to-deadline mapping on-chain, preventing human discretion from delaying critical deliveries. A CRITICAL order's 3-minute SLA cannot be silently extended.

### SC6 — Delivery Lifecycle (`SC6_DeliveryLifecycle.sol`)

**Purpose:** Real-time delivery tracking — from warehouse pickup to patient doorstep.

**How it works:**
- DS calls `createDelivery(orderId, uavId, patient, slaDeadline)`
- UAV calls `setInFlight(orderId)` when it takes off
- During flight, UAV calls `logGPS(orderId, ipfsHash)` roughly every second — the IPFS hash points to an encrypted GPS coordinate stored off-chain
- If route deviation is detected: `flagDeviation(orderId, reason)` — status → `DEVIATED`
- Patient calls `confirmDelivery(orderId)` — system checks if delivery was within SLA, then calls `SC4.updateReputation()` to reward the UAV (`+1`) or penalise a failed/deviated delivery (`−1`)

**Why it's needed:** Creates an indelible GPS audit trail. If a delivery fails, is tampered with, or deviates from approved airspace, the entire flight history is permanently on-chain for investigation.

### SC7 — Oracle Bridge (`SC7_OracleBridge.sol`)

**Purpose:** Cross-chain linking — prevents the same prescription from being used to order multiple deliveries (replay attack prevention).

**How it works:**
- When SC3 stores a medical record, it calls `SC7.registerHash(prescriptionHash)` → status: `PENDING`
- When SC5 processes a delivery order, it calls `SC7.verifyHash(prescriptionHash)` → status: `VALID` (one-time)
- After verification, the hash status changes to `USED` — any future attempt to reuse the same prescription is rejected
- `setSC3Address(sc3)` must be called after deployment to authorise SC3 as the only hash registrar

**Why it's needed:** Without this, a single doctor's prescription could be used to order unlimited deliveries (prescription fraud). The oracle bridge enforces a strict one-prescription → one-delivery mapping across both chains.

---

## 5. UAV Operational Chain — Hyperledger Fabric Chaincode

Go chaincode deployed to the `dcbachannel` Fabric channel as `dcba-uoc`. Contains two contracts that mirror the Ethereum SC4 and SC6 logic for high-throughput, low-latency operations.

### DCSContract (`dcs_scoring.go`)

Mirrors SC4 — manages scoring rounds and UAV reputation on Fabric.

| Function | Type | Description |
|----------|------|-------------|
| `OpenRound(roundID, orderID)` | Write | Creates a new scoring round on the ledger |
| `SubmitScore(roundID, uavID, score)` | Write | Records a UAV's score (0–100); rejects duplicates |
| `CloseRound(roundID)` | Write | Selects the highest-scoring UAV as winner |
| `GetWinner(roundID)` | Read | Returns winner address and score |
| `UpdateReputation(uavID, delta)` | Write | Adds/subtracts from a UAV's lifetime reputation |
| `GetReputation(uavID)` | Read | Returns current reputation score |

**Ledger keys:** `ROUND_{roundID}`, `REP_{uavID}`

### LifecycleContract (`delivery_lifecycle.go`)

Mirrors SC6 — tracks real-time delivery status and GPS logs on Fabric.

| Function | Type | Description |
|----------|------|-------------|
| `CreateDelivery(orderID, uavID, patient, slaDeadline)` | Write | Initialises delivery record |
| `SetInFlight(orderID)` | Write | Transitions status `DISPATCHED → IN_FLIGHT` |
| `LogGPS(orderID, ipfsHash)` | Write | Appends a GPS log entry (IPFS hash + timestamp) |
| `FlagDeviation(orderID, reason)` | Write | Marks delivery as `DEVIATED` |
| `ConfirmDelivery(orderID)` | Write | Marks `DELIVERED`, evaluates SLA compliance |
| `GetDelivery(orderID)` | Read | Returns full delivery record including GPS log array |

**Ledger keys:** `DEL_{orderID}`

**Delivery status flow:**
```
DISPATCHED → IN_FLIGHT → DELIVERED
                       ↘ DEVIATED
```

---

## 6. Cross-Chain Oracle Bridge

```
                  PDC (Ethereum)              UOC (Fabric)
                  ──────────────              ────────────
Doctor writes     SC3.addRecord()
  record    →     SC7.registerHash()   ──→   Hash marked PENDING
                  (hash: PENDING)

HP submits        SC5.submitOrder()
  order     →     SC7.verifyHash()     ──→   Hash marked USED
                  (hash: VALID → USED)       (cannot be reused)

DS opens          SC4.openRound()      ──→   DCSContract.OpenRound()
  DCS round →     SC4.closeRound()           DCSContract.CloseRound()

DS creates        SC6.createDelivery() ──→   LifecycleContract.CreateDelivery()
  delivery  →     SC6.logGPS()               LifecycleContract.LogGPS()
                  SC6.confirmDelivery()       LifecycleContract.ConfirmDelivery()
```

> The Fabric chaincode (UOC) mirrors the Ethereum contracts (PDC) for operational functions that need high throughput. SC7 is the trust anchor ensuring a medical record on PDC maps exactly once to a delivery on UOC.

---

## 7. End-to-End Medical Delivery Flow

```
Step 1 — Registration (one-time)
  TA.register(patient, PATIENT)
  TA.register(doctor, HEALTHCARE_PROVIDER)
  TA.register(warehouse, WAREHOUSE)
  TA.register(droneStation, DRONE_STATION)
  TA.register(uav1, UAV)
  TA.register(uav2, UAV)

Step 2 — Patient Consent
  patient → SC2.grantAccess(doctor, 7 days)

Step 3 — Medical Record
  doctor → SC3.addRecord(patient, ipfsHash, pars=95, prescriptionHash)
           └→ SC7.registerHash(prescriptionHash)   [cross-chain link]

Step 4 — Delivery Order
  doctor → SC5.submitOrder(patient, prescriptionHash, pars=95)
           └→ SC7.verifyHash(prescriptionHash)     [one-time use]
           └→ SLA = 3 minutes (CRITICAL tier)

Step 5 — Stock Confirmation
  warehouse → SC5.confirmStock(orderId)

Step 6 — DCS Scoring
  droneStation → SC4.openRound(orderId)      / DCSContract.OpenRound()
  uav1         → SC4.submitScore(roundId, 85) / DCSContract.SubmitScore()
  uav2         → SC4.submitScore(roundId, 92) / DCSContract.SubmitScore()
  droneStation → SC4.closeRound(roundId)      / DCSContract.CloseRound()
                 └→ winner = uav2 (score 92)

Step 7 — UAV Assignment
  droneStation → SC5.assignUAV(orderId, uav2)
  droneStation → SC6.createDelivery(orderId, uav2, patient, slaDeadline)
                 / LifecycleContract.CreateDelivery()

Step 8 — Flight
  uav2 → SC6.setInFlight(orderId)  / LifecycleContract.SetInFlight()
  uav2 → SC6.logGPS(orderId, Qm…)  / LifecycleContract.LogGPS()  [every ~1s]
  uav2 → SC6.logGPS(orderId, Qm…)
  ...

Step 9 — Delivery Confirmation
  patient → SC6.confirmDelivery(orderId)
            └→ withinSLA = (now ≤ slaDeadline)
            └→ SC4.updateReputation(uav2, +1)   / DCSContract.UpdateReputation()
```

---

## 8. Directory Structure

```
dcba/
├── README.md
├── package.json                        # Caliper benchmark dependencies (~/dcba)
│
├── Blockchain/                         # All blockchain code
│   ├── contracts/                      # Ethereum Solidity smart contracts
│   │   ├── SC1_IdentityRegistry.sol
│   │   ├── SC2_PatientConsent.sol
│   │   ├── SC3_MedicalRecords.sol
│   │   ├── SC4_DCSScoring.sol
│   │   ├── SC5_DeliveryOrders.sol
│   │   ├── SC6_DeliveryLifecycle.sol
│   │   └── SC7_OracleBridge.sol
│   │
│   ├── chaincode/
│   │   └── dcba-uoc/                   # Hyperledger Fabric Go chaincode
│   │       ├── main.go                 # Chaincode entry point
│   │       ├── dcs_scoring.go          # DCS scoring + reputation (mirrors SC4)
│   │       ├── delivery_lifecycle.go   # Delivery tracking + GPS (mirrors SC6)
│   │       ├── go.mod
│   │       └── vendor/                 # Vendored Go dependencies
│   │
│   ├── scripts/
│   │   ├── deploy.js                   # Hardhat deployment (all 7 contracts)
│   │   └── test_flow.js               # End-to-end workflow test
│   │
│   ├── network/                        # Hyperledger Fabric test network
│   │   ├── network.sh                  # Network up/down/deployCC
│   │   ├── organizations/              # Crypto material (generated)
│   │   └── scripts/                    # Channel, chaincode, env scripts
│   │
│   ├── benchmark/                      # Caliper benchmark (Blockchain workspace)
│   │   ├── network.yaml                # Fabric network config for Caliper
│   │   ├── benchmark.yaml              # Test rounds config
│   │   └── workload/
│   │       ├── dcs_submit.js           # DCS scoring workload
│   │       └── gps_log.js              # GPS logging workload
│   │
│   ├── test/                           # Hardhat test suites
│   │   ├── SC1.test.js … SC7.test.js
│   │   ├── Gas.test.js
│   │   └── Security.test.js
│   │
│   ├── hardhat.config.js               # Hardhat + Solidity config
│   ├── deployed-addresses.json         # Live contract addresses
│   ├── gas-report.txt                  # Gas usage report
│   ├── BUG_REPORT.md                   # Critical bug documentation
│   └── package.json                    # Node.js dependencies
│
└── benchmark/                          # Caliper benchmark (dcba workspace)
    ├── network.yaml                    # Fabric network config
    ├── benchmark.yaml                  # 3-round benchmark config
    ├── connection-org1.yaml            # Fabric CCP (peer/orderer endpoints)
    └── workloads/
        ├── dcs-scoring.js              # Full DCS round (open→score×3→close)
        ├── delivery-lifecycle.js       # Full delivery (create→fly→GPS→confirm)
        └── query-operations.js         # Read-only GetDelivery queries
```

---

## 9. Prerequisites

### Ethereum (PDC)
- Node.js ≥ 18
- npm ≥ 9
- [Hardhat](https://hardhat.org/) (installed via `npm install`)

### Hyperledger Fabric (UOC)
- Go ≥ 1.21
- Docker ≥ 25 (see note below)
- Hyperledger Fabric binaries v2.5+ in `~/fabric/fabric-samples/`
- `jq`, `curl`

> **Docker version note:** Docker 25+ uses BuildKit and containerd snapshotter by default, which breaks Fabric v2.5's legacy chaincode builder. A `/etc/docker/daemon.json` fix is required:
> ```json
> { "features": { "containerd-snapshotter": false } }
> ```
> Restart Docker after applying. See [Known Issues](#17-known-issues--bug-fixes).

### Benchmarking
- Node.js ≥ 18 (Caliper 0.7.1 recommends ≥ 22, but works on 20)
- Fabric network running with `dcbachannel`

---

## 10. Setup & Deployment — Ethereum (PDC)

```bash
cd ~/dcba/Blockchain

# Install dependencies
npm install

# Start local Hardhat node
npx hardhat node

# Deploy all 7 contracts (in another terminal)
npx hardhat run scripts/deploy.js --network localhost

# Run test suite
npx hardhat test

# Run end-to-end flow test
npx hardhat run scripts/test_flow.js --network localhost

# Check gas costs
cat gas-report.txt
```

Deployed contract addresses are saved to `deployed-addresses.json`.

### Critical deployment steps (handled by deploy.js)

After deploying all 7 contracts, two linking calls **must** be made or the system will fail:

```javascript
// Step 5 — Link SC7 → SC3 (so SC3 can register prescription hashes)
await SC7.setSC3Address(SC3.address);

// Step 9 — Link SC4 → SC6 (so SC6 can update UAV reputation)
await SC4.linkSC6(SC6.address);
```

---

## 11. Setup & Deployment — Hyperledger Fabric (UOC)

```bash
# Start Fabric test network with dcbachannel
cd ~/fabric/fabric-samples/test-network
./network.sh up createChannel -c dcbachannel -ca

# Pull required chaincode builder images
docker pull hyperledger/fabric-ccenv:3.1
docker pull hyperledger/fabric-baseos:3.1

# Deploy dcba-uoc chaincode
./network.sh deployCC \
  -ccn dcba-uoc \
  -ccp ~/dcba/Blockchain/chaincode/dcba-uoc \
  -ccl go \
  -c dcbachannel

# Tear down network
./network.sh down
```

Expected output on success:
```
Chaincode is installed on peer0.org1  ✓
Chaincode is installed on peer0.org2  ✓
Chaincode definition committed on channel 'dcbachannel'  ✓
Approvals: [Org1MSP: true, Org2MSP: true]  ✓
```

---

## 12. Running Benchmarks (Hyperledger Caliper)

Two benchmark workspaces are available. Both test the same Fabric chaincode but with different workload scenarios.

### Option A — From `~/dcba` (3 rounds)

```bash
cd ~/dcba

# Install Caliper dependencies (first time only)
npm install
npx caliper bind --caliper-bind-sut fabric:fabric-gateway

# Run benchmark
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig benchmark/network.yaml \
  --caliper-benchconfig benchmark/benchmark.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled
```

**Rounds:**
| Round | Operations | TPS | Transactions |
|-------|-----------|-----|-------------|
| open-and-score-round | OpenRound + SubmitScore×3 + CloseRound | 5 | 50 |
| delivery-lifecycle | CreateDelivery + SetInFlight + LogGPS + ConfirmDelivery | 5 | 50 |
| query-winner | GetDelivery (read-only) | 20 | 100 |

### Option B — From `~/dcba/Blockchain` (2 rounds, original workloads)

```bash
cd ~/dcba/Blockchain

# Install Caliper dependencies (first time only)
npm install
npx caliper bind --caliper-bind-sut fabric:fabric-gateway

# Run benchmark
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig benchmark/network.yaml \
  --caliper-benchconfig benchmark/benchmark.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled
```

**Rounds:**
| Round | Operations | TPS | Transactions |
|-------|-----------|-----|-------------|
| DCS-Score-Submission | OpenRound + SubmitScore + CloseRound | 5 | 50 |
| GPS-Log-Throughput | CreateDelivery + SetInFlight + LogGPS | 5 | 50 |

An HTML benchmark report is generated at `report.html` in the workspace directory after each run.

### Typical Benchmark Results

```
+----------------------+------+------+-----------------+-----------------+------------------+
| Name                 | Succ | Fail | Send Rate (TPS) | Avg Latency (s) | Throughput (TPS) |
|----------------------|------|------|-----------------|-----------------|------------------|
| open-and-score-round | 80   | 0    | 7.3             | 1.18            | 5.9              |
| delivery-lifecycle   | 64   | 0    | 5.4             | 1.31            | 4.4              |
| query-winner         | 100  | 0    | 20.4            | 0.00            | 20.4             |
+----------------------+------+------+-----------------+-----------------+------------------+
```

---

## 13. Smart Contract Reference

### Contract Dependency Graph

```
SC1_IdentityRegistry  (no deps — deploy first)
        ▲
        │ isActive(), getRole()
  ┌─────┼──────────────┐
  │     │              │
SC2   SC3            SC4   SC7 (no deps — deploy second)
      │                     ▲
      └──► SC7.registerHash()│
                            │setSC3Address()
SC5 ──► SC7.verifyHash()    │
SC6 ──► SC4.updateReputation()
```

### Function Quick Reference

**SC1 — Identity Registry**
```solidity
register(address actor, Role role, string name)   // TA only
revoke(address actor)                             // TA only
isActive(address actor) → bool
getRole(address actor) → Role
transferTA(address newTA)                         // TA only
```

**SC2 — Patient Consent**
```solidity
grantAccess(address hp, uint256 duration)         // Patient only
revokeAccess(address hp)                          // Patient only
hasAccess(address patient, address hp) → bool
getConsentInfo(address patient, address hp) → (...)
```

**SC3 — Medical Records**
```solidity
addRecord(address patient, string ipfsHash, uint8 pars, bytes32 prescriptionHash)
getRecord(uint256 recordId) → Record
getPatientRecordIds(address patient) → uint256[]
getParsLabel(uint8 pars) → string   // "CRITICAL" | "HIGH" | "MODERATE" | "LOW"
```

**SC4 — DCS Scoring**
```solidity
computeScore(uint8 speed, uint8 payload, uint8 battery, uint8 cpu, uint8 ram) → uint8
openRound(uint256 orderId) → bytes32
submitScore(bytes32 roundId, uint8 score)
closeRound(bytes32 roundId) → address winner
getWinner(bytes32 roundId) → address
updateReputation(address uav, int256 delta)        // SC6 or DS only
linkSC6(address sc6)                               // TA only — call after deployment
```

**SC5 — Delivery Orders**
```solidity
submitOrder(address patient, bytes32 prescriptionHash, uint8 pars) → uint256
confirmStock(uint256 orderId)                      // Warehouse only
assignUAV(uint256 orderId, address uav)            // Drone Station only
updateStatus(uint256 orderId, OrderStatus status)
getOrder(uint256 orderId) → Order
getSLASeconds(uint8 pars) → uint256
```

**SC6 — Delivery Lifecycle**
```solidity
createDelivery(uint256 orderId, address uav, address patient, uint256 slaDeadline)
setInFlight(uint256 orderId)
logGPS(uint256 orderId, string ipfsHash)
flagDeviation(uint256 orderId, string reason)
confirmDelivery(uint256 orderId)                   // Patient only
getDeliveryStatus(uint256 orderId) → DeliveryStatus
getGPSLog(uint256 orderId) → GPSEntry[]
```

**SC7 — Oracle Bridge**
```solidity
setSC3Address(address sc3)                         // TA only — call after SC3 deployment
registerHash(bytes32 hash)                         // SC3 only
verifyHash(bytes32 hash) → bool                    // SC5 only (marks as USED)
checkHash(bytes32 hash) → HashStatus
```

---

## 14. Chaincode Reference

### Invoke examples using Fabric CLI

```bash
# Set environment for Org1
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_ADDRESS=localhost:7051
export FABRIC_CFG_PATH=$PWD/../config/
# (set TLS cert paths as appropriate)

# Open a DCS scoring round
peer chaincode invoke -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:OpenRound","Args":["round-001","order-001"]}'

# Submit a UAV score
peer chaincode invoke -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:SubmitScore","Args":["round-001","uav-001","88"]}'

# Close the round
peer chaincode invoke -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:CloseRound","Args":["round-001"]}'

# Query the winner
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:GetWinner","Args":["round-001"]}'

# Create a delivery
peer chaincode invoke -C dcbachannel -n dcba-uoc \
  -c '{"function":"LifecycleContract:CreateDelivery","Args":["order-001","uav-001","patient-001","9999999999"]}'

# Log a GPS coordinate
peer chaincode invoke -C dcbachannel -n dcba-uoc \
  -c '{"function":"LifecycleContract:LogGPS","Args":["order-001","QmXxyz..."]}'

# Get full delivery record
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"LifecycleContract:GetDelivery","Args":["order-001"]}'
```

---

## 15. Security Design

### Threat Model & Mitigations

| Threat | Mitigation |
|--------|-----------|
| Unauthorised medical record write | SC2 consent check + SC1 role check in SC3 |
| Prescription replay (order same medication twice) | SC7 marks hash as `USED` after first verification |
| Rogue UAV submitting GPS after landing | SC6 rejects `logGPS` unless status is `IN_FLIGHT` |
| DS assigning a preferred UAV without scoring | SC4 on-chain scoring; winner selection is deterministic and public |
| Compromised actor | SC1 `revoke()` immediately blocks all contract interactions |
| Medical data exposure | Raw data stored encrypted on IPFS; only hash stored on-chain |
| UAV impersonation | SC1 identity check on every state-changing call |
| Duplicate UAV score submission | SC4 tracks submitted UAVs per round; rejects duplicates |

### MVCC Conflict Prevention (Fabric)

Fabric uses optimistic concurrency (MVCC). If two transactions read and write the same ledger key simultaneously, the second one is rejected (status 11 = `MVCC_READ_CONFLICT`). The chaincode workloads prevent this by assigning a unique ledger key per transaction:

```javascript
// Each transaction uses its own unique roundId/orderId
const roundId = `r-${workerIndex}-${txCounter}-${Date.now()}`;
```

---

## 16. Gas Costs

All costs measured on a local Hardhat network (Solidity 0.8.20, optimizer 200 runs).

### Deployment Costs

| Contract | Gas Used | % of Block Limit |
|----------|---------|-----------------|
| SC1_IdentityRegistry | 660,784 | 1.1% |
| SC2_PatientConsent | 429,015 | 0.7% |
| SC3_MedicalRecords | 873,476 | 1.5% |
| SC4_DCSScoring | 997,739 | 1.7% |
| SC5_DeliveryOrders | 1,375,158 | 2.3% |
| SC6_DeliveryLifecycle | 1,328,993 | 2.2% |
| SC7_OracleBridge | 383,565 | 0.6% |
| **Total** | **6,048,730** | **~10.1%** |

### Key Function Costs

| Function | Gas (avg) | Notes |
|----------|----------|-------|
| SC5.submitOrder | 369,576 | Most expensive — calls SC7 + stores order |
| SC3.addRecord | 321,488 | Calls SC7.registerHash + stores IPFS hash |
| SC4.submitScore | 185,111 | Updates round state |
| SC6.createDelivery | 176,952 | Initialises delivery record |
| SC4.openRound | ~120,000 | Creates round state |
| SC6.logGPS | ~90,000 | Appends to GPS array |
| SC1.register | ~80,000 | Stores actor identity |
| SC2.grantAccess | ~60,000 | Stores consent token |

---

## 17. Known Issues & Bug Fixes

### Bug 1 — CRITICAL: SC4.updateReputation fails when called from SC6

**Problem:** SC6 calls `SC4.updateReputation()` after delivery confirmation. Inside SC4, `msg.sender` is the SC6 contract address. SC4 checks `SC1.isActive(msg.sender)` — but SC6 is a contract, not a registered actor → reverts every time.

**Fix applied:** Added `sc6Address` storage and `linkSC6(address)` function to SC4. Reputation update now accepts calls from either a registered actor OR the linked SC6 address:
```solidity
require(sc1.isActive(msg.sender) || msg.sender == sc6Address, "Not authorised");
```

**Action required at deployment:** Call `SC4.linkSC6(SC6_address)` after both contracts are deployed (handled in `deploy.js` step 9).

---

### Bug 2 — CRITICAL: SC7.registerHash reverts (missing setSC3Address)

**Problem:** SC7 initialises `sc3Address = address(0)`. SC7.registerHash() checks `msg.sender == sc3Address`, which is always false until `setSC3Address()` is called. Every `SC3.addRecord()` call fails silently.

**Fix applied:** `setSC3Address(address)` already exists in SC7. The fix is a deployment procedure change — it must be called between SC3 and SC4 deployment.

**Action required at deployment:** Call `SC7.setSC3Address(SC3_address)` immediately after SC3 is deployed (handled in `deploy.js` step 5).

---

### Bug 3 — Docker 25+ breaks Fabric chaincode installation

**Problem:** Docker 23+ enables BuildKit and containerd snapshotter by default. Hyperledger Fabric v2.5's peer uses the legacy Docker build API which fails with `write unix @->/run/docker.sock: write: broken pipe`.

**Fix applied:** Create `/etc/docker/daemon.json`:
```json
{ "features": { "containerd-snapshotter": false } }
```
Restart Docker daemon after applying.

---

### Bug 4 — Fabric peer image version mismatch

**Problem:** After Docker restart, `fabric-peer:latest` pulls v3.1.4, but the local Fabric binaries are v2.5.0. The peer container looks for `hyperledger/fabric-ccenv:3.1` which doesn't exist locally.

**Fix applied:**
```bash
docker pull hyperledger/fabric-ccenv:3.1
docker pull hyperledger/fabric-baseos:3.1
```

---

### Bug 5 — MVCC conflicts in Caliper workloads

**Problem:** Original workload scripts created one shared round/delivery per worker and submitted many transactions to it concurrently. Fabric's MVCC rejected concurrent writes to the same ledger key (status code 11).

**Fix applied:** Each `submitTransaction()` call now creates a new unique key using `workerIndex + txCounter + timestamp`, so no two concurrent transactions share a state key.

---

## Deployed Contract Addresses (Localhost)

```json
{
  "SC1": "0x0B306BF915C4d645ff596e518fAf3F9669b97016",
  "SC2": "0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE",
  "SC3": "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
  "SC4": "0xc6e7DF5E7b4f2A278906862b61205850344D4e7d",
  "SC5": "0x59b670e9fA9D0A427751Af201D676719a970857b",
  "SC6": "0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1",
  "SC7": "0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1"
}
```

> These addresses are valid for the local Hardhat network only. Re-deploying generates new addresses.
