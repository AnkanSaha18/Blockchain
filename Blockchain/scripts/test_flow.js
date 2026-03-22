// test_flow.js — Full end-to-end DCBA workflow test
// Run AFTER deploy.js: npx hardhat run scripts/test_flow.js --network localhost

import hre from "hardhat";
import fs from "fs";

const { ethers } = hre;


async function main() {
  const addrs = JSON.parse(fs.readFileSync("./deployed-addresses.json"));
  const signers = await ethers.getSigners();

  // Assign roles to test wallets
  const TA        = signers[0];  // Trusted Authority (deployer)
  const patient   = signers[1];
  const hp        = signers[2];  // Healthcare Provider (doctor)
  const warehouse = signers[3];
  const ds        = signers[4];  // Drone Station
  const uav1      = signers[5];
  const uav2      = signers[6];

  console.log("\n🧪 DCBA End-to-End Test Flow");
  console.log("═".repeat(55));

  // Load contracts
  const sc1 = await ethers.getContractAt("SC1_IdentityRegistry", addrs.SC1, TA);
  const sc2 = await ethers.getContractAt("SC2_PatientConsent",   addrs.SC2, TA);
  const sc3 = await ethers.getContractAt("SC3_MedicalRecords",   addrs.SC3, TA);
  const sc4 = await ethers.getContractAt("SC4_DCSScoring",       addrs.SC4, TA);
  const sc5 = await ethers.getContractAt("SC5_DeliveryOrders",   addrs.SC5, TA);
  const sc6 = await ethers.getContractAt("SC6_DeliveryLifecycle",addrs.SC6, TA);
  const sc7 = await ethers.getContractAt("SC7_OracleBridge",     addrs.SC7, TA);

  // ── STEP 1: Register all actors in SC1 ────────────────────
  console.log("\n[1] Registering actors in SC1...");
  await sc1.register(patient.address,   "patient",     "hash_patient");
  await sc1.register(hp.address,        "hp",          "hash_hp");
  await sc1.register(warehouse.address, "warehouse",   "hash_wh");
  await sc1.register(ds.address,        "dronestation","hash_ds");
  await sc1.register(uav1.address,      "uav",         "hash_uav1");
  await sc1.register(uav2.address,      "uav",         "hash_uav2");
  console.log("   ✓ 6 actors registered");

  // ── STEP 2: Patient grants consent to HP ──────────────────
  console.log("\n[2] Patient grants consent to HP (7 days)...");
  const sc2AsPatient = sc2.connect(patient);
  await sc2AsPatient.grantAccess(hp.address, 7);
  const hasAccess = await sc2.hasAccess(hp.address, patient.address);
  console.log("   ✓ hasAccess:", hasAccess);

  // ── STEP 3: HP writes a medical record ────────────────────
  console.log("\n[3] HP writes medical record to SC3...");
  const rxHash = ethers.keccak256(ethers.toUtf8Bytes("prescription-001"));
  const sc3AsHP = sc3.connect(hp);
  await sc3AsHP.addRecord(
    patient.address,
    "QmFakeIPFSHash123",  // IPFS hash of encrypted data
    95,                   // CRITICAL priority
    rxHash
  );
  console.log("   ✓ Record added, rxHash:", rxHash);

  // Verify SC7 received the hash
  const hashStatus = await sc7.checkHash(rxHash);
  console.log("   ✓ SC7 hash status:", hashStatus === 1n ? "VALID" : "ERROR");

  // ── STEP 4: HP submits delivery order ─────────────────────
  console.log("\n[4] HP submits delivery order to SC5...");
  const sc5AsHP = sc5.connect(hp);
  const tx = await sc5AsHP.submitOrder(
    patient.address,
    rxHash,
    95,
    "Insulin 10 units, Epinephrine 1mg",
    warehouse.address,
    ds.address
  );
  await tx.wait();
  console.log("   ✓ Order submitted (orderId: 1)");

  const order = await sc5.getOrder(1);
  console.log("   ✓ SLA tier:", await sc5.getParsLabel(95));
  console.log("   ✓ SLA deadline (seconds from now):", 
    Number(order.slaDeadline) - Math.floor(Date.now()/1000), "sec");

  // ── STEP 5: Warehouse confirms stock ──────────────────────
  console.log("\n[5] Warehouse confirms stock...");
  const sc5AsWH = sc5.connect(warehouse);
  await sc5AsWH.confirmStock(1);
  console.log("   ✓ Order status: CONFIRMED");

  // ── STEP 6: DS opens DCS scoring round ────────────────────
  console.log("\n[6] DS opens DCS scoring round...");
  const sc4AsDS = sc4.connect(ds);
  await sc4AsDS.openRound(1);
  console.log("   ✓ Round 1 opened");

  // UAVs submit scores
  const score1 = await sc4.computeScore(80, 90, 85, 70, 75);
  const score2 = await sc4.computeScore(70, 80, 90, 80, 85);
  console.log("   UAV1 score:", score1.toString(), "| UAV2 score:", score2.toString());

  await sc4.connect(uav1).submitScore(1, score1);
  await sc4.connect(uav2).submitScore(1, score2);

  // DS closes round → picks winner
  await sc4AsDS.closeRound(1);
  const [winner, winScore] = await sc4.getWinner(1);
  console.log("   ✓ Winner:", winner === uav1.address ? "UAV1" : "UAV2",
    "| Score:", winScore.toString());

  // ── STEP 7: DS assigns UAV in SC5 ─────────────────────────
  console.log("\n[7] DS assigns winning UAV...");
  const sc5AsDS = sc5.connect(ds);
  await sc5AsDS.assignUAV(1, winner);
  console.log("   ✓ UAV assigned, order DISPATCHED");

  // ── STEP 8: DS creates delivery in SC6 ────────────────────
  console.log("\n[8] DS creates delivery tracking in SC6...");
  const orderData = await sc5.getOrder(1);
  const sc6AsDS = sc6.connect(ds);
  await sc6AsDS.createDelivery(1, winner, patient.address, orderData.slaDeadline);
  console.log("   ✓ Delivery created");

  // UAV takes off
  const winnerSigner = winner === uav1.address ? uav1 : uav2;
  await sc6.connect(winnerSigner).setInFlight(1);
  console.log("   ✓ UAV IN_FLIGHT");

  // UAV logs GPS
  await sc6.connect(winnerSigner).logGPS(1, "QmGPS_Hash_001");
  await sc6.connect(winnerSigner).logGPS(1, "QmGPS_Hash_002");
  console.log("   ✓ 2 GPS logs recorded");

  // ── STEP 9: Patient confirms delivery ─────────────────────
  console.log("\n[9] Patient confirms delivery...");
  await sc6.connect(patient).confirmDelivery(1);
  const status = await sc6.getDeliveryStatus(1);
  console.log("   ✓ Status:", status.status === 4n ? "DELIVERED" : status.status.toString());
  console.log("   ✓ Within SLA:", status.withinSLA);

  // Check UAV reputation update
  const rep = await sc4.reputationScore(winner);
  console.log("   ✓ Winner UAV reputation:", rep.toString());

  console.log("\n" + "═".repeat(55));
  console.log("✅ Full DCBA flow completed successfully!\n");
}

main().catch((e) => { console.error(e); process.exit(1); });
