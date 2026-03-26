# DCBA PROJECT — CLAUDE RESUME DOCUMENT
# Version: 1.0 | Date: March 23, 2026
# Purpose: For Claude to read at start of any new conversation to resume
#          this project with ZERO context loss.
# Usage: Paste this entire file into a new conversation and say "Resume DCBA project."
# ============================================================

## 0. WHO IS THE USER

- **Name:** Ankan Saha
- **Role:** Lecturer, CSE Department, Bangladesh University of Business and Technology (BUBT)
- **Also:** M.Sc. student at Bangladesh University of Engineering and Technology (BUET)
- **Research area:** Blockchain, IoT, Deep Learning, Computer Vision
- **Location:** Narayanganj, Dhaka, Bangladesh
- **Language:** Bengali + English mixed. Responds well to Bengali explanations for complex things.
- **GitHub:** https://github.com/AnkanSaha18/Blockchain
- **Communication style:** Direct, fast-paced. Pastes terminal output, expects quick diagnosis.

---

## 1. PROJECT IDENTITY

- **Full name:** DCBA — Dual-Chain Blockchain Architecture for Secure, Priority-Aware, UAV-Enabled Pharmaceutical Delivery
- **Institution:** BUET M.Sc. Research Project, 2025–2026
- **Supervisor context:** BUET M.Sc. (supervisor not named in conversation)
- **Repository:** https://github.com/AnkanSaha18/Blockchain (public, all code is here)
- **Stack:** Ethereum PoA (PDC) + Hyperledger Fabric 2.5 (UOC) + Node.js Oracle Bridge + Python simulation

---

## 2. THE CORE IDEA (ONE PARAGRAPH)

DCBA solves two problems simultaneously: (1) pharmaceutical supply chain fraud (counterfeit drugs kill ~1M/year, WHO reports 10% of drugs in LMICs are falsified), and (2) last-mile drug delivery failure in Bangladesh (Dhaka: 44,000 persons/km², gridlock). Solution: two purpose-specific blockchains — a **Patient Data Chain (PDC)** on Ethereum PoA for privacy-sensitive medical records, and a **UAV Operational Chain (UOC)** on Hyperledger Fabric for high-throughput drone logistics — connected by **SC-7**, a cross-chain oracle bridge. UAVs are selected via a two-phase **Drone Capability Score (DCS)** algorithm (Bloom filter + ECDSA). Deliveries are prioritized by **PARS** (Priority-Aware Routing System) with 4 clinical tiers (CRITICAL 3min → LOW 2hr SLA).

---

## 3. SYSTEM ACTORS (8 total)

| Actor | Chain | Key function |
|---|---|---|
| Trusted Authority (TA) | Both | Registers all actors, sole admin of SC-1 |
| Patient | PDC light + UOC observer | Grants consent, confirms delivery |
| Healthcare Provider (HP) | PDC full + UOC writer | Writes MBLOCK, submits delivery order |
| Drug Warehouse (DW) | UOC full | Confirms drug stock |
| Drone Station (DS) | UOC full | Opens/closes DCS rounds, monitors GPS |
| UAV | UOC IoT node | Computes DCS score, flies, logs GPS |
| Miner/Validator | Both infra | PoA consensus (PDC) / Raft (UOC) |
| Regulatory Auditor (RA) | Both read-only | Audits PARS anomalies, DGDA reports |

---

## 4. SEVEN SMART CONTRACTS

All Solidity contracts: `pragma solidity ^0.8.20`, optimizer 200 runs.

### PDC Contracts (Ethereum PoA / Hardhat)
| SC | File | Purpose | Depends on |
|---|---|---|---|
| SC-1 | SC1_IdentityRegistry.sol | DID registry for all actors. `isActive()` called by every other contract. Deploy FIRST. | None |
| SC-2 | SC2_PatientConsent.sol | Time-limited HP consent tokens. `grantAccess(hp, durationDays)` / `revokeAccess(hp)` | SC-1 |
| SC-3 | SC3_MedicalRecords.sol | MBLOCK store. Triple gate: SC-1 identity + SC-2 consent + PARS range. Auto-calls SC-7.registerHash() | SC-1, SC-2, SC-7 |
| SC-7 | SC7_OracleBridge.sol | rxHash state machine: PENDING→VALID→USED. Replay prevention. | SC-3 only (via setSC3Address) |

