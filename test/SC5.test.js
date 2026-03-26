import { expect } from "chai";
import hre from "hardhat";

describe("SC5 - Delivery Orders", function () {
  let sc1, sc2, sc3, sc5, sc7;
  let patient, hp, warehouse, ds, uav;
  let rxHash;

  // Helper: submit one order and return orderId
  async function submitOrder(parsScore, suffix = "001") {
    const hash = hre.ethers.keccak256(
      hre.ethers.toUtf8Bytes(`rx-pars-${suffix}-${parsScore}`)
    );
    await sc3.connect(hp).addRecord(patient.address, "QmHash", parsScore, hash);
    await sc5.connect(hp).submitOrder(
      patient.address, hash, parsScore,
      "Insulin 10u", warehouse.address, ds.address
    );
    return (await sc5.orderCount()).toString();
  }

  beforeEach(async function () {
    [, patient, hp, warehouse, ds, uav] = await hre.ethers.getSigners();

    sc1 = await (await hre.ethers.getContractFactory("SC1_IdentityRegistry")).deploy();
    sc7 = await (await hre.ethers.getContractFactory("SC7_OracleBridge")).deploy();
    sc2 = await (await hre.ethers.getContractFactory("SC2_PatientConsent")).deploy(
      await sc1.getAddress()
    );
    sc3 = await (await hre.ethers.getContractFactory("SC3_MedicalRecords")).deploy(
      await sc1.getAddress(), await sc2.getAddress(), await sc7.getAddress()
    );
    await sc7.setSC3Address(await sc3.getAddress());
    sc5 = await (await hre.ethers.getContractFactory("SC5_DeliveryOrders")).deploy(
      await sc1.getAddress(), await sc7.getAddress()
    );

    await sc1.register(patient.address,   "patient",      "h_p");
    await sc1.register(hp.address,        "hp",           "h_hp");
    await sc1.register(warehouse.address, "warehouse",    "h_wh");
    await sc1.register(ds.address,        "dronestation", "h_ds");
    await sc1.register(uav.address,       "uav",          "h_uav");
    await sc2.connect(patient).grantAccess(hp.address, 7);

    rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc5-001"));
    await sc3.connect(hp).addRecord(patient.address, "QmHash", 95, rxHash);
  });

  // ── Core Order Flow ──────────────────────────────────────────

  it("TC-SC5-01: HP can submit a valid order", async function () {
    await sc5.connect(hp).submitOrder(
      patient.address, rxHash, 95, "Insulin", warehouse.address, ds.address
    );
    expect(await sc5.orderCount()).to.equal(1n);
  });

  it("TC-SC5-02: Duplicate rxHash rejected (replay prevention)", async function () {
    await sc5.connect(hp).submitOrder(
      patient.address, rxHash, 95, "Insulin", warehouse.address, ds.address
    );
    const rxHash2 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc5-002"));
    await sc3.connect(hp).addRecord(patient.address, "QmHash2", 90, rxHash2);
    // First rxHash is now USED — try reusing it
    await expect(
      sc5.connect(hp).submitOrder(
        patient.address, rxHash, 95, "Insulin", warehouse.address, ds.address
      )
    ).to.be.revertedWith("Prescription not verified by SC-7 oracle");
  });

  it("TC-SC5-03: CRITICAL order gets 3-minute SLA", async function () {
    expect(await sc5.getSLASeconds(95)).to.equal(180n);
  });

  it("TC-SC5-04: HIGH order gets 10-minute SLA", async function () {
    expect(await sc5.getSLASeconds(75)).to.equal(600n);
  });

  it("TC-SC5-05: MODERATE order gets 30-minute SLA", async function () {
    expect(await sc5.getSLASeconds(50)).to.equal(1800n);
  });

  it("TC-SC5-06: LOW order gets 2-hour SLA", async function () {
    expect(await sc5.getSLASeconds(20)).to.equal(7200n);
  });

  it("TC-SC5-07: Warehouse can confirm stock", async function () {
    await sc5.connect(hp).submitOrder(
      patient.address, rxHash, 95, "Insulin", warehouse.address, ds.address
    );
    await sc5.connect(warehouse).confirmStock(1);
    const order = await sc5.getOrder(1);
    expect(order.status).to.equal(1n); // CONFIRMED
  });

  it("TC-SC5-08: Wrong warehouse cannot confirm", async function () {
    await sc5.connect(hp).submitOrder(
      patient.address, rxHash, 95, "Insulin", warehouse.address, ds.address
    );
    await expect(sc5.connect(ds).confirmStock(1)).to.be.revertedWith(
      "Only the assigned warehouse"
    );
  });

  it("TC-SC5-09: DS can assign UAV after confirmation", async function () {
    await sc5.connect(hp).submitOrder(
      patient.address, rxHash, 95, "Insulin", warehouse.address, ds.address
    );
    await sc5.connect(warehouse).confirmStock(1);
    await sc5.connect(ds).assignUAV(1, uav.address);
    const order = await sc5.getOrder(1);
    expect(order.assignedUAV).to.equal(uav.address);
    expect(order.status).to.equal(2n); // DISPATCHED
  });

  // ── PARS Priority Queue ──────────────────────────────────────

  it("PARS-05: Boundary scores map to correct tiers", async function () {
    expect(await sc5.getSLASeconds(90)).to.equal(180n);    // exactly CRITICAL_MIN
    expect(await sc5.getSLASeconds(89)).to.equal(600n);    // exactly HIGH_MAX
    expect(await sc5.getSLASeconds(70)).to.equal(600n);    // exactly HIGH_MIN
    expect(await sc5.getSLASeconds(69)).to.equal(1800n);   // exactly MODERATE_MAX
    expect(await sc5.getSLASeconds(40)).to.equal(1800n);   // exactly MODERATE_MIN
    expect(await sc5.getSLASeconds(39)).to.equal(7200n);   // exactly LOW_MAX
    expect(await sc5.getSLASeconds(0)).to.equal(7200n);    // minimum LOW
  });

  it("PARS-06: getParsLabel returns correct tier strings", async function () {
    expect(await sc5.getParsLabel(95)).to.equal("CRITICAL - 3min SLA");
    expect(await sc5.getParsLabel(75)).to.equal("HIGH - 10min SLA");
    expect(await sc5.getParsLabel(50)).to.equal("MODERATE - 30min SLA");
    expect(await sc5.getParsLabel(20)).to.equal("LOW - 2hr SLA");
  });

  it("PARS-07: getHighestPriorityOrder returns 0 when no pending orders", async function () {
    const result = await sc5.getHighestPriorityOrder();
    expect(result.orderId).to.equal(0n);
    expect(result.tier).to.equal("NO_PENDING_ORDERS");
  });

  it("PARS-08: getHighestPriorityOrder returns the only pending order", async function () {
    await submitOrder(75, "001");
    const result = await sc5.getHighestPriorityOrder();
    expect(result.orderId).to.equal(1n);
    expect(result.parsScore).to.equal(75n);
    expect(result.tier).to.equal("HIGH - 10min SLA");
  });

  it("PARS-09: getHighestPriorityOrder picks CRITICAL over HIGH and LOW", async function () {
    await submitOrder(30, "low");      // orderId 1 — LOW
    await submitOrder(75, "high");     // orderId 2 — HIGH
    await submitOrder(95, "critical"); // orderId 3 — CRITICAL

    const result = await sc5.getHighestPriorityOrder();
    expect(result.orderId).to.equal(3n);
    expect(result.parsScore).to.equal(95n);
    expect(result.tier).to.equal("CRITICAL - 3min SLA");
  });

  it("PARS-10: FIFO tie-breaking — earlier order wins when parsScore equal", async function () {
    await submitOrder(75, "first");   // orderId 1 — same score, earlier
    await submitOrder(75, "second");  // orderId 2 — same score, later

    const result = await sc5.getHighestPriorityOrder();
    expect(result.orderId).to.equal(1n);  // earlier order wins (FIFO within tier)
  });

  it("PARS-11: After confirming stock, order is no longer PENDING — priority queue updates", async function () {
    await submitOrder(95, "critical");   // orderId 1 — CRITICAL
    await submitOrder(50, "moderate");   // orderId 2 — MODERATE

    // Confirm stock on CRITICAL order → moves to CONFIRMED (no longer PENDING)
    await sc5.connect(warehouse).confirmStock(1);

    const result = await sc5.getHighestPriorityOrder();
    expect(result.orderId).to.equal(2n);
    expect(result.parsScore).to.equal(50n);
    expect(result.tier).to.equal("MODERATE - 30min SLA");
  });

  it("PARS-12: getPendingOrdersSorted returns orders sorted by parsScore DESC", async function () {
    await submitOrder(30, "low");      // orderId 1
    await submitOrder(95, "critical"); // orderId 2
    await submitOrder(75, "high");     // orderId 3
    await submitOrder(50, "moderate"); // orderId 4

    const sorted = await sc5.getPendingOrdersSorted();
    expect(sorted.scores[0]).to.equal(95n);
    expect(sorted.scores[1]).to.equal(75n);
    expect(sorted.scores[2]).to.equal(50n);
    expect(sorted.scores[3]).to.equal(30n);
  });

  it("PARS-13: getPendingOrdersSorted returns correct tier labels", async function () {
    await submitOrder(95, "c"); // CRITICAL
    await submitOrder(50, "m"); // MODERATE

    const sorted = await sc5.getPendingOrdersSorted();
    expect(sorted.tiers[0]).to.equal("CRITICAL - 3min SLA");
    expect(sorted.tiers[1]).to.equal("MODERATE - 30min SLA");
  });

  it("PARS-14: getPendingOrdersSorted returns empty when no PENDING orders", async function () {
    const sorted = await sc5.getPendingOrdersSorted();
    expect(sorted.sortedIds.length).to.equal(0);
  });

  it("PARS-15: getPendingCountByTier counts correctly across all tiers", async function () {
    await submitOrder(95, "c1"); // CRITICAL
    await submitOrder(92, "c2"); // CRITICAL
    await submitOrder(75, "h1"); // HIGH
    await submitOrder(50, "m1"); // MODERATE
    await submitOrder(20, "l1"); // LOW
    await submitOrder(10, "l2"); // LOW

    const counts = await sc5.getPendingCountByTier();
    expect(counts.criticalCount).to.equal(2n);
    expect(counts.highCount).to.equal(1n);
    expect(counts.moderateCount).to.equal(1n);
    expect(counts.lowCount).to.equal(2n);
  });

  it("PARS-16: getPendingCountByTier excludes confirmed/dispatched orders", async function () {
    await submitOrder(95, "critical");
    await submitOrder(75, "high");

    // Confirm stock on CRITICAL — no longer PENDING
    await sc5.connect(warehouse).confirmStock(1);

    const counts = await sc5.getPendingCountByTier();
    expect(counts.criticalCount).to.equal(0n); // moved to CONFIRMED
    expect(counts.highCount).to.equal(1n);     // still PENDING
  });

  it("PARS-17: Full PARS dispatch — CRITICAL always dispatched before LOW", async function () {
    await submitOrder(15, "low-first");     // orderId 1
    await submitOrder(95, "critical-late"); // orderId 2

    // Priority queue should pick CRITICAL despite being submitted second
    const first = await sc5.getHighestPriorityOrder();
    expect(first.orderId).to.equal(2n);
    expect(first.tier).to.equal("CRITICAL - 3min SLA");

    // Confirm + dispatch CRITICAL
    await sc5.connect(warehouse).confirmStock(2);

    // Now only LOW remains
    const next = await sc5.getHighestPriorityOrder();
    expect(next.orderId).to.equal(1n);
    expect(next.tier).to.equal("LOW - 2hr SLA");
  });
});
