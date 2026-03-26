import { expect } from "chai";
import hre from "hardhat";

describe("Security Attack Tests", function () {
  let sc1, sc2, sc3, sc4, sc5, sc6, sc7;
  let TA, patient, hp, warehouse, ds, uav, attacker;

  beforeEach(async function () {
    [TA, patient, hp, warehouse, ds, uav, attacker] =
      await hre.ethers.getSigners();
    sc1 = await (
      await hre.ethers.getContractFactory("SC1_IdentityRegistry")
    ).deploy();
    sc7 = await (
      await hre.ethers.getContractFactory("SC7_OracleBridge")
    ).deploy();
    sc2 = await (
      await hre.ethers.getContractFactory("SC2_PatientConsent")
    ).deploy(await sc1.getAddress());
    sc3 = await (
      await hre.ethers.getContractFactory("SC3_MedicalRecords")
    ).deploy(
      await sc1.getAddress(),
      await sc2.getAddress(),
      await sc7.getAddress(),
    );
    await sc7.setSC3Address(await sc3.getAddress());
    sc4 = await (
      await hre.ethers.getContractFactory("SC4_DCSScoring")
    ).deploy(await sc1.getAddress());
    sc5 = await (
      await hre.ethers.getContractFactory("SC5_DeliveryOrders")
    ).deploy(await sc1.getAddress(), await sc7.getAddress());
    sc6 = await (
      await hre.ethers.getContractFactory("SC6_DeliveryLifecycle")
    ).deploy(await sc1.getAddress(), await sc4.getAddress());
    await sc4.linkSC6(await sc6.getAddress());

    await sc1.register(patient.address, "patient", "h_p");
    await sc1.register(hp.address, "hp", "h_hp");
    await sc1.register(warehouse.address, "warehouse", "h_wh");
    await sc1.register(ds.address, "dronestation", "h_ds");
    await sc1.register(uav.address, "uav", "h_uav");
    await sc2.connect(patient).grantAccess(hp.address, 7);
  });

  // ── ATTACK 1: Prescription Replay ────────────────────────
  it("TC-SEC-01: Replay attack — same rxHash used twice is blocked", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sec-01"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 95, rxHash);

    // First order — valid
    await sc5
      .connect(hp)
      .submitOrder(
        patient.address,
        rxHash,
        95,
        "Insulin",
        warehouse.address,
        ds.address,
      );

    // Second order — same rxHash, must be blocked
    await expect(
      sc5
        .connect(hp)
        .submitOrder(
          patient.address,
          rxHash,
          95,
          "Insulin",
          warehouse.address,
          ds.address,
        ),
    ).to.be.revertedWith("Prescription not verified by SC-7 oracle");
  });

  // ── ATTACK 2: Unregistered Actor ─────────────────────────
  it("TC-SEC-02: Unregistered actor cannot write medical record", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sec-02"));
    await expect(
      sc3.connect(attacker).addRecord(patient.address, "QmH", 80, rxHash),
    ).to.be.revertedWith("HP not registered in SC-1");
  });

  // ── ATTACK 3: Revoked Actor ───────────────────────────────
  it("TC-SEC-03: Revoked HP cannot write medical record", async function () {
    await sc1.revoke(hp.address, "licence expired");
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sec-03"));
    await expect(
      sc3.connect(hp).addRecord(patient.address, "QmH", 80, rxHash),
    ).to.be.revertedWith("HP not registered in SC-1");
  });

  // ── ATTACK 4: Fake UAV in DCS ─────────────────────────────
  it("TC-SEC-04: Unregistered UAV cannot submit DCS score", async function () {
    await sc4.connect(ds).openRound(1);
    // Phase 1 (Bloom filter) fires before Phase 2 (SC-1 check) — attacker blocked earlier
    await expect(sc4.connect(attacker).submitScore(1, 99)).to.be.revertedWith(
      "Phase 1 failed: UAV not in Bloom filter",
    );
  });

  // ── ATTACK 5: Wrong Patient Confirms Delivery ─────────────
  it("TC-SEC-05: Attacker cannot confirm someone else's delivery", async function () {
    const sla = 9999999999;
    await sc6.connect(ds).createDelivery(1, uav.address, patient.address, sla);
    await sc6.connect(uav).setInFlight(1);
    await expect(sc6.connect(attacker).confirmDelivery(1)).to.be.revertedWith(
      "Only the patient can confirm delivery",
    );
  });

  // ── ATTACK 6: No Consent — HP Blocked ────────────────────
  it("TC-SEC-06: HP cannot write record without patient consent", async function () {
    // Revoke existing consent first
    await sc2.connect(patient).revokeAccess(hp.address);
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sec-06"));
    await expect(
      sc3.connect(hp).addRecord(patient.address, "QmH", 80, rxHash),
    ).to.be.revertedWith(
      "No patient consent - patient must call SC2.grantAccess first",
    );
  });

  // ── ATTACK 7: TA Authority Hijack ────────────────────────
  it("TC-SEC-07: Non-TA cannot transfer TA authority", async function () {
    await expect(
      sc1.connect(attacker).transferTA(attacker.address),
    ).to.be.revertedWith("Only TA can do this");
  });

  // ── ATTACK 8: Direct Oracle Manipulation ─────────────────
  it("TC-SEC-08: Attacker cannot directly register hash in SC7", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-fake"));
    await expect(
      sc7.connect(attacker).registerHash(rxHash, attacker.address),
    ).to.be.revertedWith("Only SC-3 can register");
  });

  // ── ATTACK 9: Wrong DS tries to close DCS round ──────────
  it("TC-SEC-09: Different DS cannot close another DS's round", async function () {
    await sc1.register(attacker.address, "dronestation", "h_fake_ds");
    await sc4.connect(ds).addUAVToBloom(uav.address);
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav).submitScore(1, 80);
    await expect(sc4.connect(attacker).closeRound(1)).to.be.revertedWith(
      "Only the DS that opened this round",
    );
  });

  // ── ATTACK 10: Wrong Warehouse Confirms Stock ─────────────
  it("TC-SEC-10: Attacker warehouse cannot confirm another order's stock", async function () {
    await sc1.register(attacker.address, "warehouse", "h_fake_wh");
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sec-10"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 70, rxHash);
    await sc5
      .connect(hp)
      .submitOrder(
        patient.address,
        rxHash,
        70,
        "Paracetamol",
        warehouse.address,
        ds.address,
      );
    await expect(sc5.connect(attacker).confirmStock(1)).to.be.revertedWith(
      "Only the assigned warehouse",
    );
  });
});