### UOC Contracts (Hyperledger Fabric / Go chaincode)
| SC | File | Purpose | Depends on |
|---|---|---|---|
| SC-4 | SC4_DCSScoring.sol | DCS scoring rounds. Bloom filter Phase1 + ECDSA Phase2. openRound/closeRound/getWinner/updateReputation | SC-1 |
| SC-5 | SC5_DeliveryOrders.sol | PARS queue. submitOrder calls SC7.verifyHash. getSLASeconds(score). | SC-1, SC-7 |
| SC-6 | SC6_DeliveryLifecycle.sol | State machine: DISPATCHED→IN_FLIGHT→DELIVERED. logGPS stores IPFS hashes. | SC-1, SC-4 |

### CRITICAL DEPLOYMENT ORDER
```
1. Deploy SC-1
2. Deploy SC-7
3. Deploy SC-2 (pass SC-1 address)
4. Deploy SC-3 (pass SC-1, SC-2, SC-7 addresses)
5. CALL: SC7.setSC3Address(SC3_address)   ← MUST NOT SKIP
6. Deploy SC-4 (pass SC-1 address)
7. Deploy SC-5 (pass SC-1, SC-7 addresses)
8. Deploy SC-6 (pass SC-1, SC-4 addresses)
9. CALL: SC4.linkSC6(SC6_address)         ← MUST NOT SKIP (bug fix)
```

### BUGS FOUND AND FIXED
- **Bug 1 (CRITICAL):** SC4.updateReputation() had `require(sc1.isActive(msg.sender))` — SC6's contract address is not in SC-1, so `confirmDelivery()` and `flagDeviation()` always reverted. **Fix:** Added `sc6Address` state var + `linkSC6()` function. SC6 contract address is now authorized.
- **Bug 2 (CRITICAL):** SC7.sc3Address defaults to address(0). If TA forgets `setSC3Address()`, SC3.addRecord() always reverts. **Fix:** Deployment procedure — call setSC3Address after deploying SC3.
- **Bug 3 (MINOR):** SC6 had unused `ISC5` interface (dead code). **Fix:** Removed.

---

## 5. DCS FORMULA

```
score = (speed×30 + payload×25 + battery×20 + cpu×15 + ram×10) / 100
```
All inputs 0-100. Result 0-100. `computeScore()` is `pure` — UAVs can call it off-chain.

**Two-phase submission:**
1. UAV encrypts: ε = Enc(cs, keypub_DS)
2. UAV signs: σ = Sign(ε, keypri_UAV)
3. Submits (ε, σ) to SC-4
4. Phase 1: Bloom filter screens unregistered DIDs O(1)
5. Phase 2: ECDSA verifies σ against SC-1's stored keypub
6. DS decrypts all verified ε, selects argmax → υpremium

**Bloom filter params:** n=100 UAVs, ε=0.01 FP rate, k=7 hash functions, m=959 bits (1024 used).

---

## 6. PARS TIERS

| Tier | Score | SLA | Clinical examples |
|---|---|---|---|
| CRITICAL | 90-100 | 3 min | Insulin, epinephrine, cardiac meds |
| HIGH | 70-89 | 10 min | Antibiotics for sepsis, anti-coagulants |
| MODERATE | 40-69 | 30 min | Routine prescriptions, maintenance drugs |
| LOW | 0-39 | 2 hr | OTC, elective, non-urgent refills |

SLA seconds in SC-5: CRITICAL=180, HIGH=600, MODERATE=1800, LOW=7200.

---

## 7. HARDWARE-BOUND UAV IDENTITY

```
h° = H(mac ‖ τs ‖ seed)
```
- `mac` = hardware MAC address (non-changeable NIC)
- `τs` = manufacture timestamp (factory-recorded)
- `seed` = TA-issued secret (never stored in UAV firmware)
- DID: `did:dcba:uav:H(keypub_UAV)` where keypub derived from h°
- Stealing private key + installing on different device = different MAC → different h° → SC-1 rejects

