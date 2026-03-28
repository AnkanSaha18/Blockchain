# DCBA — Dual-Chain Blockchain Architecture

### Secure, Priority-Aware, UAV-Enabled Pharmaceutical Delivery

> **M.Sc. Research Project** — Department of Computer Science and Engineering
> Bangladesh University of Engineering and Technology (BUET), 2025–2026

A dual-chain blockchain system combining **Ethereum smart contracts** (Patient Data Chain) and **Hyperledger Fabric chaincode** (UAV Operational Chain) to enable secure, privacy-preserving, and auditable drone delivery of pharmaceutical supplies.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Why Two Blockchains?](#2-why-two-blockchains)
3. [System Architecture](#3-system-architecture)
4. [Principal Actors](#4-principal-actors)
5. [PDC — Patient Data Chain (SC-1, SC-2, SC-3)](#5-pdc--patient-data-chain)
6. [UOC — UAV Operational Chain (SC-4, SC-5, SC-6)](#6-uoc--uav-operational-chain)
7. [SC-7 — Cross-Chain Oracle Bridge](#7-sc-7--cross-chain-oracle-bridge)
8. [Core Algorithms](#8-core-algorithms)
9. [Hyperledger Fabric Chaincode (Go)](#9-hyperledger-fabric-chaincode-go)
10. [End-to-End System Flow](#10-end-to-end-system-flow)
11. [UAV Fleet Simulation](#11-uav-fleet-simulation)
12. [Directory Structure](#12-directory-structure)
13. [Prerequisites](#13-prerequisites)
14. [Quick Start — Automated](#14-quick-start--automated)
15. [Manual Setup — Ethereum PDC](#15-manual-setup--ethereum-pdc)
16. [Manual Setup — Hyperledger Fabric UOC](#16-manual-setup--hyperledger-fabric-uoc)
17. [Oracle Bridge](#17-oracle-bridge)
18. [Benchmarks — Hyperledger Caliper](#18-benchmarks--hyperledger-caliper)
19. [Smart Contract Reference](#19-smart-contract-reference)
20. [Chaincode Reference (Fabric CLI)](#20-chaincode-reference-fabric-cli)
21. [Security Design](#21-security-design)
22. [Gas Costs](#22-gas-costs)
23. [Performance Results](#23-performance-results)
24. [Known Issues and Bug Fixes](#24-known-issues-and-bug-fixes)

---

## 1. Project Overview

DCBA solves two simultaneous real-world problems in pharmaceutical delivery:

- **Counterfeit drugs** — WHO reports ~10% of medicines in low-income countries are falsified, causing ~1 million deaths per year.
- **Last-mile delivery failure** — In Bangladesh, traffic congestion in Dhaka (44,000 persons/km²) makes ground delivery of life-critical medications (insulin, epinephrine, cardiac drugs) dangerously slow.

**The solution:** A blockchain-governed UAV delivery system with six original contributions absent from prior literature:

| #  | Contribution                  | Description                                                                                 |
| -- | ----------------------------- | ------------------------------------------------------------------------------------------- |
| C1 | Dual-chain architecture       | PDC for patient privacy + UOC for UAV operations, connected by SC-7 oracle                  |
| C2 | Hardware-bound UAV identity   | `h = H(mac ‖ τs ‖ seed)` ties DID to physical MAC address — clone-resistant           |
| C3 | Two-phase DCS algorithm       | Bloom filter pre-screening + SC-1 identity check; selects from 100 UAVs in**8.37 ms** |
| C4 | Sanitizable signature records | TA root signature preserved during HP amendments to medical records                         |
| C5 | PARS with on-chain SLA        | Four clinical urgency tiers with blockchain-enforced delivery deadlines                     |
| C6 | Patient-sovereign encryption  | Records encrypted with patient's public key — physician cannot read stored data            |

---

## 2. Why Two Blockchains?

| Concern                      | Ethereum PDC                      | Hyperledger Fabric UOC                          |
| ---------------------------- | --------------------------------- | ----------------------------------------------- |
| **Privacy**            | Patient consent gates all access  | Permissioned — only registered orgs            |
| **Data type**          | Business logic, identity, consent | High-frequency operational data (GPS ~1 tx/sec) |
| **Transaction volume** | Low (records, orders)             | High (GPS logs, status updates, scoring)        |
| **Finality**           | PoA (fast, known validators)      | Immediate (Raft/BFT consensus)                  |
| **Throughput**         | 100–300 TPS                      | 3,000–10,000 TPS                               |
| **Gas cost**           | Nominal in PoA                    | None (permissioned)                             |

Ethereum handles **trustless, privacy-sensitive business logic**. Hyperledger Fabric handles **high-throughput operational tracking** — GPS logging at 118,582 gas/call on Ethereum makes the split essential.

---

## 3. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DCBA Dual-Chain Architecture                       │
│                                                                             │
│  ┌────────────────────────────┐   SC-7 Oracle   ┌───────────────────────┐   │
│  │  PDC — Patient Data Chain  │◄───────────────►│  UOC — UAV Ops Chain  │   │
│  │  (Ethereum / Hardhat PoA)  │  rxHash relay   │  (Hyperledger Fabric) │   │
│  │                            │                 │                       │   │
│  │  SC-1  Identity Registry   │                 │  DCSContract   (Go)   │   │
│  │  SC-2  Patient Consent     │                 │  LifecycleContract(Go)│   │
│  │  SC-3  Medical Records     │                 │  OrdersContract  (Go) │   │
│  │  SC-7  Oracle Bridge ──────┼──── relay ─────►│  channel: dcbachannel │   │
│  │        PENDING→VALID→USED  │                 │  chaincode: dcba-uoc  │   │
│  └────────────────────────────┘                 └───────────────────────┘   │
│                                                                             │
│  Off-chain storage : IPFS (encrypted medical data + GPS coordinates)        │
│  Off-chain relay   : oracle/bridge.js — 16 ms local / ~5.4 s cross-host     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Contract-to-Chain Assignment

| Contract                   | Chain                             | Purpose                                              |
| -------------------------- | --------------------------------- | ---------------------------------------------------- |
| SC-1 — Identity Registry  | **Both** (PDC + UOC)        | Root-of-trust; every contract calls `isActive()`   |
| SC-2 — Patient Consent    | **PDC**                     | Patient data sovereignty                             |
| SC-3 — Medical Records    | **PDC**                     | Sensitive health data governed by patient consent    |
| SC-4 — DCS Scoring        | **UOC**                     | High-frequency UAV competition rounds + Bloom filter |
| SC-5 — Delivery Orders    | **UOC**                     | PARS priority queue + SLA enforcement                |
| SC-6 — Delivery Lifecycle | **UOC**                     | Real-time GPS logging + delivery state machine       |
| SC-7 — Oracle Bridge      | **Shared** (PDC→UOC relay) | Cross-chain prescription verification                |

> **Development note:** All 7 Solidity contracts are deployed on a single Hardhat network for local development. In production, SC-4/SC-5/SC-6 run on Hyperledger Fabric. The Go chaincode (`DCSContract`, `LifecycleContract`, `OrdersContract`) is the production UOC implementation.

---

## 4. Principal Actors

Eight actors govern the system. Seven are application-layer participants registered in SC-1; one operates at the consensus layer.

| # | Actor                    | Role                                                | SC-1 Role String           |
| - | ------------------------ | --------------------------------------------------- | -------------------------- |
| 1 | Trusted Authority (TA)   | Deploys all contracts; registers/revokes all actors | *(deployer — implicit)* |
| 2 | Healthcare Provider (HP) | Writes medical records; submits delivery orders     | `"hp"`                   |
| 3 | Patient                  | Grants/revokes HP consent; confirms delivery        | `"patient"`              |
| 4 | Drug Warehouse (DW)      | Confirms drug stock; hands package to UAV           | `"warehouse"`            |
| 5 | Drone Station (DS)       | Runs DCS rounds; assigns UAVs; monitors GPS         | `"dronestation"`         |
| 6 | UAV                      | Competes via DCS scoring; delivers; logs GPS        | `"uav"`                  |
| 7 | Regulatory Auditor (RA)  | Read-only audit trail; DGDA compliance reports      | `"auditor"`              |
| 8 | Miner/Validator          | PoA consensus (PDC); Raft endorsement (UOC)         | *(infrastructure only)*  |

---

## 5. PDC — Patient Data Chain

Three contracts on **Ethereum PoA** handle identity, consent, and medical records.

### SC-1 — Identity Registry (`SC1_IdentityRegistry.sol`)

Root-of-trust for the entire system. Every other contract calls `isActive()` before any state change.

- TA calls `register(address, role, publicKeyHash)` to onboard actors
- `isActive(address)` and `getRole(address)` called by SC-2 through SC-6
- `revoke(address, reason)` immediately blocks a compromised actor across **all** contracts
- `transferTA(newTA)` for TA key rotation

> SC-1 is deployed identically on both chains — UOC contracts also need identity verification.

### SC-2 — Patient Consent (`SC2_PatientConsent.sol`)

Patient-controlled, time-limited access tokens for medical data. Implements GDPR-style "right to access" at the smart-contract level.

- Patient calls `grantAccess(hpAddress, durationDays)` — `durationDays = 0` means indefinite
- SC-3 calls `hasAccess(hp, patient)` atomically before every record write
- Patient can `revokeAccess(hpAddress)` at any time — instant effect

### SC-3 — Medical Records (`SC3_MedicalRecords.sol`)

Stores medical record metadata on-chain. Actual data lives on IPFS encrypted with the patient's public key.

**Triple validation gate in `addRecord()`:**

1. HP is registered and active in SC-1
2. HP has patient's valid, non-expired consent in SC-2
3. PARS score is 0–100 and `rxHash` is non-empty

After storing, SC-3 **automatically** calls `SC7.registerHash(rxHash)` in the same transaction — the prescription hash becomes VALID in the oracle atomically.

---

## 6. UOC — UAV Operational Chain

Three contracts handle UAV selection, order management, and live delivery tracking. In development they run as Solidity on Hardhat; in production they run as Go chaincode on Hyperledger Fabric.

### SC-4 — DCS Scoring (`SC4_DCSScoring.sol`) — with Bloom Filter

Implements the complete **two-phase Drone Capability Score** selection protocol.

#### DCS Formula

```
score = (speed×30 + payload×25 + battery×20 + cpu×15 + ram×10) / 100
```

All inputs 0–100. Weights sum to 100. Output normalised in [0, 100].

#### Phase 1 — Bloom Filter (O(1) pre-screen)

On-chain Bloom filter for fast pre-screening before the more expensive identity check.

**Parameters (Section 6.4 of research proposal):**

| Parameter                | Value                       |
| ------------------------ | --------------------------- |
| Fleet size (n)           | 100 UAVs                    |
| False positive rate (ε) | 0.01 (1%)                   |
| Hash functions (k)       | 7 (`k = ⌈−log₂(ε)⌉`) |
| Bit array size (m)       | 1,024 bits (128 bytes)      |

```
Phase 1 — Bloom Filter (O(1)):
  UAV address NOT in filter → definitely unregistered → reject immediately
  UAV address IN filter     → probably registered    → proceed to Phase 2

Phase 2 — SC-1 Identity Check (definitive):
  Catches the ~1% Bloom false positive
  sc1.isActive(msg.sender) must return true
```

**Bloom filter management:**

- `addUAVToBloom(uavAddress)` — call after registering a new UAV in SC-1
- `rebuildBloomFilter(activeUAVs[])` — full rebuild required after any revocation (Bloom filters do not support deletion)
- `bloomCheck(uavAddress)` — read-only query

#### Reputation System

| Event                                                    | Delta |
| -------------------------------------------------------- | ----- |
| On-time delivery (called by SC-6 on `confirmDelivery`) | +5    |
| Late delivery (called by SC-6 on `confirmDelivery`)    | −5   |
| Route deviation (called by SC-6 on `flagDeviation`)    | −10  |

### SC-5 — Delivery Orders (`SC5_DeliveryOrders.sol`) — with PARS Priority Queue

Order management contract implementing the full **Priority-Aware Routing System**.

#### PARS Tiers

| Tier     | PARS Score | SLA    | UAV Requirement    | Clinical Examples                       |
| -------- | ---------- | ------ | ------------------ | --------------------------------------- |
| CRITICAL | 90–100    | 3 min  | Premium mandatory  | Insulin, epinephrine, cardiac meds      |
| HIGH     | 70–89     | 10 min | Premium preferred  | Antibiotics for sepsis, anti-coagulants |
| MODERATE | 40–69     | 30 min | Normal sufficient  | Routine medications, maintenance drugs  |
| LOW      | 0–39      | 2 hr   | Normal best-effort | OTC, elective, non-urgent refills       |

#### Priority Queue

Orders are dispatched in order of clinical urgency — not first-come-first-served.

```
getHighestPriorityOrder()   → most urgent PENDING order
                               tie-breaking: earlier submission wins (FIFO within tier)

getPendingOrdersSorted()    → all PENDING orders sorted by parsScore DESC

getPendingCountByTier()     → {critical, high, moderate, low} counts
                               used by RA for PARS inflation detection

getOverduePendingOrders()   → orders that have already exceeded their SLA deadline
```

`submitOrder()` calls `SC7.verifyHash(rxHash)` in the same transaction — prescription is marked USED atomically, preventing replay attacks.

### SC-6 — Delivery Lifecycle (`SC6_DeliveryLifecycle.sol`)

Real-time delivery tracking from warehouse pickup to patient doorstep.

**State machine:** `DISPATCHED → IN_FLIGHT → DELIVERED` (or `DEVIATED` on anomaly)

| Function                      | Caller  | Effect                                                      |
| ----------------------------- | ------- | ----------------------------------------------------------- |
| `createDelivery()`          | DS      | Initialises delivery record                                 |
| `setInFlight()`             | UAV     | `DISPATCHED → IN_FLIGHT`                                 |
| `logGPS(orderId, ipfsHash)` | UAV     | Appends GPS log entry (~1 per second)                       |
| `flagDeviation()`           | DS      | `→ DEVIATED`; UAV reputation −10                        |
| `confirmDelivery()`         | Patient | `→ DELIVERED`; UAV reputation +5 (on-time) or −5 (late) |
| `getGPSLog()`               | Anyone  | Returns full GPS trail for audit                            |

---

## 7. SC-7 — Cross-Chain Oracle Bridge

The only communication point between PDC and UOC. Enforces the strict **one-prescription → one-delivery** mapping to prevent prescription fraud.

**Hash lifecycle:**

```
PENDING  →  VALID  →  USED
(initial)   (SC-3 addRecord)   (SC-5 submitOrder)
```

| Function                     | Caller             | Description                                   |
| ---------------------------- | ------------------ | --------------------------------------------- |
| `setSC3Address(sc3)`       | TA only            | Authorise SC-3 as the only hash registrar     |
| `registerHash(rxHash, hp)` | SC-3 only          | Marks hash VALID                              |
| `verifyHash(rxHash)`       | SC-5               | Marks hash USED — one-time, cannot be reused |
| `checkHash(rxHash)`        | Anyone (read-only) | Returns 0=PENDING, 1=VALID, 2=USED            |

> `setSC3Address()` **must** be called by TA immediately after SC-3 deployment, or all `addRecord()` calls will fail. This is handled automatically by `deploy.js`.

---

## 8. Core Algorithms

### Two-Phase DCS Protocol

```
UAV off-chain:
  cs = computeScore(speed, payload, battery, cpu, ram)
  ε  = Enc(cs, keypub_DS)         ← asymmetric encryption
  σ  = Sign(ε, keypri_UAV)        ← digital signature
  SC4.submitScore(roundId, cs)    ← on-chain submission

On-chain SC-4:
  Phase 1: bloomCheck(msg.sender) → false? → reject O(1)
  Phase 2: sc1.isActive(msg.sender) → false? → reject
  Accept  → record score
  closeRound() → argmax → winner (υ_premium)
```

### Hardware-Bound UAV Identity

```
h° = H(mac ‖ τs ‖ seed)
```

- `mac` — hardware MAC address (NIC, non-changeable)
- `τs` — manufacture timestamp (factory-recorded)
- `seed` — TA-issued secret (never stored in UAV firmware)

Extracting the private key and installing it on a different device fails because the MAC address differs → `h°` differs → DID does not match SC-1 registration.

---

## 9. Hyperledger Fabric Chaincode (Go)

Go chaincode deployed to `dcbachannel` as `dcba-uoc v2.0`. Three contracts are registered in `main.go`.

### DCSContract (`dcs_scoring.go`)

Mirrors SC-4. Manages DCS scoring rounds, Bloom filter, and UAV reputation on Fabric.

| Function                               | Type  | Description                                         |
| -------------------------------------- | ----- | --------------------------------------------------- |
| `OpenRound(roundID, orderID)`        | Write | Creates scoring round on ledger                     |
| `SubmitScore(roundID, uavID, score)` | Write | Phase 1 Bloom + Phase 2 active check; records score |
| `CloseRound(roundID)`                | Write | Selects highest-scoring UAV as winner               |
| `GetWinner(roundID)`                 | Read  | Returns winner address and score                    |
| `AddUAVToBloom(uavID)`               | Write | Adds UAV to on-chain Bloom filter                   |
| `RebuildBloomFilter(activeUAVsJSON)` | Write | Full rebuild after any revocation                   |
| `BloomCheck(uavID)`                  | Read  | Returns true/false                                  |
| `UpdateReputation(uavID, delta)`     | Write | Adds/subtracts from UAV reputation score            |
| `GetReputation(uavID)`               | Read  | Returns current reputation                          |
| `GetRoundStats(roundID)`             | Read  | Returns accepted/rejectedBloom/rejectedSig counts   |

**Ledger keys:** `ROUND_{roundID}`, `REP_{uavID}`, `BLOOM_FILTER`

### LifecycleContract (`delivery_lifecycle.go`)

Mirrors SC-6. Tracks real-time delivery status and GPS logs on Fabric.

| Function                                                 | Type  | Description                                          |
| -------------------------------------------------------- | ----- | ---------------------------------------------------- |
| `CreateDelivery(orderID, uavID, patient, slaDeadline)` | Write | Initialises delivery record                          |
| `SetInFlight(orderID)`                                 | Write | `DISPATCHED → IN_FLIGHT`                          |
| `LogGPS(orderID, ipfsHash)`                            | Write | Appends GPS log entry (IPFS hash + timestamp)        |
| `FlagDeviation(orderID, reason)`                       | Write | Marks `DEVIATED`                                   |
| `ConfirmDelivery(orderID)`                             | Write | Marks `DELIVERED`; evaluates SLA compliance        |
| `GetDelivery(orderID)`                                 | Read  | Returns full delivery record including GPS log array |

**Ledger keys:** `DEL_{orderID}`

**Delivery state flow:**

```
DISPATCHED → IN_FLIGHT → DELIVERED
                       ↘ DEVIATED
```

### OrdersContract (`delivery_orders.go`)

Mirrors SC-5. Implements PARS priority queue on Fabric.

| Function                                                                          | Type  | Description                                     |
| --------------------------------------------------------------------------------- | ----- | ----------------------------------------------- |
| `SubmitOrder(orderID, hp, patient, rxHash, parsScore, drugList, warehouse, ds)` | Write | Creates delivery order                          |
| `GetHighestPriorityOrder(orderIDsJSON)`                                         | Read  | Returns most urgent PENDING order               |
| `GetPendingOrdersSorted(orderIDsJSON)`                                          | Read  | Returns PENDING orders sorted by parsScore DESC |
| `GetPendingCountByTier(orderIDsJSON)`                                           | Read  | Returns counts per PARS tier                    |
| `UpdateOrderStatus(orderID, newStatus)`                                         | Write | DS/UAV advances order state                     |
| `GetOrder(orderID)`                                                             | Read  | Returns full order details                      |

**Ledger keys:** `FABRIC_ORDER_{orderID}`

---

## 10. End-to-End System Flow

```
STEP 1 — Registration (one-time)
  TA → SC1.register(patient,      "patient")
  TA → SC1.register(hp,           "hp")
  TA → SC1.register(warehouse,    "warehouse")
  TA → SC1.register(droneStation, "dronestation")
  TA → SC1.register(uav1,         "uav")
  TA → SC4.addUAVToBloom(uav1)           ← add to Bloom filter

STEP 2 — Patient Consent
  patient → SC2.grantAccess(hp, 7)       ← 7-day consent token

STEP 3 — Medical Record
  hp → SC3.addRecord(patient, ipfsHash, parsScore=95, rxHash)
            └→ SC7.registerHash(rxHash)  ← PENDING → VALID (same tx)

STEP 4 — Oracle Relay (16 ms local)
  bridge.js catches RecordAdded event → verifies SC7 hash status

STEP 5 — Delivery Order (CRITICAL tier — SLA = 3 min)
  hp → SC5.submitOrder(patient, rxHash, 95, "Insulin", warehouse, ds)
            └→ SC7.verifyHash(rxHash)    ← VALID → USED (replay prevention)

STEP 6 — Stock Confirmation
  warehouse → SC5.confirmStock(orderId)  ← PENDING → CONFIRMED

STEP 7 — DCS Round (Priority Queue dispatches CRITICAL first)
  ds  → SC4.openRound(orderId)             / DCSContract.OpenRound()
  uav1 → SC4.submitScore(roundId, 82)     ← Phase 1: Bloom ✓, Phase 2: SC1 ✓
  ds  → SC4.closeRound(roundId)           ← winner = uav1 (score 82)

STEP 8 — Assignment and Dispatch
  ds  → SC5.assignUAV(orderId, uav1)     ← CONFIRMED → DISPATCHED
  ds  → SC6.createDelivery(orderId, uav1, patient, slaDeadline)
                                          / LifecycleContract.CreateDelivery()

STEP 9 — Flight
  uav1 → SC6.setInFlight(orderId)        ← DISPATCHED → IN_FLIGHT
  uav1 → SC6.logGPS(orderId, "QmGPS1")  ← every ~1 second
  uav1 → SC6.logGPS(orderId, "QmGPS2")
  ...

STEP 10 — Delivery Confirmation
  patient → SC6.confirmDelivery(orderId)
                  └→ withinSLA = (now ≤ slaDeadline) → true
                  └→ SC4.updateReputation(uav1, +5)   ← on-time bonus

DEVIATION PATH (instead of Step 10):
  ds → SC6.flagDeviation(orderId, "off-route")
             └→ SC4.updateReputation(uav1, -10)       ← deviation penalty
             └→ status = DEVIATED → new DCS round triggered
```

---

## 11. UAV Fleet Simulation

### `simulation/fleet_sim.py` — DCS Scalability Benchmark

Simulates concurrent DCS score computation using Python threads, mirroring the `SC4.computeScore()` weighted formula across 10–100 UAV fleet sizes.

```bash
cd ~/dcba/Blockchain
python3 simulation/fleet_sim.py
```

**Measured results:**

| Fleet Size | Round Time        | ≤ 140 ms target?         |
| ---------- | ----------------- | ------------------------- |
| 10 UAVs    | 0.89 ms           | ✓                        |
| 25 UAVs    | 3.71 ms           | ✓                        |
| 50 UAVs    | 4.32 ms           | ✓                        |
| 75 UAVs    | 7.88 ms           | ✓                        |
| 100 UAVs   | **8.37 ms** | ✓ — 16.7× below target |

Results are saved to `simulation/scalability_results.json`.

### `simulation/uav_agent.py` — Individual UAV Agent

Simulates one UAV computing its DCS score and generating GPS coordinate hashes, with optional Web3 connection to submit on-chain.

```bash
python3 simulation/uav_agent.py --uav-id uav-001 --round-id round-sim-001
```

---

## 12. Directory Structure

```
~/dcba/
│
├── README.md                           ← This file
├── README_(old).md                     ← Previous version (archived)
├── report.html                         ← Caliper benchmark HTML report
│
├── Blockchain/                         ← Primary working directory
│   │
│   ├── contracts/                      ← Ethereum Solidity smart contracts (PDC)
│   │   ├── SC1_IdentityRegistry.sol    ← DID registry — deployed on both chains
│   │   ├── SC2_PatientConsent.sol      ← Patient consent tokens
│   │   ├── SC3_MedicalRecords.sol      ← MBLOCK store + auto SC-7 registration
│   │   ├── SC4_DCSScoring.sol          ← DCS scoring + Bloom filter (v2)
│   │   ├── SC5_DeliveryOrders.sol      ← PARS priority queue (v2)
│   │   ├── SC6_DeliveryLifecycle.sol   ← GPS trail + delivery state machine
│   │   └── SC7_OracleBridge.sol        ← rxHash PENDING→VALID→USED
│   │
│   ├── chaincode/
│   │   └── dcba-uoc/                   ← Hyperledger Fabric Go chaincode (UOC)
│   │       ├── main.go                 ← Registers all three chaincode contracts
│   │       ├── dcs_scoring.go          ← DCS rounds + Bloom filter (mirrors SC-4)
│   │       ├── delivery_lifecycle.go   ← GPS tracking + state machine (mirrors SC-6)
│   │       ├── delivery_orders.go      ← PARS priority queue (mirrors SC-5) — v2
│   │       ├── go.mod                  ← go 1.21 (major.minor only — Fabric requirement)
│   │       └── vendor/                 ← Vendored Go dependencies
│   │
│   ├── scripts/
│   │   ├── deploy.js                   ← Deploys all 7 contracts in correct order
│   │   └── test_flow.js                ← Full end-to-end workflow test
│   │
│   ├── test/                           ← Hardhat test suite (116 tests total)
│   │   ├── SC1.test.js                 ← Identity registry (7 tests)
│   │   ├── SC2.test.js                 ← Patient consent (12 tests)
│   │   ├── SC3.test.js                 ← Medical records (8 tests)
│   │   ├── SC4.test.js                 ← DCS scoring — core (10 tests)
│   │   ├── SC4_BloomFilter.test.js     ← Bloom filter — v2 (13 tests)
│   │   ├── SC5.test.js                 ← Delivery orders — core (9 tests)
│   │   ├── SC5_PARSQueue.test.js       ← PARS priority queue — v2 (17 tests)
│   │   ├── SC6.test.js                 ← Delivery lifecycle (10 tests)
│   │   ├── SC7.test.js                 ← Oracle bridge (8 tests)
│   │   ├── Gas.test.js                 ← Gas cost measurements (12 tests)
│   │   └── Security.test.js            ← Attack scenario tests (10 tests)
│   │
│   ├── oracle/
│   │   └── bridge.js                   ← Off-chain oracle relay (event listener)
│   │
│   ├── simulation/
│   │   ├── fleet_sim.py                ← DCS scalability: 10–100 UAV fleet
│   │   ├── uav_agent.py                ← Individual UAV agent
│   │   └── scalability_results.json    ← Measured results (all < 9 ms)
│   │
│   ├── benchmark/                      ← Hyperledger Caliper benchmark
│   │   ├── network.yaml                ← Fabric network config (version: "1.0")
│   │   ├── benchmark.yaml              ← 3-round benchmark config
│   │   └── workload/
│   │       ├── dcs_submit.js           ← DCS scoring workload
│   │       └── gps_log.js              ← GPS logging workload
│   │
│   ├── Reports/                        ← Research documents
│   ├── artifacts/                      ← Hardhat compilation artifacts (generated)
│   ├── hardhat.config.js               ← Solidity 0.8.20 + ESM config
│   ├── package.json                    ← "type": "module" required
│   ├── deployed-addresses.json         ← Contract addresses (written by deploy.js)
│   └── gas-report.txt                  ← Gas cost report (generated by tests)
│
└── network/                            ← Project automation scripts
    ├── start_project.sh                ← Full project startup (11 automated steps)
    ├── stop_project.sh                 ← Graceful shutdown (+  --clean option)
    ├── status.sh                       ← Live status check for all services
    ├── run_test.sh                     ← Fabric chaincode integration test only
    └── logs/                           ← Runtime logs (created automatically)
        ├── fabric_network.log
        ├── chaincode_deploy.log
        ├── hardhat_node.log
        ├── hardhat_tests.log
        ├── oracle_bridge.log
        └── integration_test.log
```

---

## 13. Prerequisites

### Ethereum PDC

- **Node.js ≥ 20 LTS** — `node --version`
- **npm ≥ 10** — `npm --version`
- **Hardhat** — installed via `npm install` inside `Blockchain/`

### Hyperledger Fabric UOC

- **Go 1.21** — `go version`
  > `go.mod` must declare `go 1.21` (major.minor only). Fabric's Docker builder rejects patch versions like `go 1.21.13`. The `start_project.sh` script auto-corrects this.
  >
- **Docker ≥ 25 + Docker Compose v2** — `docker --version`
- **Hyperledger Fabric 2.5 binaries** — installed at `~/fabric/fabric-samples/`
- **`jq`** and **`curl`**

> **Docker 25+ fix required.** Docker 23+ enables the containerd snapshotter by default, which breaks Fabric v2.5's legacy chaincode builder (`write unix @->/run/docker.sock: write: broken pipe`). Fix:
>
> ```bash
> sudo tee /etc/docker/daemon.json <<'EOF'
> { "features": { "containerd-snapshotter": false } }
> EOF
> sudo systemctl restart docker
> ```

> **Fabric image fix.** After Docker restart, pull the builder images used by the peer:
>
> ```bash
> docker pull hyperledger/fabric-ccenv:3.1
> docker pull hyperledger/fabric-baseos:3.1
> ```

### Oracle Bridge and Simulation

- **Node.js ≥ 20** (for `oracle/bridge.js`)
- **Python 3.12** (for `simulation/`)
- **web3 Python package** (optional, for `uav_agent.py`):
  ```bash
  pip install web3 --break-system-packages
  ```

### Benchmarking

- **Hyperledger Caliper 0.6.0** — installed via `npm install`
- Fabric network running with `dcbachannel` active

---

## 14. Quick Start — Automated

The `network/` directory contains four automation scripts that manage the entire project lifecycle. **All scripts can be run from any directory** — they resolve all paths internally using `$(dirname "$0")`.

```bash
# Make scripts executable once
chmod +x ~/dcba/network/*.sh
```

### `start_project.sh` — Full Startup (11 steps)

```bash
bash ~/dcba/network/start_project.sh
```

What it does in order:

| Step | Action                                                                |
| ---- | --------------------------------------------------------------------- |
| 0    | Pre-flight checks (Node, Go, Docker, peer binary, paths)              |
| 1    | Build Go chaincode — auto-fix `go.mod` patch version if needed     |
| 2    | Start Hyperledger Fabric test-network + create `dcbachannel`        |
| 3    | Deploy `dcba-uoc` v2.0 Go chaincode to Fabric                       |
| 4    | Start Hardhat local Ethereum node (background, port 8545)             |
| 5    | Deploy all 7 Solidity contracts — writes `deployed-addresses.json` |
| 6    | Start Oracle Bridge (background)                                      |
| 7    | Run full Hardhat test suite (116 tests)                               |
| 8    | Run end-to-end integration test (`test_flow.js`)                    |
| 9    | Run Fabric chaincode live tests (Bloom filter + PARS priority queue)  |
| 10   | Run DCS fleet simulation (Python)                                     |
| 11   | Run Hyperledger Caliper benchmark                                     |

**Options:**

```bash
bash start_project.sh --skip-deploy    # Skip chaincode/contract deploy (use existing)
bash start_project.sh --tests-only     # Only run tests, skip all network startup
bash start_project.sh --skip-caliper   # Skip Caliper benchmark (faster run)
bash start_project.sh --help           # Show usage
```

### `status.sh` — Live Status Check

```bash
bash ~/dcba/network/status.sh
```

Shows the current state of every component: Hardhat node, deployed contract addresses, Oracle Bridge process, Fabric peer/orderer containers, chaincode container, and all log files.

### `stop_project.sh` — Shutdown

```bash
bash ~/dcba/network/stop_project.sh           # Stop all processes, keep data
bash ~/dcba/network/stop_project.sh --clean   # Stop + full wipe (fresh restart)
```

`--clean` removes Docker volumes, Fabric crypto material, Hardhat cache/artifacts, and `deployed-addresses.json`.

### `run_test.sh` — Fabric Chaincode Test Only

```bash
bash ~/dcba/network/run_test.sh
```

Deploys the chaincode (if not already deployed) and runs a live test: Bloom filter add/check, DCS round open/score/close/winner query.

---

## 15. Manual Setup — Ethereum PDC

```bash
cd ~/dcba/Blockchain

# Install Node.js dependencies
npm install

# Terminal 1: Start local Hardhat node (keeps running)
npx hardhat node

# Terminal 2: Deploy all 7 contracts in correct order
npx hardhat run scripts/deploy.js --network localhost

# Run full test suite (116 tests across 11 files)
npx hardhat test

# Run end-to-end flow test
npx hardhat run scripts/test_flow.js --network localhost

# View gas report
cat gas-report.txt
```

Deployed contract addresses are written to `deployed-addresses.json`.

### Critical Deployment Steps

Two linking calls **must** be made after deployment or the system will fail:

```javascript
// Step 5 — Authorise SC-3 to register prescription hashes in SC-7
await SC7.setSC3Address(SC3.address);

// Step 9 — Authorise SC-6 to call updateReputation in SC-4
await SC4.linkSC6(SC6.address);
```

Both are handled automatically by `deploy.js`.

### Full Deployment Order

| Step        | Action                                                   |
| ----------- | -------------------------------------------------------- |
| 1           | Deploy SC-1 (no args)                                    |
| 2           | Deploy SC-7 (no args)                                    |
| 3           | Deploy SC-2 (SC-1 address)                               |
| 4           | Deploy SC-3 (SC-1, SC-2, SC-7 addresses)                 |
| **5** | **`SC7.setSC3Address(SC3_address)` ← CRITICAL** |
| 6           | Deploy SC-4 (SC-1 address)                               |
| 7           | Deploy SC-5 (SC-1, SC-7 addresses)                       |
| 8           | Deploy SC-6 (SC-1, SC-4 addresses)                       |
| **9** | **`SC4.linkSC6(SC6_address)` ← CRITICAL**       |

---

## 16. Manual Setup — Hyperledger Fabric UOC

```bash
# Step 1: Build and verify chaincode compiles
cd ~/dcba/Blockchain/chaincode/dcba-uoc
go mod tidy
go build ./...

# Step 2: Start Fabric test-network and create channel
cd ~/fabric/fabric-samples/test-network
./network.sh up createChannel -c dcbachannel

# Step 3: Deploy dcba-uoc chaincode (v2.0 includes Bloom filter + OrdersContract)
./network.sh deployCC \
  -ccn dcba-uoc \
  -ccp ~/dcba/Blockchain/chaincode/dcba-uoc \
  -ccl go \
  -c dcbachannel \
  -ccv 2.0
```

**Expected output on success:**

```
Chaincode is installed on peer0.org1  ✓
Chaincode is installed on peer0.org2  ✓
Chaincode definition committed on channel 'dcbachannel'  ✓
Approvals: [Org1MSP: true, Org2MSP: true]  ✓
```

### Set Peer CLI Environment

```bash
export PATH=~/fabric/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=~/fabric/fabric-samples/config/
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=\
  ~/fabric/fabric-samples/test-network/organizations/peerOrganizations/\
  org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=\
  ~/fabric/fabric-samples/test-network/organizations/peerOrganizations/\
  org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
```

### Tear Down

```bash
cd ~/fabric/fabric-samples/test-network
./network.sh down
```

---

## 17. Oracle Bridge

The bridge is a Node.js process that listens for `RecordAdded` events from SC-3 and verifies the prescription hash status in SC-7. It measures end-to-end cross-chain relay latency.

**Prerequisites:** Hardhat node running and contracts deployed.

```bash
cd ~/dcba/Blockchain
node oracle/bridge.js
```

**Sample output:**

```
DCBA Oracle Bridge started
   SC3: 0x68B1D87F95878fE05B998F19b66F4baba5De1aed
   SC7: 0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1
────────────────────────────────────────────────────
Listening for SC3 RecordAdded events...

[2026-03-28T10:00:01Z] RecordAdded event caught!
   recordId : 1
   rxHash   : 0xc56d4e8b...
   parsScore: 95
   SC7 status: VALID
   Latency: 16ms
   Total relayed: 1 | Avg: 16ms
```

> **Latency:** 16 ms on local Hardhat. Expected ~5.4 seconds in a cross-host production deployment (PDC Ethereum node → relay server → UOC Fabric peer).

---

## 18. Benchmarks — Hyperledger Caliper

```bash
cd ~/dcba/Blockchain

# First time only
npm install
npx caliper bind --caliper-bind-sut fabric:2.5

# Run benchmark
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig benchmark/network.yaml \
  --caliper-benchconfig benchmark/benchmark.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled
```

> `benchmark/network.yaml` must use `version: "1.0"` (not `"2.0"`) — Caliper 0.6 rejects version 2.0.

**Benchmark rounds:**

| Round                | Operations                                              | Send Rate | Transactions |
| -------------------- | ------------------------------------------------------- | --------- | ------------ |
| open-and-score-round | OpenRound + SubmitScore×3 + CloseRound                 | 5 TPS     | 50           |
| delivery-lifecycle   | CreateDelivery + SetInFlight + LogGPS + ConfirmDelivery | 5 TPS     | 50           |
| query-winner         | GetDelivery (read-only)                                 | 20 TPS    | 100          |

**Typical results:**

```
+----------------------+------+------+-----------------+-----------------+------------------+
| Name                 | Succ | Fail | Send Rate (TPS) | Avg Latency (s) | Throughput (TPS) |
|----------------------|------|------|-----------------|-----------------|------------------|
| open-and-score-round | 80   | 0    | 7.3             | 1.18            | 5.9              |
| delivery-lifecycle   | 64   | 0    | 5.4             | 1.31            | 4.4              |
| query-winner         | 100  | 0    | 20.4            | 0.00            | 20.4             |
+----------------------+------+------+-----------------+-----------------+------------------+
```

HTML report saved to `report.html` after each run.

---

## 19. Smart Contract Reference

### Dependency Graph

```
SC1_IdentityRegistry  ← no deps — deploy first
       ▲
       │ isActive(), getRole()
  ┌────┼────────────────────────────────┐
  │    │                                │
 SC2  SC3 ──► SC7.registerHash()       SC4   SC7 ← no deps — deploy second
                                              ▲
SC5 ──► SC7.verifyHash()                     │ linkSC6()
SC6 ──► SC4.updateReputation() ──────────────┘
```

### SC-1 Functions

```solidity
register(address who, string role, string publicKeyHash)  // TA only
revoke(address who, string reason)                        // TA only
isActive(address who) → bool
getRole(address who) → string
transferTA(address newTA)                                 // TA only
```

### SC-2 Functions

```solidity
grantAccess(address hp, uint256 durationDays)             // Patient; 0 = indefinite
revokeAccess(address hp)                                  // Patient only
hasAccess(address hp, address patient) → bool
getConsentInfo(address patient, address hp)
  → (bool active, uint256 grantedAt, uint256 expiresAt)
```

### SC-3 Functions

```solidity
addRecord(address patient, string encryptedDataHash, uint8 parsScore, bytes32 rxHash)
getRecord(uint256 recordId)
  → (address hp, address patient, string hash, uint8 parsScore, bytes32 rxHash, uint256 timestamp)
getPatientRecordIds(address patient) → uint256[]
getParsLabel(uint8 parsScore) → string   // "CRITICAL" | "HIGH" | "MODERATE" | "LOW"
```

### SC-4 Functions (v2 — with Bloom Filter)

```solidity
// DCS Scoring
computeScore(uint256 speed, uint256 payload, uint256 battery, uint256 cpu, uint256 ram) → uint256
openRound(uint256 orderId) → uint256 roundId
submitScore(uint256 roundId, uint256 score)  // Phase 1: Bloom, Phase 2: SC-1
closeRound(uint256 roundId)
getWinner(uint256 roundId) → (address winner, uint256 score)
getRoundStats(uint256 roundId) → (uint256 accepted, uint256 rejectedBloom, uint256 rejectedSig)

// Bloom Filter
addUAVToBloom(address uav)                   // Call after SC1.register() for new UAV
rebuildBloomFilter(address[] activeUAVs)     // Rebuild after any revocation
bloomCheck(address uav) → bool

// Reputation
updateReputation(address uav, int256 delta)  // SC6 (via linkSC6) or registered actor
linkSC6(address sc6)                         // TA calls once after SC6 deployment
```

### SC-5 Functions (v2 — with PARS Priority Queue)

```solidity
// Orders
submitOrder(address patient, bytes32 rxHash, uint8 parsScore, string drugList,
            address warehouse, address droneStation) → uint256 orderId
confirmStock(uint256 orderId)                // Assigned warehouse only
assignUAV(uint256 orderId, address uav)      // Drone Station only
updateStatus(uint256 orderId, OrderStatus newStatus)
getOrder(uint256 orderId)
  → (address hp, address patient, uint8 parsScore, string drugList,
     address assignedUAV, OrderStatus status, uint256 slaDeadline)

// PARS Priority Queue
getHighestPriorityOrder() → (uint256 orderId, uint8 parsScore, string tier, uint256 slaDeadline)
getPendingOrdersSorted() → (uint256[] sortedIds, uint8[] scores, string[] tiers)
getPendingCountByTier() → (uint256 critical, uint256 high, uint256 moderate, uint256 low)
getOverduePendingOrders() → uint256[] overdueIds

// Helpers
getSLASeconds(uint8 parsScore) → uint256
getParsLabel(uint8 parsScore) → string  // "CRITICAL - 3min SLA" | "HIGH - 10min SLA" | ...
```

### SC-6 Functions

```solidity
createDelivery(uint256 orderId, address uav, address patient, uint256 slaDeadline)
setInFlight(uint256 orderId)
logGPS(uint256 orderId, string ipfsHash)
flagDeviation(uint256 orderId, string reason)    // DS only → UAV reputation −10
confirmDelivery(uint256 orderId)                 // Patient only → UAV reputation +5 or −5
getDeliveryStatus(uint256 orderId)
  → (DeliveryStatus status, address uav, uint256 gpsUpdateCount, bool withinSLA, bool deviated)
getGPSLog(uint256 orderId) → (string[] hashes, uint256[] timestamps)
```

### SC-7 Functions

```solidity
setSC3Address(address sc3)                       // TA only — call after SC3 deployment
registerHash(bytes32 rxHash, address hp)         // SC3 only; PENDING → VALID
verifyHash(bytes32 rxHash) → bool                // SC5; VALID → USED (one-time)
checkHash(bytes32 rxHash) → uint8                // Read-only: 0=PENDING 1=VALID 2=USED
```

---

## 20. Chaincode Reference (Fabric CLI)

```bash
# ── DCS Scoring ──────────────────────────────────────────────────────────────

# Add UAV to Bloom filter (call after SC1.register)
peer chaincode invoke ... -c '{"function":"DCSContract:AddUAVToBloom","Args":["uav-001"]}'

# Check Bloom filter
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:BloomCheck","Args":["uav-001"]}'

# Open DCS scoring round
peer chaincode invoke ... -c '{"function":"DCSContract:OpenRound","Args":["round-001","order-001"]}'

# Submit score (Phase 1: Bloom, Phase 2: active check)
peer chaincode invoke ... -c '{"function":"DCSContract:SubmitScore","Args":["round-001","uav-001","82"]}'

# Close round and select winner
peer chaincode invoke ... -c '{"function":"DCSContract:CloseRound","Args":["round-001"]}'

# Query winner
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:GetWinner","Args":["round-001"]}'

# Get round stats (accepted / rejectedBloom / rejectedSig)
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"DCSContract:GetRoundStats","Args":["round-001"]}'

# ── Delivery Lifecycle ────────────────────────────────────────────────────────

# Create delivery
peer chaincode invoke ... \
  -c '{"function":"LifecycleContract:CreateDelivery","Args":["order-001","uav-001","patient-001","9999999999"]}'

# Set in-flight
peer chaincode invoke ... -c '{"function":"LifecycleContract:SetInFlight","Args":["order-001"]}'

# Log GPS coordinate
peer chaincode invoke ... -c '{"function":"LifecycleContract:LogGPS","Args":["order-001","QmGPSHashXyz"]}'

# Confirm delivery
peer chaincode invoke ... -c '{"function":"LifecycleContract:ConfirmDelivery","Args":["order-001"]}'

# Get full delivery record
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"LifecycleContract:GetDelivery","Args":["order-001"]}'

# ── PARS Priority Queue ───────────────────────────────────────────────────────

# Submit order (parsScore=95 → CRITICAL tier)
peer chaincode invoke ... \
  -c '{"function":"OrdersContract:SubmitOrder","Args":["order-001","hp-001","patient-001","rx-001","95","Insulin","warehouse-001","ds-001"]}'

# Submit low-priority order (parsScore=20 → LOW tier)
peer chaincode invoke ... \
  -c '{"function":"OrdersContract:SubmitOrder","Args":["order-002","hp-001","patient-001","rx-002","20","Vitamins","warehouse-001","ds-001"]}'

# Get highest priority order from list
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"OrdersContract:GetHighestPriorityOrder","Args":["order-001","order-002"]}'

# Get all pending orders sorted by PARS tier
peer chaincode query -C dcbachannel -n dcba-uoc \
  -c '{"function":"OrdersContract:GetPendingOrdersSorted","Args":["order-001","order-002"]}'
```

---

## 21. Security Design

### Threat Model and Mitigations

| Threat                                            | Mitigation                                                                  | Enforcement       |
| ------------------------------------------------- | --------------------------------------------------------------------------- | ----------------- |
| Prescription replay (same rxHash → 2 deliveries) | SC-7 marks hash USED after first verification                               | SC-7              |
| Unregistered actor writes medical record          | `isActive()` check in SC-3                                                | SC-1, SC-3        |
| Revoked HP writes after revocation                | `isActive()` returns false immediately                                    | SC-1              |
| Fake UAV submits DCS score                        | Phase 1: Bloom O(1); Phase 2: SC-1 identity check                           | SC-4              |
| UAV hardware cloning                              | `h = H(mac ‖ τs ‖ seed)` — different MAC → different DID             | Hardware + SC-1   |
| HP writes without patient consent                 | `SC2.hasAccess()` called atomically in `SC3.addRecord()`                | SC-2, SC-3        |
| TA authority hijack                               | `onlyTA` modifier on `transferTA()`                                     | SC-1              |
| Direct oracle manipulation                        | `registerHash()` restricted to SC-3 via `setSC3Address()`               | SC-7              |
| Wrong DS closes scoring round                     | DS address stored at `openRound()`                                        | SC-4              |
| Rogue warehouse confirms stock                    | Warehouse address stored per order                                          | SC-5              |
| GPS spoofing                                      | IPFS content addressing — modifying GPS data changes the CID               | IPFS + SC-6       |
| PARS score inflation                              | RA monitors SC-3/SC-5 for statistical anomalies                             | RA monitoring     |
| MVCC conflicts (Fabric)                           | Unique ledger key per transaction (`workerIndex + txCounter + timestamp`) | Caliper workloads |

### Security Test Coverage (`Security.test.js` — 10 tests, all passing)

| Test      | Scenario                                       | Expected Revert                                                    |
| --------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| TC-SEC-01 | Same rxHash used for two delivery orders       | `"Prescription not verified by SC-7 oracle"`                     |
| TC-SEC-02 | Unregistered actor writes medical record       | `"HP not registered in SC-1"`                                    |
| TC-SEC-03 | Revoked HP writes medical record               | `"HP not registered in SC-1"`                                    |
| TC-SEC-04 | Unregistered UAV submits DCS score             | `"Phase 1 failed: UAV not in Bloom filter"`                      |
| TC-SEC-05 | Attacker confirms another patient's delivery   | `"Only the patient can confirm delivery"`                        |
| TC-SEC-06 | HP writes record without patient consent       | `"No patient consent - patient must call SC2.grantAccess first"` |
| TC-SEC-07 | Non-TA attempts to transfer TA authority       | `"Only TA can do this"`                                          |
| TC-SEC-08 | Attacker directly injects hash into SC-7       | `"Only SC-3 can register"`                                       |
| TC-SEC-09 | Different DS closes another DS's round         | `"Only the DS that opened this round"`                           |
| TC-SEC-10 | Rogue warehouse confirms another order's stock | `"Only the assigned warehouse"`                                  |

---

## 22. Gas Costs

All measured on Hardhat local network (Solidity 0.8.20, optimizer 200 runs, block limit 60,000,000).

### Deployment Costs

| Contract                              | Gas Used            | % of Block Limit |
| ------------------------------------- | ------------------- | ---------------- |
| SC-1 IdentityRegistry                 | 660,784             | 1.1%             |
| SC-2 PatientConsent                   | 429,015             | 0.7%             |
| SC-3 MedicalRecords                   | 873,476             | 1.5%             |
| SC-4 DCSScoring (v2 + Bloom)          | 997,739             | 1.7%             |
| SC-5 DeliveryOrders (v2 + PARS queue) | 1,375,158           | 2.3%             |
| SC-6 DeliveryLifecycle                | 1,328,993           | 2.2%             |
| SC-7 OracleBridge                     | 383,565             | 0.6%             |
| **Total**                       | **6,048,730** | **~10.1%** |

### Function Costs (from `gas-report.txt`)

| Contract | Function             | Min Gas | Max Gas | Avg Gas |
| -------- | -------------------- | ------- | ------- | ------- |
| SC-1     | `register`         | 118,544 | 118,736 | 118,617 |
| SC-1     | `revoke`           | 27,503  | 27,635  | 27,561  |
| SC-2     | `grantAccess`      | 67,055  | 101,267 | 100,367 |
| SC-2     | `revokeAccess`     | —      | —      | 23,924  |
| SC-3     | `addRecord`        | 289,998 | 324,306 | 321,488 |
| SC-4     | `openRound`        | —      | —      | 104,650 |
| SC-4     | `submitScore`      | 154,711 | 188,911 | 185,111 |
| SC-4     | `closeRound`       | 88,674  | 99,869  | 91,473  |
| SC-4     | `updateReputation` | 53,773  | 54,145  | 53,959  |
| SC-5     | `submitOrder`      | 369,551 | 369,628 | 369,576 |
| SC-5     | `confirmStock`     | —      | —      | 49,039  |
| SC-5     | `assignUAV`        | —      | —      | 40,012  |
| SC-6     | `createDelivery`   | 176,949 | 176,961 | 176,952 |
| SC-6     | `setInFlight`      | —      | —      | 30,505  |
| SC-6     | `logGPS`           | 84,154  | 118,582 | 107,054 |
| SC-6     | `flagDeviation`    | —      | —      | 95,657  |
| SC-6     | `confirmDelivery`  | —      | —      | 120,122 |
| SC-7     | `setSC3Address`    | 46,031  | 46,043  | 46,042  |
| SC-7     | `verifyHash`       | 50,723  | 50,735  | 50,729  |

> `SC-5.submitOrder` is the most expensive function (369,576 gas) because it atomically calls `SC7.verifyHash()` and stores the full order in one transaction. `SC-6.logGPS` reaching 118,582 gas at maximum is the primary motivation for the PDC/UOC split.

---

## 23. Performance Results

### DCS Selection Latency

| Fleet Size | Round Time        | ≤ 140 ms?                |
| ---------- | ----------------- | ------------------------- |
| 10 UAVs    | 0.89 ms           | ✓                        |
| 25 UAVs    | 3.71 ms           | ✓                        |
| 50 UAVs    | 4.32 ms           | ✓                        |
| 75 UAVs    | 7.88 ms           | ✓                        |
| 100 UAVs   | **8.37 ms** | ✓ — 16.7× below target |

### Oracle Bridge Latency

| Deployment                                 | Latency |
| ------------------------------------------ | ------- |
| Local (Hardhat → Hardhat)                 | ~16 ms  |
| Cross-host (PDC node → relay → UOC peer) | ~5.4 s  |

### Caliper Throughput (Fabric UOC)

| Workload                       | Throughput | Avg Latency |
| ------------------------------ | ---------- | ----------- |
| DCS scoring round              | 5.9 TPS    | 1.18 s      |
| Delivery lifecycle             | 4.4 TPS    | 1.31 s      |
| Read queries (`GetDelivery`) | 20.4 TPS   | < 10 ms     |

---

## 24. Known Issues and Bug Fixes

### Bug 1 — CRITICAL: `SC4.updateReputation` fails when called from SC6

**Problem:** SC6 calls `SC4.updateReputation()` on delivery confirmation and deviation flagging. Inside SC4, `msg.sender` is the SC6 contract address. SC4 checks `SC1.isActive(msg.sender)` — but SC6 is a contract, not a registered actor → reverts every time. `confirmDelivery()` and `flagDeviation()` in SC6 **always failed** without this fix.

**Fix applied:** Added `sc6Address` storage and `linkSC6(address)` to SC4. Reputation update now accepts calls from a registered actor **or** the linked SC6 address:

```solidity
require(sc1.isActive(msg.sender) || msg.sender == sc6Address, "Caller not authorized");
```

**Action required at deployment:** Call `SC4.linkSC6(SC6_address)` after both contracts are deployed. Handled automatically in `deploy.js` step 9.

---

### Bug 2 — CRITICAL: `SC7.registerHash` always reverts (missing `setSC3Address`)

**Problem:** SC7 initialises `sc3Address = address(0)`. `registerHash()` checks `msg.sender == sc3Address`, which is always false until `setSC3Address()` is called. Every `SC3.addRecord()` silently failed.

**Fix applied:** Not a code bug — a deployment procedure gap. `setSC3Address(address)` already existed in SC7 but was not being called.

**Action required at deployment:** Call `SC7.setSC3Address(SC3_address)` immediately after SC3 is deployed. Handled automatically in `deploy.js` step 5.

---

### Bug 3 — MINOR: Unused `ISC5` interface in SC6

**Problem:** `interface ISC5` was declared in SC6 but never instantiated or used — dead code that increased deployment gas.

**Fix applied:** Removed the unused `ISC5` interface block from SC6.

---

### Bug 4 — Docker 25+ breaks Fabric chaincode installation

**Problem:** Docker 23+ enables BuildKit and containerd snapshotter by default. Hyperledger Fabric v2.5's peer uses the legacy Docker build API which fails with `write unix @->/run/docker.sock: write: broken pipe`.

**Fix applied:**

```bash
sudo tee /etc/docker/daemon.json <<'EOF'
{ "features": { "containerd-snapshotter": false } }
EOF
sudo systemctl restart docker
```

---

### Bug 5 — Fabric peer image version mismatch after Docker restart

**Problem:** After Docker restart, `fabric-peer:latest` may resolve to v3.x, but local Fabric binaries are v2.5. The peer container looks for `hyperledger/fabric-ccenv:3.1` which doesn't exist locally → chaincode build fails.

**Fix applied:**

```bash
docker pull hyperledger/fabric-ccenv:3.1
docker pull hyperledger/fabric-baseos:3.1
```

---

### Bug 6 — MVCC conflicts in Caliper workloads

**Problem:** Original workload scripts created one shared round/delivery per worker and submitted many transactions to it concurrently. Fabric's MVCC rejected concurrent writes to the same ledger key (status code 11 = `MVCC_READ_CONFLICT`).

**Fix applied:** Each `submitTransaction()` call now creates a unique key using `workerIndex + txCounter + timestamp`:

```javascript
const roundId = `r-${workerIndex}-${txCounter}-${Date.now()}`;
```

---

### Bug 7 — `go.mod` patch version rejected by Fabric Docker builder

**Problem:** Fabric's chaincode Docker builder rejects `go.mod` files with patch versions like `go 1.21.13`. Only `go 1.21` (major.minor) is accepted.

**Fix applied:** `start_project.sh` auto-detects and corrects this at startup:

```bash
sed -i 's/^go \([0-9]*\.[0-9]*\)\.[0-9]*/go \1/' go.mod
```

---

*BUET M.Sc. Research Project — 2025–2026*
