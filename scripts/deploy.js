// deploy.js — Deploys all 7 DCBA smart contracts in the correct order
// Run: npx hardhat run scripts/deploy.js --network localhost
//
// DEPLOY ORDER (based on dependencies):
//  1. SC1  — no deps
//  2. SC7  — no deps
//  3. SC2  — needs SC1
//  4. SC3  — needs SC1, SC2, SC7
//  5. SC7.setSC3Address(SC3)   ← CRITICAL STEP
//  6. SC4  — needs SC1
//  7. SC5  — needs SC1, SC7
//  8. SC6  — needs SC1, SC4
//  9. SC4.linkSC6(SC6)         ← CRITICAL STEP (new fix)

import hre from "hardhat";
import fs from "fs";

const { ethers } = hre;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("\n🚀 Deploying DCBA contracts...");
  console.log("   Deployer (TA):", deployer.address);
  console.log("─".repeat(55));

  // ── 1. SC1: Identity Registry ─────────────────────────────
  const SC1 = await ethers.getContractFactory("SC1_IdentityRegistry");
  const sc1 = await SC1.deploy();
  await sc1.waitForDeployment();
  console.log("✓ SC1 IdentityRegistry :", await sc1.getAddress());

  // ── 2. SC7: Oracle Bridge ──────────────────────────────────
  const SC7 = await ethers.getContractFactory("SC7_OracleBridge");
  const sc7 = await SC7.deploy();
  await sc7.waitForDeployment();
  console.log("✓ SC7 OracleBridge     :", await sc7.getAddress());

  // ── 3. SC2: Patient Consent ────────────────────────────────
  const SC2 = await ethers.getContractFactory("SC2_PatientConsent");
  const sc2 = await SC2.deploy(await sc1.getAddress());
  await sc2.waitForDeployment();
  console.log("✓ SC2 PatientConsent   :", await sc2.getAddress());

  // ── 4. SC3: Medical Records ────────────────────────────────
  const SC3 = await ethers.getContractFactory("SC3_MedicalRecords");
  const sc3 = await SC3.deploy(
    await sc1.getAddress(),
    await sc2.getAddress(),
    await sc7.getAddress()
  );
  await sc3.waitForDeployment();
  console.log("✓ SC3 MedicalRecords   :", await sc3.getAddress());

  // ── 5. CRITICAL: Tell SC7 which address SC3 is ────────────
  await sc7.setSC3Address(await sc3.getAddress());
  console.log("✓ SC7.setSC3Address()  → linked to SC3");

  // ── 6. SC4: DCS Scoring ────────────────────────────────────
  const SC4 = await ethers.getContractFactory("SC4_DCSScoring");
  const sc4 = await SC4.deploy(await sc1.getAddress());
  await sc4.waitForDeployment();
  console.log("✓ SC4 DCSScoring       :", await sc4.getAddress());

  // ── 7. SC5: Delivery Orders ────────────────────────────────
  const SC5 = await ethers.getContractFactory("SC5_DeliveryOrders");
  const sc5 = await SC5.deploy(
    await sc1.getAddress(),
    await sc7.getAddress()
  );
  await sc5.waitForDeployment();
  console.log("✓ SC5 DeliveryOrders   :", await sc5.getAddress());

  // ── 8. SC6: Delivery Lifecycle ─────────────────────────────
  const SC6 = await ethers.getContractFactory("SC6_DeliveryLifecycle");
  const sc6 = await SC6.deploy(
    await sc1.getAddress(),
    await sc4.getAddress()
  );
  await sc6.waitForDeployment();
  console.log("✓ SC6 DeliveryLifecycle:", await sc6.getAddress());

  // ── 9. CRITICAL: Tell SC4 that SC6 is authorized ──────────
  await sc4.linkSC6(await sc6.getAddress());
  console.log("✓ SC4.linkSC6()        → SC6 authorized for updateReputation");

  console.log("\n" + "═".repeat(55));
  console.log("✅ All 7 contracts deployed successfully!\n");

  // Save addresses for test script
  const addresses = {
    SC1: await sc1.getAddress(),
    SC2: await sc2.getAddress(),
    SC3: await sc3.getAddress(),
    SC4: await sc4.getAddress(),
    SC5: await sc5.getAddress(),
    SC6: await sc6.getAddress(),
    SC7: await sc7.getAddress(),
  };

  fs.writeFileSync(
    "./deployed-addresses.json",
    JSON.stringify(addresses, null, 2)
  );
  console.log("📄 Addresses saved to deployed-addresses.json");
  console.log(JSON.stringify(addresses, null, 2));
}

main().catch((e) => { console.error(e); process.exit(1); });