---

## 8. ORACLE BRIDGE (SC-7) FLOW

```
SC-3.addRecord() → SC-7.registerHash(rxHash) [same tx, atomic]
rxHash: PENDING → VALID

Node.js bridge listens: sc3.on("RecordAdded", ...) 
→ calls sc7.verifyHash(rxHash) → VALID → USED

SC-5.submitOrder() → SC-7.verifyHash() 
→ if USED already: revert ("Prescription not verified")
→ if VALID: mark USED, create order
```
Measured oracle relay latency: **16ms** (local Hardhat), expected ~5.4s in cross-host deployment.

---

## 9. IMPLEMENTATION STATUS — ALL PHASES COMPLETE

| Phase | Status | Key results |
|---|---|---|
| Phase 0: Environment Setup | ✅ DONE | Node.js 20, Hardhat, Go 1.21, Docker, Fabric 2.5, Python 3.12, Ubuntu 24.04 |
| Phase 1: PDC Smart Contracts | ✅ DONE | 86/86 tests passing, 0 failures, both macOS + Ubuntu |
| Phase 2: UOC Fabric Chaincode | ✅ DONE | Deployed on dcbachannel, Org1MSP + Org2MSP approved |
| Phase 3: Oracle Bridge | ✅ DONE | 16ms relay latency, replay prevention confirmed |
| Phase 4: UAV Fleet Simulation | ✅ DONE | 100 UAVs in 8.37ms (target was <140ms) |
| Phase 5: Caliper Benchmarking | ✅ DONE | 0 failures across 244 transactions, 3 rounds |
| Phase 6: Security Analysis | ✅ DONE | 10/10 attack vectors blocked, 0 false negatives |
| Phase 7: Paper Writing | ✅ DONE | Full ACM SIGPLAN LaTeX paper generated |
| Extension: Simulation Feasibility | ✅ DONE | Feasibility report: custom Python stack recommended |

---

## 10. TEST SUITE — 86 TESTS, 0 FAILURES

| Suite | Tests |
|---|---|
| SC-1 Identity Registry | 7 |
| SC-2 Patient Consent | 12 |
| SC-3 Medical Records | 8 |
| SC-4 DCS Scoring | 10 |
| SC-5 Delivery Orders | 9 |
| SC-6 Delivery Lifecycle | 10 |
| SC-7 Oracle Bridge | 8 |
| Security Attacks | 10 |
| Gas Cost Benchmark | 12 |
| **TOTAL** | **86 / 86** |

Security tests cover: TC-SEC-01 to TC-SEC-10 (replay attack, unregistered actor, revoked HP, fake UAV, wrong patient, no consent, TA hijack, direct oracle manipulation, wrong DS, wrong warehouse).

---

## 11. GAS COSTS (PDC — Hardhat local, optimizer 200 runs)

| Contract | Function | Gas |
|---|---|---|
| SC-1 | register() | 118,652 |
| SC-1 | revoke() | 27,515 |
| SC-2 | grantAccess() | 101,267 |
| SC-2 | revokeAccess() | 23,924 |
| SC-3 | addRecord() CRITICAL | 324,306 |
| SC-4 | openRound() | 104,650 |
| SC-4 | submitScore() | 188,911 |
| SC-4 | closeRound() 1 UAV | 88,674 |
| SC-5 | submitOrder() | 369,599 ← highest |
| SC-5 | confirmStock() | 49,039 |
| SC-6 | logGPS() | 118,582 |
| SC-6 | confirmDelivery() | 120,122 |

Note: SC5.submitOrder highest because it calls SC1.isActive() + SC7.verifyHash() + writes full DeliveryOrder struct. SC6.logGPS high — motivates GPS logging being on Fabric UOC in production.

---

## 12. CALIPER BENCHMARK RESULTS (Fabric 2.5, dcbachannel, 2 workers)

