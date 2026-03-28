# DCBA — Dual-Chain Blockchain Architecture for Drone-Based Medical Delivery

A hybrid blockchain system that combines **Ethereum smart contracts** (Patient Data Chain) and **Hyperledger Fabric chaincode** (UAV Operational Chain) to enable secure, privacy-preserving, and auditable drone delivery of medical supplies.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [System Architecture](#2-system-architecture)
3. [Why Two Blockchains?](#3-why-two-blockchains)
4. [PDC — Patient Data Chain (SC1, SC2, SC3)](#4-pdc--patient-data-chain-sc1-sc2-sc3)
5. [UOC — UAV Operational Chain (SC4, SC5, SC6)](#5-uoc--uav-operational-chain-sc4-sc5-sc6)
6. [SC7 — Cross-Chain Oracle Bridge (Shared)](#6-sc7--cross-chain-oracle-bridge-shared)
7. [Hyperledger Fabric Chaincode (UOC)](#7-hyperledger-fabric-chaincode-uoc)
8. [UAV Fleet Simulation](#8-uav-fleet-simulation)
9. [End-to-End Medical Delivery Flow](#9-end-to-end-medical-delivery-flow)
10. [Directory Structure](#10-directory-structure)
11. [Prerequisites](#11-prerequisites)
12. [Setup &amp; Deployment — Ethereum (PDC)](#12-setup--deployment--ethereum-pdc)
13. [Setup &amp; Deployment — Hyperledger Fabric (UOC)](#13-setup--deployment--hyperledger-fabric-uoc)
14. [Running the Oracle Bridge](#14-running-the-oracle-bridge)
15. [Running Benchmarks (Hyperledger Caliper)](#15-running-benchmarks-hyperledger-caliper)
16. [Smart Contract Reference](#16-smart-contract-reference)
17. [Chaincode Reference](#17-chaincode-reference)
18. [Security Design](#18-security-design)
19. [Gas Costs](#19-gas-costs)
20. [Known Issues &amp; Bug Fixes](#20-known-issues--bug-fixes)

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
┌───────────────────────────────────────────────────────────────────────────┐
│                        DCBA Dual-Chain Architecture                       │
│                                                                           │
│  ┌─────────────────────────────┐   SC7 Oracle   ┌───────────────────────┐ │
│  │  PDC — Patient Data Chain   │◄──────────────►│ UOC — UAV Ops Chain   │ │
│  │  (Ethereum / PoA)           │  (Shared Relay) │ (Hyperledger Fabric) │ │
│  │                             │                 │                      │ │
│  │  SC1 Identity Registry ─────┼─────────────────► SC1 (also on UOC)    │ │
│  │  SC2 Patient Consent        │                 │  SC4 DCS Scoring     │ │
│  │  SC3 Medical Records        │                 │  SC5 Delivery Orders │ │
│  │                             │                 │  SC6 Delivery        │ │
│  │  SC7 Oracle Bridge ─────────┼──── relay ─────►│      Lifecycle       │ │
│  │  (rxHash: VALID → USED)     │                 │                      │ │
│  └─────────────────────────────┘                 │  DCSContract (Go)    │ │
│                                                  │  LifecycleContract   │ │
│                                                  │  (Go)                │ │
│                                                  └──────────────────────┘ │
│                                                                           │
│  Off-chain Storage: IPFS (encrypted medical data + GPS coordinates)       │
│  Off-chain Relay:   oracle/bridge.js (event listener + latency ~5.4s)     │
└───────────────────────────────────────────────────────────────────────────┘
```

### Contract-to-Chain Assignment (from research report Table 4.2)

| Contract                  | Chain                             | Reason                                                       |
| ------------------------- | --------------------------------- | ------------------------------------------------------------ |
| SC1 — Identity Registry  | **Both** (PDC + UOC)        | Every contract on both chains needs identity verification    |
| SC2 — Patient Consent    | **PDC**                     | Patient data sovereignty; consent is a medical-layer concern |
| SC3 — Medical Records    | **PDC**                     | Sensitive health data; governed by patient consent           |
| SC4 — DCS Scoring        | **UOC**                     | Operational; high-frequency UAV competition rounds           |
| SC5 — Delivery Orders    | **UOC**                     | Operational coordinator; PARS queue and SLA management       |
| SC6 — Delivery Lifecycle | **UOC**                     | High-frequency GPS logging (~1 tx/sec)                       |
| SC7 — Oracle Bridge      | **Shared** (PDC→UOC relay) | Bridges prescription verification from PDC to UOC            |

> **Implementation note:** All 7 Solidity contracts are deployed on a single Ethereum network for the demo (Hardhat). In the full production system, SC4/SC5/SC6 would run on Hyperledger Fabric (UOC). The Fabric chaincode (`DCSContract`, `LifecycleContract`) represents the UOC implementation of SC4 and SC6. SC7 comment in the code explicitly states: *"For Remix/testnet demo, both live on one chain."*

### Actors

The system is governed by **eight principal actors**. Seven are application-layer participants registered in SC1; one (Miner/Validator) operates at the consensus/infrastructure layer.

| # | Actor               | Role                                                                           | Abbrev. | SC1 Role String                        |  Registered in SC1  |
| - | ------------------- | ------------------------------------------------------------------------------ | ------- | -------------------------------------- | :-----------------: |
| 1 | Trusted Authority   | Governs identity registry; registers/revokes all actors; deploys all contracts | TA      | (deployer — becomes TA automatically) |      Implicit      |
| 2 | Healthcare Provider | Doctor/hospital; writes medical records, submits delivery orders               | HP      | `"hp"`                               |         Yes         |
| 3 | Patient             | Grants/revokes consent; confirms delivery receipt                              | PAT     | `"patient"`                          |         Yes         |
| 4 | Drug Warehouse      | Confirms drug stock availability; hands package to UAV                         | WH      | `"warehouse"`                        |         Yes         |
| 5 | Drone Station       | Runs DCS scoring rounds; assigns UAVs; monitors flight; flags deviations       | DS      | `"dronestation"`                     |         Yes         |
| 6 | UAV                 | Autonomous drone; competes via DCS scoring; logs GPS during flight             | UAV     | `"uav"`                              |         Yes         |
| 7 | Regulatory Auditor  | Read-only access to full audit trail; generates compliance reports             | AUD     | `"auditor"`                          |         Yes         |
| 8 | Miner / Validator   | Validates blocks on PDC (PoA); endorses transactions on UOC (Fabric Raft)      | MV      | —                                     | Infrastructure only |

> **Miner/Validator** is an infrastructure participant. On the PDC they run the Ethereum Proof-of-Authority validator nodes. On the UOC they form the Hyperledger Fabric Raft ordering service and peer endorsers. They are not registered in SC1 as application actors — their cryptographic participation is required at the consensus layer for every block to be finalised on both chains.

---

## 3. Why Two Blockchains?

| Concern                      | Ethereum PDC                      | Hyperledger Fabric UOC                       |
| ---------------------------- | --------------------------------- | -------------------------------------------- |
| **Privacy**            | Patient consent gates all access  | Permissioned — only registered orgs         |
| **Data type**          | Business logic, identity, consent | High-frequency operational data (GPS ~1/sec) |
| **Transaction volume** | Low (records, orders)             | High (GPS logs, status updates)              |
| **Finality**           | Probabilistic (PoA)               | Immediate (Raft/BFT consensus)               |
| **Auditability**       | Public, tamper-evident            | Channel-scoped, org-controlled               |

Ethereum handles the **trustless, public business logic** (who can deliver what, to whom, under what consent). Hyperledger Fabric handles the **high-throughput operational tracking** (live flight data, GPS streams) that would be prohibitively expensive on Ethereum.

---

## 4. PDC — Patient Data Chain (SC1, SC2, SC3)

Three contracts live on the **Patient Data Chain (Ethereum PoA)**. These handle identity, patient consent, and medical records — data that demands strong privacy and patient sovereignty.

> SC1 is also deployed identically on the UOC, since every UOC contract needs identity verification too.

### SC1 — Identity Registry (`SC1_IdentityRegistry.sol`) — PDC + UOC

**Purpose:** The root-of-trust for the entire system. Every other contract calls back to SC1 to verify actor identity before executing sensitive operations.

**How it works:**

- The Trusted Authority (TA) calls `register(address, role, publicKeyHash)` to onboard actors — role is a plain string (e.g., `"patient"`, `"hp"`, `"uav"`)
- `isActive(address)` and `getRole(address)` are called by SC2–SC6 before every state-changing operation
- TA can `revoke(address, reason)` to immediately remove a compromised actor's privileges across all contracts
- TA role is transferable via `transferTA(newTA)`

**Why it's needed:** Without a shared identity layer, each contract would need its own allowlist. SC1 centralises this so revoking one actor instantly cuts their access across all seven contracts.

### SC2 — Patient Consent (`SC2_PatientConsent.sol`) — PDC only

**Purpose:** Implements patient-controlled, time-limited access tokens for medical data. Doctors cannot write a patient's records without an active consent token.

**How it works:**

- Patient calls `grantAccess(hpAddress, durationDays)` where `durationDays = 0` means indefinite
- SC3 calls `hasAccess(hp, patient)` before writing any record
- Patient can `revokeAccess(hpAddress)` at any time
- `getConsentInfo()` returns the token's creation time, expiry, and active status

**Why it's needed:** Medical data is sensitive. This contract enforces GDPR-style "right to access" at the smart-contract level — not just UI-level gatekeeping.

### SC3 — Medical Records (`SC3_MedicalRecords.sol`) — PDC only

**Purpose:** Permanent, tamper-evident storage of medical record metadata. Actual data lives on IPFS (encrypted); only the hash is stored on-chain.

**How it works:**

- HP calls `addRecord(patient, encryptedDataHash, parsScore, rxHash)` — four checks run:
  1. HP is registered and active (SC1)
  2. HP has patient's consent (SC2)
  3. PARS score is 0–100 (valid urgency rating)
  4. `rxHash` is not empty (`bytes32(0)`)
- After storing the record, SC3 automatically calls `SC7.registerHash(rxHash)` — the prescription hash becomes **VALID** in the oracle, enabling it to be used for exactly one delivery order
- `getRecord(recordId)` returns the IPFS hash, PARS score, author, and timestamp
- `getParsLabel(pars)` returns human-readable triage: `CRITICAL / HIGH / MODERATE / LOW`

**Why it's needed:** Provides an immutable audit trail of every medical record. Patients, auditors, and courts can verify that a record existed at a specific time without seeing the actual medical content.

---

## 5. UOC — UAV Operational Chain (SC4, SC5, SC6)

Three contracts live on the **UAV Operational Chain (Hyperledger Fabric)**. These handle high-frequency operational logic — UAV selection, order management, and live delivery tracking. In the demo, they run as Solidity on Ethereum; in production they run on Fabric (with DCSContract and LifecycleContract as the Fabric implementations of SC4 and SC6).

### SC4 — DCS Scoring (`SC4_DCSScoring.sol`) — UOC

**Purpose:** A competitive scoring mechanism to select the best-capable UAV for each mission.

**How it works:**

- `computeScore(speed, payload, battery, cpu, ram)` calculates a weighted score:
  ```
  DCS = (speed×30 + payload×25 + battery×20 + cpu×15 + ram×10) / 100
  ```

  All inputs are 0–100; weights sum to 100; output is a normalised score in [0, 100].
- Drone Station calls `openRound(orderId)` to start a scoring window — returns a `uint256 roundId`
- Each UAV calls `submitScore(roundId, dcsScore)` — one submission per UAV per round; duplicates rejected
- DS calls `closeRound(roundId)` — winner is the highest-scoring UAV
- `getWinner(roundId)` returns `(address winner, uint256 score)`
- `updateReputation(uavAddress, delta)` accumulates lifetime performance:
  - **+5** for on-time delivery (called by SC6 on `confirmDelivery`)
  - **−5** for late delivery (called by SC6 on `confirmDelivery`)
  - **−10** for route deviation (called by SC6 on `flagDeviation`)
- `linkSC6(sc6Address)` — TA authorises SC6 to call `updateReputation` (required after deployment; see Bug 1)

**Why it's needed:** Without a transparent scoring system, the DS could arbitrarily assign missions. On-chain scoring ensures the best-qualified UAV is always selected and the process is auditable.

### SC5 — Delivery Orders (`SC5_DeliveryOrders.sol`) — UOC

**Purpose:** The order management contract that bridges medical urgency to operational SLA.

**How it works:**

- HP calls `submitOrder(patient, rxHash, parsScore, drugList, warehouse, droneStation)` — verifies prescription via SC7 in the same transaction
- PARS score determines SLA deadline automatically:

| PARS Tier | Range   | SLA Deadline |
| --------- | ------- | ------------ |
| CRITICAL  | 90–100 | 3 minutes    |
| HIGH      | 70–89  | 10 minutes   |
| MODERATE  | 40–69  | 30 minutes   |
| LOW       | 0–39   | 2 hours      |

- `confirmStock(orderId)` — Warehouse confirms drug availability (`PENDING → CONFIRMED`)
- `assignUAV(orderId, uavAddress)` — DS assigns the DCS winner (`CONFIRMED → DISPATCHED`)
- `updateStatus(orderId, status)` — tracks order through: `PENDING → CONFIRMED → DISPATCHED → IN_FLIGHT → DELIVERED / FAILED`

**Why it's needed:** Encodes the urgency-to-deadline mapping on-chain, preventing human discretion from delaying critical deliveries. A CRITICAL order's 3-minute SLA cannot be silently extended.

### SC6 — Delivery Lifecycle (`SC6_DeliveryLifecycle.sol`) — UOC

**Purpose:** Real-time delivery tracking — from warehouse pickup to patient doorstep.

**How it works:**

- DS calls `createDelivery(orderId, uavAddress, patient, slaDeadline)`
- UAV calls `setInFlight(orderId)` when it takes off (`DISPATCHED → IN_FLIGHT`)
- During flight, UAV calls `logGPS(orderId, ipfsHash)` roughly every second — the IPFS hash points to an encrypted GPS coordinate stored off-chain
- If route deviation is detected: DS calls `flagDeviation(orderId, reason)` — status → `DEVIATED`, UAV reputation **−10**
- Patient calls `confirmDelivery(orderId)` — system checks SLA compliance and calls `SC4.updateReputation()`:
  - **+5** if delivered within SLA deadline
  - **−5** if delivered late

**Why it's needed:** Creates an indelible GPS audit trail. If a delivery fails, is tampered with, or deviates from approved airspace, the entire flight history is permanently on-chain for investigation.

---

## 6. SC7 — Cross-Chain Oracle Bridge (Shared)

SC7 sits between both chains — it is deployed on the PDC (Ethereum) but its data is consumed by the UOC (Fabric/SC5). It is the only point of communication between the two chains.

### SC7 — Oracle Bridge (`SC7_OracleBridge.sol`) — Shared (PDC→UOC relay)

**Purpose:** Cross-chain linking — prevents the same prescription from being used to order multiple deliveries (replay attack prevention).

**Hash lifecycle:**

```
PENDING  →  VALID  →  USED
(initial)   (SC3)     (SC5)
```

**How it works:**

- Every prescription hash starts as **PENDING** (not yet known to SC7)
- When SC3 stores a medical record, it calls `SC7.registerHash(rxHash)` → hash becomes **VALID**
- When SC5 processes a delivery order, it calls `SC7.verifyHash(rxHash)` → hash is consumed and becomes **USED** (one-time)
- Any future attempt to reuse a `USED` hash is rejected — `verifyHash()` returns `false`
- `setSC3Address(sc3)` must be called by TA after SC3 deployment to authorise SC3 as the only hash registrar (see Bug 2)

**Why it's needed:** Without this, a single prescription could be used to order unlimited deliveries (prescription fraud). The oracle bridge enforces a strict one-prescription → one-delivery mapping across both chains.

---

## 7. Hyperledger Fabric Chaincode (UOC)

Go chaincode deployed to the `dcbachannel` Fabric channel as `dcba-uoc`. Implements the UOC operational side — mirrors SC4 (DCS Scoring) and SC6 (Delivery Lifecycle) for high-throughput, low-latency operations on Fabric.

### DCSContract (`dcs_scoring.go`)

Mirrors SC4 — manages scoring rounds and UAV reputation on Fabric.

| Function                               | Type  | Description                                        |
| -------------------------------------- | ----- | -------------------------------------------------- |
| `OpenRound(roundID, orderID)`        | Write | Creates a new scoring round on the ledger          |
| `SubmitScore(roundID, uavID, score)` | Write | Records a UAV's score (0–100); rejects duplicates |
| `CloseRound(roundID)`                | Write | Selects the highest-scoring UAV as winner          |
| `GetWinner(roundID)`                 | Read  | Returns winner address and score                   |
| `UpdateReputation(uavID, delta)`     | Write | Adds/subtracts from a UAV's lifetime reputation    |
| `GetReputation(uavID)`               | Read  | Returns current reputation score                   |

**Ledger keys:** `ROUND_{roundID}`, `REP_{uavID}`

### LifecycleContract (`delivery_lifecycle.go`)

Mirrors SC6 — tracks real-time delivery status and GPS logs on Fabric.

| Function                                                 | Type  | Description                                          |
| -------------------------------------------------------- | ----- | ---------------------------------------------------- |
| `CreateDelivery(orderID, uavID, patient, slaDeadline)` | Write | Initialises delivery record                          |
| `SetInFlight(orderID)`                                 | Write | Transitions status `DISPATCHED → IN_FLIGHT`       |
| `LogGPS(orderID, ipfsHash)`                            | Write | Appends a GPS log entry (IPFS hash + timestamp)      |
| `FlagDeviation(orderID, reason)`                       | Write | Marks delivery as `DEVIATED`                       |
| `ConfirmDelivery(orderID)`                             | Write | Marks `DELIVERED`, evaluates SLA compliance        |
| `GetDelivery(orderID)`                                 | Read  | Returns full delivery record including GPS log array |

**Ledger keys:** `DEL_{orderID}`

**Delivery status flow:**

```
DISPATCHED → IN_FLIGHT → DELIVERED
                       ↘ DEVIATED
```

---

### Cross-Chain Flow via SC7

```
                  PDC (Ethereum)                UOC (Fabric)
                  ──────────────                ────────────
Doctor writes     SC3.addRecord()
  record    →     SC7.registerHash()   ──→   Hash: PENDING → VALID
                  (hash now VALID)

HP submits        SC5.submitOrder()
  order     →     SC7.verifyHash()     ──→   Hash: VALID → USED
                  (hash now USED,            (cannot be reused)
                   one-time consumed)

DS opens          SC4.openRound()      ──→   DCSContract.OpenRound()
  DCS round →     SC4.closeRound()           DCSContract.CloseRound()

DS creates        SC6.createDelivery() ──→   LifecycleContract.CreateDelivery()
  delivery  →     SC6.logGPS()               LifecycleContract.LogGPS()
                  SC6.confirmDelivery()       LifecycleContract.ConfirmDelivery()
```

### Off-chain relay service (`oracle/bridge.js`)

An off-chain relay process monitors PDC events and measures cross-chain verification latency:

```javascript
// Listens for SC3 RecordAdded events
sc3.on("RecordAdded", async (recordId, hp, patient, rxHash, parsScore) => {
    // Checks SC7 hash status and records relay latency
    const status = await sc7.checkHash(rxHash);  // expects 1 = VALID
    console.log(`Latency: ${latency}ms`);
});
```

**Run the bridge:**

```bash
cd ~/dcba
node oracle/bridge.js
```

The bridge logs each relay event with timestamp, hash, PARS score, latency (ms), and running average. Measured average oracle relay latency: **~5.4 seconds** end-to-end (PDC event → SC7 state check).

---

## 8. UAV Fleet Simulation

The `simulation/` directory contains Python scripts that validate the DCS algorithm's scalability without requiring a live blockchain.

### `fleet_sim.py` — DCS Scalability Test

Simulates concurrent DCS score computation across fleet sizes of 10, 25, 50, 75, and 100 UAVs using Python threads. Each thread mirrors the `SC4.computeScore()` weighted formula.

```bash
cd ~/dcba
python3 simulation/fleet_sim.py
```

**Measured results (`simulation/scalability_results.json`):**

| Fleet Size | Round Time | Within 140ms threshold? |
| ---------- | ---------- | ----------------------- |
| 10 UAVs    | 0.89 ms    | ✅                      |
| 25 UAVs    | 3.71 ms    | ✅                      |
| 50 UAVs    | 4.32 ms    | ✅                      |
| 75 UAVs    | 7.88 ms    | ✅                      |
| 100 UAVs   | 8.37 ms    | ✅                      |

All fleet sizes complete DCS rounds well under the 140 ms target defined in the research objectives.

### `uav_agent.py` — Individual UAV Agent

Simulates one UAV computing its DCS score and generating GPS hashes, with optional Web3 connection to submit on-chain.

```bash
python3 simulation/uav_agent.py --uav-id uav-001 --round-id round-sim-001
```

---

## 9. End-to-End Medical Delivery Flow

```
Step 1 — Registration (one-time)
  TA.register(patient,      "patient")
  TA.register(doctor,       "hp")
  TA.register(warehouse,    "warehouse")
  TA.register(droneStation, "dronestation")
  TA.register(uav1,         "uav")
  TA.register(uav2,         "uav")

Step 2 — Patient Consent
  patient → SC2.grantAccess(doctor, 7 days)

Step 3 — Medical Record
  doctor → SC3.addRecord(patient, ipfsHash, parsScore=95, rxHash)
           └→ SC7.registerHash(rxHash)   [hash: PENDING → VALID]

Step 4 — Delivery Order
  doctor → SC5.submitOrder(patient, rxHash, parsScore=95, "Insulin 10u", warehouse, droneStation)
           └→ SC7.verifyHash(rxHash)     [hash: VALID → USED, one-time consumption]
           └→ SLA = 3 minutes (CRITICAL tier)

Step 5 — Stock Confirmation
  warehouse → SC5.confirmStock(orderId)  [PENDING → CONFIRMED]

Step 6 — DCS Scoring
  droneStation → SC4.openRound(orderId)       / DCSContract.OpenRound()
  uav1         → SC4.submitScore(roundId, 85) / DCSContract.SubmitScore()
  uav2         → SC4.submitScore(roundId, 92) / DCSContract.SubmitScore()
  droneStation → SC4.closeRound(roundId)      / DCSContract.CloseRound()
                 └→ winner = uav2 (score 92)

Step 7 — UAV Assignment & Delivery Creation
  droneStation → SC5.assignUAV(orderId, uav2)          [CONFIRMED → DISPATCHED]
  droneStation → SC6.createDelivery(orderId, uav2, patient, slaDeadline)
                 / LifecycleContract.CreateDelivery()

Step 8 — Flight
  uav2 → SC6.setInFlight(orderId)       / LifecycleContract.SetInFlight()
         └→ [DISPATCHED → IN_FLIGHT]
  uav2 → SC6.logGPS(orderId, QmHash…)  / LifecycleContract.LogGPS()  [every ~1s]
  uav2 → SC6.logGPS(orderId, QmHash…)
  ...

Step 9 — Delivery Confirmation
  patient → SC6.confirmDelivery(orderId)
            └→ withinSLA = (now ≤ slaDeadline)
            └→ SC4.updateReputation(uav2, +5)  [on-time bonus]
               / DCSContract.UpdateReputation()

Alternative — Deviation Path
  droneStation → SC6.flagDeviation(orderId, "route anomaly")
                 └→ SC4.updateReputation(uav2, -10)  [deviation penalty]
```

---

## 10. Directory Structure

The project root (`~/dcba/`) is the primary working directory. All source files exist both at the root and mirrored under `Blockchain/` (artifact of the project merge commit).

```
dcba/
├── README.md
├── hardhat.config.js                   # Hardhat + Solidity 0.8.20 config
├── package.json                        # Node.js + Caliper dependencies
├── deployed-addresses.json             # Contract addresses (after deploy.js)
├── gas-report.txt                      # Gas cost report (generated by tests)
├── BUG_REPORT.md                       # Critical bug documentation
│
├── contracts/                          # Ethereum Solidity smart contracts
│   ├── SC1_IdentityRegistry.sol
│   ├── SC2_PatientConsent.sol
│   ├── SC3_MedicalRecords.sol
│   ├── SC4_DCSScoring.sol
│   ├── SC5_DeliveryOrders.sol
│   ├── SC6_DeliveryLifecycle.sol
│   └── SC7_OracleBridge.sol
│
├── chaincode/
│   └── dcba-uoc/                       # Hyperledger Fabric Go chaincode
│       ├── main.go                     # Chaincode entry point
│       ├── dcs_scoring.go              # DCS scoring + reputation (mirrors SC4)
│       ├── delivery_lifecycle.go       # Delivery tracking + GPS (mirrors SC6)
│       ├── go.mod
│       └── vendor/                     # Vendored Go dependencies
│
├── scripts/
│   ├── deploy.js                       # Deploys all 7 contracts in correct order
│   └── test_flow.js                   # Full end-to-end workflow test script
│
├── test/                               # Hardhat test suites (86 tests)
│   ├── SC1.test.js                     # Identity registry (7 tests)
│   ├── SC2.test.js                     # Patient consent (12 tests)
│   ├── SC3.test.js                     # Medical records (8 tests)
│   ├── SC4.test.js                     # DCS scoring (10 tests)
│   ├── SC5.test.js                     # Delivery orders (9 tests)
│   ├── SC6.test.js                     # Delivery lifecycle (10 tests)
│   ├── SC7.test.js                     # Oracle bridge (8 tests)
│   ├── Gas.test.js                     # Gas cost measurements (12 tests)
│   └── Security.test.js                # Attack scenario tests (10 tests)
│
├── oracle/
│   └── bridge.js                       # Off-chain oracle relay (event listener)
│
├── simulation/
│   ├── fleet_sim.py                    # DCS scalability: 10–100 UAV fleet
│   ├── uav_agent.py                    # Individual UAV agent (Web3-connected)
│   └── scalability_results.json        # Measured results (all <9ms)
│
├── network/                            # Hyperledger Fabric test network
│   ├── network.sh                      # Network up/down/deployCC
│   ├── organizations/                  # Crypto material (generated)
│   └── scripts/                        # Channel, chaincode, env scripts
│
└── benchmark/                          # Hyperledger Caliper benchmark
    ├── network.yaml                    # Fabric network config
    ├── benchmark.yaml                  # 3-round benchmark config
    ├── connection-org1.yaml            # Fabric CCP (peer/orderer endpoints)
    └── workloads/
        ├── dcs-scoring.js              # Full DCS round (open→score×3→close)
        ├── delivery-lifecycle.js       # Full delivery (create→fly→GPS→confirm)
        └── query-operations.js         # Read-only GetDelivery queries
```

> `Blockchain/` is a subdirectory that contains an identical mirror of the above structure — both are valid working copies.

---

## 11. Prerequisites

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
>
> ```json
> { "features": { "containerd-snapshotter": false } }
> ```
>
> Restart Docker after applying. See [Known Issues](#20-known-issues--bug-fixes).

### Oracle Bridge & Simulation

- Node.js ≥ 18 (for `oracle/bridge.js`)
- Python ≥ 3.8 (for `simulation/`)
- `pip install web3` (for `uav_agent.py`)

### Benchmarking

- Node.js ≥ 18 (Caliper 0.7.1 recommends ≥ 22, but works on 20)
- Fabric network running with `dcbachannel`

---

## 12. Setup & Deployment — Ethereum (PDC)

```bash
cd ~/dcba

# Install dependencies
npm install

# Start local Hardhat node
npx hardhat node

# Deploy all 7 contracts in the correct order (in another terminal)
npx hardhat run scripts/deploy.js --network localhost

# Run full test suite (86 tests across 9 files)
npx hardhat test

# Run end-to-end flow test
npx hardhat run scripts/test_flow.js --network localhost

# View gas costs
cat gas-report.txt
```

Deployed contract addresses are saved to `deployed-addresses.json`.

### Critical deployment steps (handled automatically by `deploy.js`)

After deploying all 7 contracts, two linking calls **must** be made or the system will fail:

```javascript
// Step 5 — Authorise SC3 to register prescription hashes in SC7
await SC7.setSC3Address(SC3.address);

// Step 9 — Authorise SC6 to call updateReputation in SC4
await SC4.linkSC6(SC6.address);
```

### Full deployment order

| Step        | Action                                                   |
| ----------- | -------------------------------------------------------- |
| 1           | Deploy SC1 (no constructor args)                         |
| 2           | Deploy SC7 (no constructor args)                         |
| 3           | Deploy SC2 (SC1 address)                                 |
| 4           | Deploy SC3 (SC1, SC2, SC7 addresses)                     |
| **5** | **`SC7.setSC3Address(SC3_address)` ← CRITICAL** |
| 6           | Deploy SC4 (SC1 address)                                 |
| 7           | Deploy SC5 (SC1, SC7 addresses)                          |
| 8           | Deploy SC6 (SC1, SC4 addresses)                          |
| **9** | **`SC4.linkSC6(SC6_address)` ← CRITICAL**       |

---

## 13. Setup & Deployment — Hyperledger Fabric (UOC)

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
  -ccp ~/dcba/chaincode/dcba-uoc \
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

## 14. Running the Oracle Bridge

The oracle bridge is a Node.js process that listens for `RecordAdded` events from SC3 and verifies the prescription hash status in SC7. It measures end-to-end relay latency.

**Prerequisites:** Hardhat node running + contracts deployed.

```bash
cd ~/dcba
node oracle/bridge.js
```

Sample output:

```
🌉 DCBA Oracle Bridge started
   SC3: 0x68B1D87F95878fE05B998F19b66F4baba5De1aed
   SC7: 0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1
───────────────────────────────────────────────────────
👂 Listening for SC3 RecordAdded events...

[2026-03-23T10:00:01.234Z] RecordAdded event caught!
   recordId : 1
   rxHash   : 0xabc123...
   parsScore: 95
   SC7 status: ✅ VALID
   ⏱  Latency: 5412ms
   ⏱  Total relayed: 1 | Avg: 5412ms
```

---

## 15. Running Benchmarks (Hyperledger Caliper)

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

| Round                | Operations                                              | TPS | Transactions |
| -------------------- | ------------------------------------------------------- | --- | ------------ |
| open-and-score-round | OpenRound + SubmitScore×3 + CloseRound                 | 5   | 50           |
| delivery-lifecycle   | CreateDelivery + SetInFlight + LogGPS + ConfirmDelivery | 5   | 50           |
| query-winner         | GetDelivery (read-only)                                 | 20  | 100          |

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

| Round                | Operations                            | TPS | Transactions |
| -------------------- | ------------------------------------- | --- | ------------ |
| DCS-Score-Submission | OpenRound + SubmitScore + CloseRound  | 5   | 50           |
| GPS-Log-Throughput   | CreateDelivery + SetInFlight + LogGPS | 5   | 50           |

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

## 16. Smart Contract Reference

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
        (via linkSC6)
```

### Function Quick Reference

**SC1 — Identity Registry**

```solidity
register(address who, string role, string publicKeyHash)   // TA only
revoke(address who, string reason)                         // TA only
isActive(address who) → bool
getRole(address who) → string
transferTA(address newTA)                                  // TA only
```

**SC2 — Patient Consent**

```solidity
grantAccess(address hp, uint256 durationDays)              // Patient only; 0 = indefinite
revokeAccess(address hp)                                   // Patient only
hasAccess(address hp, address patient) → bool
getConsentInfo(address patient, address hp) → (bool active, uint256 grantedAt, uint256 expiresAt)
```

**SC3 — Medical Records**

```solidity
addRecord(address patient, string encryptedDataHash, uint8 parsScore, bytes32 rxHash)
getRecord(uint256 recordId) → (address hp, address patient, string hash, uint8 parsScore, bytes32 rxHash, uint256 timestamp)
getPatientRecordIds(address patient) → uint256[]
getParsLabel(uint8 parsScore) → string   // "CRITICAL" | "HIGH" | "MODERATE" | "LOW"
```

**SC4 — DCS Scoring**

```solidity
computeScore(uint256 speed, uint256 payload, uint256 battery, uint256 cpu, uint256 ram) → uint256
openRound(uint256 orderId) → uint256 roundId
submitScore(uint256 roundId, uint256 score)
closeRound(uint256 roundId)
getWinner(uint256 roundId) → (address winner, uint256 score)
updateReputation(address uav, int256 delta)                // SC6 (via linkSC6) or any registered actor
linkSC6(address sc6)                                       // callable once (no onlyTA guard — deploy immediately after SC6)
```

**SC5 — Delivery Orders**

```solidity
submitOrder(address patient, bytes32 rxHash, uint8 parsScore, string drugList, address warehouse, address droneStation) → uint256 orderId
confirmStock(uint256 orderId)                              // Assigned warehouse only
assignUAV(uint256 orderId, address uav)                   // Drone Station only
updateStatus(uint256 orderId, OrderStatus newStatus)
getOrder(uint256 orderId) → (address hp, address patient, uint8 parsScore, string drugList, address assignedUAV, OrderStatus status, uint256 slaDeadline)
getSLASeconds(uint8 parsScore) → uint256
getParsLabel(uint8 parsScore) → string   // "CRITICAL - 3min SLA" | "HIGH - 10min SLA" | "MODERATE - 30min SLA" | "LOW - 2hr SLA"
```

**SC6 — Delivery Lifecycle**

```solidity
createDelivery(uint256 orderId, address uav, address patient, uint256 slaDeadline)
setInFlight(uint256 orderId)
logGPS(uint256 orderId, string ipfsHash)
flagDeviation(uint256 orderId, string reason)              // DS only; triggers −10 reputation
confirmDelivery(uint256 orderId)                           // Patient only; triggers +5 or −5 reputation
getDeliveryStatus(uint256 orderId) → (DeliveryStatus status, address uav, uint256 gpsUpdateCount, bool withinSLA, bool deviated)
getGPSLog(uint256 orderId) → (string[] hashes, uint256[] timestamps)
```

**SC7 — Oracle Bridge**

```solidity
setSC3Address(address sc3)                                 // TA only — call after SC3 deployment
registerHash(bytes32 rxHash, address hp)                   // SC3 only; hash: PENDING → VALID
verifyHash(bytes32 rxHash) → bool                         // hash: VALID → USED (no caller restriction in current impl)
checkHash(bytes32 rxHash) → uint8                         // Read-only: 0=PENDING, 1=VALID, 2=USED
```

---

## 17. Chaincode Reference

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

## 18. Security Design

### Threat Model & Mitigations

| Threat                                                   | Mitigation                                                                     |
| -------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Unauthorised medical record write                        | SC2 consent check + SC1 role check in SC3                                      |
| Prescription replay (ordering the same medication twice) | SC7 marks hash as `USED` after first verification — any reuse returns false |
| Rogue UAV submitting GPS after landing                   | SC6 rejects `logGPS` unless status is `IN_FLIGHT`                          |
| DS assigning a preferred UAV without scoring             | SC4 on-chain scoring; winner selection is deterministic and public             |
| Compromised actor                                        | SC1 `revoke()` immediately blocks all contract interactions                  |
| Medical data exposure                                    | Raw data stored encrypted on IPFS; only hash stored on-chain                   |
| UAV impersonation                                        | SC1 identity check on every state-changing call                                |
| Duplicate UAV score submission                           | SC4 tracks submitted UAVs per round; rejects duplicates                        |
| Wrong patient confirming delivery                        | SC6 checks `msg.sender == delivery.patient`                                  |
| Wrong warehouse confirming stock                         | SC5 checks `msg.sender == order.warehouse`                                   |

### Security Test Coverage (`Security.test.js` — 10 tests)

| Test ID   | Scenario                                                  | Expected Result                                                            |
| --------- | --------------------------------------------------------- | -------------------------------------------------------------------------- |
| TC-SEC-01 | Same `rxHash` used for two orders (prescription replay) | Second order reverts:`"Prescription not verified by SC-7 oracle"`        |
| TC-SEC-02 | Unregistered actor writes medical record                  | Reverts:`"HP not registered in SC-1"`                                    |
| TC-SEC-03 | Revoked HP writes medical record                          | Reverts:`"HP not registered in SC-1"`                                    |
| TC-SEC-04 | Unregistered UAV submits DCS score                        | Reverts:`"UAV not registered in SC-1"`                                   |
| TC-SEC-05 | Attacker confirms someone else's delivery                 | Reverts:`"Only the patient can confirm delivery"`                        |
| TC-SEC-06 | HP writes record without patient consent                  | Reverts:`"No patient consent - patient must call SC2.grantAccess first"` |
| TC-SEC-07 | Non-TA attempts to transfer TA authority                  | Reverts:`"Only TA can do this"`                                          |
| TC-SEC-08 | Attacker directly registers hash in SC7 (bypasses SC3)    | Reverts:`"Only SC-3 can register"`                                       |
| TC-SEC-09 | Different DS closes another DS's scoring round            | Reverts:`"Only the DS that opened this round"`                           |
| TC-SEC-10 | Wrong warehouse confirms another order's stock            | Reverts:`"Only the assigned warehouse"`                                  |

### MVCC Conflict Prevention (Fabric)

Fabric uses optimistic concurrency (MVCC). If two transactions read and write the same ledger key simultaneously, the second one is rejected (status 11 = `MVCC_READ_CONFLICT`). The chaincode workloads prevent this by assigning a unique ledger key per transaction:

```javascript
// Each transaction uses its own unique roundId/orderId
const roundId = `r-${workerIndex}-${txCounter}-${Date.now()}`;
```

---

## 19. Gas Costs

All costs measured on a local Hardhat network (Solidity 0.8.20, optimizer 200 runs, block limit 60,000,000).

### Deployment Costs

| Contract              | Gas Used            | % of Block Limit |
| --------------------- | ------------------- | ---------------- |
| SC1_IdentityRegistry  | 660,784             | 1.1%             |
| SC2_PatientConsent    | 429,015             | 0.7%             |
| SC3_MedicalRecords    | 873,476             | 1.5%             |
| SC4_DCSScoring        | 997,739             | 1.7%             |
| SC5_DeliveryOrders    | 1,375,158           | 2.3%             |
| SC6_DeliveryLifecycle | 1,328,993           | 2.2%             |
| SC7_OracleBridge      | 383,565             | 0.6%             |
| **Total**       | **6,048,730** | **~10.1%** |

### Function Costs (from `gas-report.txt`)

| Contract | Function             | Min Gas | Max Gas | Avg Gas |
| -------- | -------------------- | ------- | ------- | ------- |
| SC1      | `register`         | 118,544 | 118,736 | 118,617 |
| SC1      | `revoke`           | 27,503  | 27,635  | 27,561  |
| SC1      | `transferTA`       | —      | —      | 27,001  |
| SC2      | `grantAccess`      | 67,055  | 101,267 | 100,367 |
| SC2      | `revokeAccess`     | —      | —      | 23,924  |
| SC3      | `addRecord`        | 289,998 | 324,306 | 321,488 |
| SC4      | `openRound`        | —      | —      | 104,650 |
| SC4      | `submitScore`      | 154,711 | 188,911 | 185,111 |
| SC4      | `closeRound`       | 88,674  | 99,869  | 91,473  |
| SC4      | `updateReputation` | 53,773  | 54,145  | 53,959  |
| SC4      | `linkSC6`          | —      | —      | 44,099  |
| SC5      | `submitOrder`      | 369,551 | 369,628 | 369,576 |
| SC5      | `confirmStock`     | —      | —      | 49,039  |
| SC5      | `assignUAV`        | —      | —      | 40,012  |
| SC6      | `createDelivery`   | 176,949 | 176,961 | 176,952 |
| SC6      | `setInFlight`      | —      | —      | 30,505  |
| SC6      | `logGPS`           | 84,154  | 118,582 | 107,054 |
| SC6      | `flagDeviation`    | —      | —      | 95,657  |
| SC6      | `confirmDelivery`  | —      | —      | 120,122 |
| SC7      | `setSC3Address`    | 46,031  | 46,043  | 46,042  |
| SC7      | `verifyHash`       | 50,723  | 50,735  | 50,729  |

> `SC5.submitOrder` is the most expensive transaction (369,576 gas) because it atomically calls `SC7.verifyHash()` and stores the full order in one transaction.

---

## 20. Known Issues & Bug Fixes

### Bug 1 — CRITICAL: SC4.updateReputation fails when called from SC6

**Problem:** SC6 calls `SC4.updateReputation()` after delivery confirmation or deviation flagging. Inside SC4, `msg.sender` is the SC6 contract address. SC4 checks `SC1.isActive(msg.sender)` — but SC6 is a contract, not a registered actor → reverts every time.

**Effect:** `confirmDelivery()` and `flagDeviation()` in SC6 **always fail** without this fix.

**Fix applied:** Added `sc6Address` storage and `linkSC6(address)` function to SC4. Reputation update now accepts calls from either a registered actor OR the linked SC6 address:

```solidity
require(sc1.isActive(msg.sender) || msg.sender == sc6Address, "Caller not authorized");
```

**Action required at deployment:** Call `SC4.linkSC6(SC6_address)` after both contracts are deployed (handled in `deploy.js` step 9).

---

### Bug 2 — CRITICAL: SC7.registerHash reverts (missing setSC3Address step)

**Problem:** SC7 initialises `sc3Address = address(0)`. SC7.registerHash() checks `msg.sender == sc3Address`, which is always false until `setSC3Address()` is called. Every `SC3.addRecord()` call fails silently.

**Fix applied:** Not a code bug — it's a deployment procedure step. `setSC3Address(address)` already exists in SC7.

**Action required at deployment:** Call `SC7.setSC3Address(SC3_address)` immediately after SC3 is deployed (handled in `deploy.js` step 5).

---

### Bug 3 — MINOR: SC6 had unused ISC5 interface (dead code)

**Problem:** `interface ISC5` was declared in SC6 but never instantiated or used.

**Fix applied:** ISC5 interface block removed from SC6.

---

### Bug 4 — Docker 25+ breaks Fabric chaincode installation

**Problem:** Docker 23+ enables BuildKit and containerd snapshotter by default. Hyperledger Fabric v2.5's peer uses the legacy Docker build API which fails with `write unix @->/run/docker.sock: write: broken pipe`.

**Fix applied:** Create `/etc/docker/daemon.json`:

```json
{ "features": { "containerd-snapshotter": false } }
```

Restart Docker daemon after applying.

---

### Bug 5 — Fabric peer image version mismatch

**Problem:** After Docker restart, `fabric-peer:latest` pulls v3.1.4, but the local Fabric binaries are v2.5.0. The peer container looks for `hyperledger/fabric-ccenv:3.1` which doesn't exist locally.

**Fix applied:**

```bash
docker pull hyperledger/fabric-ccenv:3.1
docker pull hyperledger/fabric-baseos:3.1
```

---

### Bug 6 — MVCC conflicts in Caliper workloads

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