| Round | Succ | Fail | TPS sent | Avg lat | Max lat | Throughput |
|---|---|---|---|---|---|---|
| open-and-score-round | 80 | 0 | 5.4 | 1.27s | 2.59s | 4.6 TPS |
| delivery-lifecycle | 64 | 0 | 5.4 | 1.25s | 2.61s | 4.4 TPS |
| query-winner | 100 | 0 | 20.4 | 0.00s | 0.01s | 20.4 TPS |
| **Total** | **244** | **0** | | | | |

---

## 13. DCS SCALABILITY RESULTS

| Fleet | Round time | Target |
|---|---|---|
| 10 UAVs | 0.89ms | ✅ <140ms |
| 25 UAVs | 3.71ms | ✅ <140ms |
| 50 UAVs | 4.32ms | ✅ <140ms |
| 75 UAVs | 7.88ms | ✅ <140ms |
| 100 UAVs | **8.37ms** | ✅ **94% below target** |

Method: Python threading, `compute_dcs_score()` runs concurrently per UAV.

---

## 14. SECURITY ANALYSIS SUMMARY

All 10 attacks blocked:
1. Prescription replay → SC-7 USED status
2. Unregistered actor → SC-1 isActive() on every tx
3. Revoked HP writes → SC-1 revoke() immediate + isActive()
4. Fake UAV DCS → Bloom filter Phase1 + ECDSA Phase2
5. Wrong patient confirms → patient address stored at createDelivery()
6. HP without consent → SC-2.hasAccess() atomic in SC-3.addRecord()
7. TA authority hijack → onlyTA modifier on transferTA()
8. Direct oracle manipulation → setSC3Address() whitelist
9. Wrong DS closes round → droneStation stored at openRound()
10. Rogue warehouse → warehouse address stored per order

---

## 15. FILE STRUCTURE ON ANKAN'S LINUX PC

```
~/dcba/Blockchain/
├── contracts/          ← All 7 Solidity .sol files
├── chaincode/
│   └── dcba-uoc/       ← Go chaincode (go.mod has go 1.21 — NOT 1.21.13)
│       ├── main.go
│       ├── dcs_scoring.go
│       └── delivery_lifecycle.go
├── scripts/
│   ├── deploy.js       ← ESM format (import/export)
│   └── test_flow.js    ← ESM format
├── oracle/
│   └── bridge.js       ← Node.js event listener
├── simulation/
│   ├── fleet_sim.py    ← Threading version (NOT subprocess)
│   └── uav_agent.py    ← Single UAV agent
├── benchmark/
│   ├── network.yaml    ← Caliper config (version: "1.0" NOT "2.0")
│   ├── benchmark.yaml
│   └── workload/
│       ├── dcs_submit.js
│       └── gps_log.js
├── test/               ← 9 test files (SC1-SC7, Security, Gas)
├── hardhat.config.js   ← ESM: import not require; no HardhatUserConfig type
├── package.json        ← MUST have "type": "module"
└── deployed-addresses.json ← Written by deploy.js
```

**Fabric network location:**
```
~/fabric/fabric-samples/test-network/
```
Channel name: `dcbachannel`
Chaincode name: `dcba-uoc`

**Private key for Caliper:**
```
~/fabric/fabric-samples/test-network/organizations/peerOrganizations/
org1.example.com/users/Admin@org1.example.com/msp/keystore/
a678d29dafeac075cb91e48a5f77d51abf833213f83b22e44eb4ac0bb57f743b_sk
```

---

## 16. ENVIRONMENT DETAILS

### Mac (for PDC work only)
- macOS, limited disk space
- Path: `/Users/ankansaha/Academic Courses/BUET-MSc/April 2025/Blockchain/Project Proposal/Smart Contracts v2/`
- Can run: Hardhat compile, test, deploy to localhost
- Cannot run: Hyperledger Fabric (no Docker capacity)

### Linux PC (Ubuntu 24.04.4 LTS — primary dev machine)
- RAM: 12 GB | Model: ASUS VivoBook X509FA
- Hostname: `ankan-VivoBook-ASUSLaptop-X509FA-X509FA`
- Username: `ankan`
- Node.js 20.20.1 | npm 10.8.2
- Go 1.21.13 (PATH: `/usr/local/go/bin`)
- Python 3.12.3
- Docker 29.3.0 | Docker Compose v5.1.1
- OpenJDK 17.0.18

### Common ESM pitfalls for this project (ALREADY SOLVED)
- `package.json` must have `"type": "module"`
- `hardhat.config.js` must use `import` not `require`, no `HardhatUserConfig` type import
- All scripts use `import { ethers } from "hardhat"` and `import fs from "fs"`

---

## 17. HARDHAT COMMON COMMANDS

```bash
# Always from ~/dcba/Blockchain/
npx hardhat compile         # "Nothing to compile" = already compiled = OK
npx hardhat test            # All 86 tests
npx hardhat test test/SC1.test.js  # Single test file

# Terminal 1: Local blockchain node
npx hardhat node

# Terminal 2: Deploy
npx hardhat run scripts/deploy.js --network localhost

# Terminal 2: Oracle bridge (AFTER deploy, reads deployed-addresses.json)
node oracle/bridge.js

# Terminal 3: End-to-end test
npx hardhat run scripts/test_flow.js --network localhost
```

---

## 18. FABRIC COMMON COMMANDS

```bash
# Start network + create channel
cd ~/fabric/fabric-samples/test-network
./network.sh up createChannel -c dcbachannel

# Deploy chaincode (if go.mod has go 1.21 NOT 1.21.13)
./network.sh deployCC \
  -ccn dcba-uoc \
  -ccp ~/dcba/Blockchain/chaincode/dcba-uoc \
  -ccl go \
  -c dcbachannel

# Set env vars for peer CLI
export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=$PWD/../config/
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051

# Invoke DCS round
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile ${PWD}/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem \
  -C dcbachannel -n dcba-uoc \
  --peerAddresses localhost:7051 --tlsRootCertFiles ${PWD}/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
  --peerAddresses localhost:9051 --tlsRootCertFiles ${PWD}/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem \
  -c '{"function":"DCSContract:OpenRound","Args":["round-001","order-001"]}'

# Stop network
./network.sh down
```

---

## 19. CALIPER COMMANDS

```bash
cd ~/dcba/Blockchain
npx caliper bind --caliper-bind-sut fabric:2.5  # Only needed once

npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig benchmark/network.yaml \
  --caliper-benchconfig benchmark/benchmark.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled
```

**KNOWN ISSUES:**
- `network.yaml` version MUST be `"1.0"` not `"2.0"` (Caliper 0.6 rejects 2.0)
- `go.mod` in chaincode MUST say `go 1.21` not `go 1.21.13` (Fabric docker rejects patch version)

---

## 20. DELIVERABLES CREATED IN THIS CONVERSATION

| Deliverable | Status | Location/Format |
|---|---|---|
| 7 Solidity smart contracts | ✅ | GitHub: AnkanSaha18/Blockchain/contracts/ |
| 3 Go chaincodes | ✅ | GitHub: AnkanSaha18/Blockchain/chaincode/ |
| 86-test test suite | ✅ | GitHub: AnkanSaha18/Blockchain/test/ |
| deploy.js + test_flow.js | ✅ | GitHub: AnkanSaha18/Blockchain/scripts/ |
| Oracle bridge (bridge.js) | ✅ | GitHub: AnkanSaha18/Blockchain/oracle/ |
| UAV fleet simulator (Python) | ✅ | GitHub: AnkanSaha18/Blockchain/simulation/ |
| Caliper benchmark configs | ✅ | GitHub: AnkanSaha18/Blockchain/benchmark/ |
| Gas cost table (docx) | ✅ | DCBA_Gas_Cost_Table.docx |
| Enhanced Caliper report (HTML) | ✅ | report.html (full visual dashboard) |
| ACM SIGPLAN LaTeX paper | ✅ | dcba_paper.zip (main.tex + references.bib + images/) |
| BUG_REPORT.md | ✅ | GitHub: AnkanSaha18/Blockchain/BUG_REPORT.md |
| UAV Simulation Feasibility Report | ✅ | In conversation (markdown artifact) |
| This resume document | ✅ | DCBA_Claude_Resume.md |

---

## 21. RESEARCH PAPER STATUS

**Template:** ACM SIGPLAN Proceedings (acmart.cls, sigplan option)
**Length:** ~14 pages
**Status:** Complete draft, needs:
  1. Replace 2 `\fbox` placeholder figures with actual diagrams (Figure 1: architecture, Figure 2: flow sequence)
  2. Fill in 3 author names/emails
  3. Update `\acmConference` with actual venue
  4. Review oracle latency figure (currently 16ms local; may change with cross-host deployment)

**Sections written:**
- Abstract ✅
- §1 Introduction + Contributions (C1-C6) ✅
- §2 Related Work + 6 Research Gaps (Table 1) ✅
- §3 System Architecture + Actor table ✅
- §4 System Flow (9 stages) ✅
- §5 Smart Contract Design (all 7 SCs with Solidity listing for SC-1) ✅
- §6 Algorithms (DCS pseudocode, Bloom params, PARS table, hardware identity) ✅
- §7 Security Analysis (10 attack mitigations table) ✅
- §8 Performance (test table, gas table, Caliper table, TikZ charts, DCS table) ✅
- §9 Conclusion + Future Work ✅
- References (18 citations, BibTeX) ✅

---

## 22. NEXT PLANNED WORK (UAV SIMULATION EXTENSION)

**Decision:** Custom Python stack (no dedicated drone simulator — all fail for blockchain use case)

**Recommended tools:**
- Mesa 3.x → agent-based UAV fleet modeling
- SimPy 4.x → PARS priority queue (PriorityResource maps to PARS tiers)
- Plotly Dash → real-time 4-panel dashboard
- Matplotlib + contextily → publication-quality figures
- Folium → interactive Dhaka map HTML
- web3.py → SC-4 + SC-6 event listener

**Geographic context:** Dhaka, Bangladesh
- Dhaka Medical College: 23.7256°N, 90.3976°E (hospital/delivery destination)
- Hazrat Shahjalal Airport: 23.8513°N, 90.4068°E (UAV depot reference)

**5-week roadmap:**
- Week 1: Mesa UAV agents + SimPy priority queue + basic matplotlib
- Week 2: web3.py blockchain bridge (SC-4 events + SC-6 GPS events)
- Week 3: Plotly Dash 4-panel real-time dashboard
- Week 4: Publication figures (contextily + Dhaka tiles, PDF/SVG export)
- Week 5: Full experiments, stress test, paper figures finalized

**Expected paper figures from simulation (8-12 total):**
1. Dhaka map with UAV flight paths color-coded by PARS tier
2. Dhaka delivery density heat map by district
3. Blockchain gas cost per delivery time series
4. Blockchain confirmation latency vs dispatch delay
5. PARS tier distribution under varying demand
6. CRITICAL vs LOW delivery time comparison (proves PARS works)
7. Queue depth over time under surge conditions
8. DCS score evolution across fleet over multiple rounds
9. UAV reliability score vs delivery success scatter
10. DCS round convergence analysis

**Install command (all tools):**
```bash
pip3 install mesa simpy web3 dash plotly folium geopandas contextily kaleido matplotlib shapely --break-system-packages
```

**Supplement:** SUMO for Dhaka road congestion context figure (motivates UAV delivery narrative). `osmWebWizard.py` imports Dhaka OSM in 30 minutes.

**REJECTED options and why:**
- PySimverse: 6 stars, 6KB codebase, paid, alpha, no GIS. ELIMINATE.
- Gazebo+ROS2: 5 tech stacks, 1-2 weeks setup, solves flight dynamics (irrelevant).
- AirSim/Colosseum: Deprecated 2022, 613 stars, Ubuntu 24.04 unsupported, 100GB disk.
- MATLAB UAV Toolbox: $2400+/year, no native web3, Python bridge awkward. OK if BUET has license for figure generation only.

---

## 23. KEY NUMBERS TO REMEMBER (for paper claims)

| Metric | Value | Context |
|---|---|---|
| Test pass rate | 86/86 (100%) | Both macOS + Ubuntu |
| DCS 100-UAV time | 8.37ms | 16.7× below 140ms target |
| Oracle relay latency | 16ms | Local Hardhat; cross-host ~5.4s |
| Caliper total transactions | 244 | 0 failures |
| Caliper query TPS | 20.4 TPS | Read-only |
| Caliper invoke TPS | 4.4–4.6 TPS | Single-node Raft |
| Highest gas cost | 369,599 | SC5.submitOrder() |
| Lowest gas cost | 23,924 | SC2.revokeAccess() |
| Security attacks blocked | 10/10 | Zero false negatives |
| Bloom filter size | 1024 bits (128 bytes) | n=100 UAVs, ε=0.01 FP |
| PARS CRITICAL SLA | 180 seconds (3 min) | |
| Counterfeit drug deaths | ~1 million/year | WHO stat |
| DGDA licensed manufacturers | 257 | Bangladesh |
| Dhaka population density | 44,000/km² | Urban |

---

## 24. IMPORTANT TECHNICAL NOTES FOR CLAUDE

1. **ESM vs CommonJS:** This project uses `"type": "module"` in package.json. ALL JS files must use `import/export`, never `require()`. Hardhat.config.js must NOT import `HardhatUserConfig` type (it's TypeScript-only).

2. **Go version in go.mod:** Must be `go 1.21` (major.minor only). Fabric's Docker build rejects `go 1.21.13` (patch version) with "invalid go version must match format 1.23".

3. **Caliper network.yaml version:** Must be `"1.0"`. `"2.0"` throws "Unknown network configuration version 2.0 specified".

4. **SC4.linkSC6():** Must be called once after deploying SC6. If forgotten, `confirmDelivery()` and `flagDeviation()` will ALWAYS revert silently.

5. **SC7.setSC3Address():** Must be called after deploying SC3. If forgotten, `SC3.addRecord()` will ALWAYS revert.

6. **Oracle bridge must start AFTER deploy.js:** bridge.js reads deployed-addresses.json. Starting bridge before deploy gives wrong addresses and misses events.

7. **Fabric network state:** When Ankan says "I get 'dcbachannel not found'" it means the test-network was restarted (`./network.sh down` then up) but chaincode was not redeployed. Always redeploy after `./network.sh down`.

8. **Python fleet_sim.py:** Uses `threading.Thread`, NOT `subprocess.Popen`. The subprocess version showed 2000ms+ per run (process spawn overhead). Threading version shows <10ms.

9. **SLA deadline timing in tests:** Use `9999999999` (year ~2286) as slaDeadline in SC6 tests, not `Date.now()/1000 + 3600`. Hardhat mines multiple blocks fast, causing timestamp confusion.

10. **SC4 computeScore formula check:** `(80*30 + 90*25 + 85*20 + 70*15 + 75*10) / 100 = 8150/100 = 81` (integer division). Test was wrong with 82, corrected to 81.

---

## 25. HOW TO RESUME THIS PROJECT IN A NEW CONVERSATION

Say to Claude: *"Read this resume document and resume the DCBA project. I want to continue from where we left off."*

Then specify what you want to do next:
- **Start UAV simulation:** "Let's start building the UAV simulation — Week 1: Mesa + SimPy setup"
- **Improve paper:** "Let's add Figure 1 (architecture diagram) to the LaTeX paper"  
- **More benchmarking:** "Run higher-load Caliper tests with 500 transactions"
- **Add features:** "Implement the Regulatory Auditor anomaly detection in SC-5"
- **Thesis chapter:** "Write Section 4 of my M.Sc. thesis based on this project"

The GitHub repo (https://github.com/AnkanSaha18/Blockchain) always has the latest code. In a new conversation, Claude can be asked to fetch and read specific files from there.

---

*End of resume document. Total project phases: 7 complete + 1 planned (simulation). Total code: 7 Solidity contracts + 3 Go chaincodes + 5 Python files + 5 JS files + 9 test files + 3 Caliper configs. Total test coverage: 86 tests, 100% pass rate.*
