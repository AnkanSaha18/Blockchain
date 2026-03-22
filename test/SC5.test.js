import { expect } from "chai";
import hre from "hardhat";

describe("SC5 - Delivery Orders", function () {
  let sc1, sc2, sc3, sc4, sc5, sc7;
  let TA, patient, hp, warehouse, ds, uav;
  let rxHash;

  beforeEach(async function () {
    [TA, patient, hp, warehouse, ds, uav] = await hre.ethers.getSigners();
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
    sc5 = await (
      await hre.ethers.getContractFactory("SC5_DeliveryOrders")
    ).deploy(await sc1.getAddress(), await sc7.getAddress());
    await sc1.register(patient.address, "patient", "h_p");
    await sc1.register(hp.address, "hp", "h_hp");
    await sc1.register(warehouse.address, "warehouse", "h_wh");
    await sc1.register(ds.address, "dronestation", "h_ds");
    await sc1.register(uav.address, "uav", "h_uav");
    await sc2.connect(patient).grantAccess(hp.address, 7);
    rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc5-001"));
    await sc3.connect(hp).addRecord(patient.address, "QmHash", 95, rxHash);
  });

  it("TC-SC5-01: HP can submit a valid order", async function () {
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
    expect(await sc5.orderCount()).to.equal(1n);
  });

  it("TC-SC5-02: Duplicate rxHash rejected (replay prevention)", async function () {
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
    const rxHash2 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc5-002"));
    await sc3.connect(hp).addRecord(patient.address, "QmHash2", 90, rxHash2);
    // First rxHash is now USED — try reusing it
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
    await sc5.connect(warehouse).confirmStock(1);
    const order = await sc5.getOrder(1);
    expect(order.status).to.equal(1n); // CONFIRMED
  });

  it("TC-SC5-08: Wrong warehouse cannot confirm", async function () {
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
    await expect(sc5.connect(ds).confirmStock(1)).to.be.revertedWith(
      "Only the assigned warehouse",
    );
  });

  it("TC-SC5-09: DS can assign UAV after confirmation", async function () {
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
    await sc5.connect(warehouse).confirmStock(1);
    await sc5.connect(ds).assignUAV(1, uav.address);
    const order = await sc5.getOrder(1);
    expect(order.assignedUAV).to.equal(uav.address);
    expect(order.status).to.equal(2n); // DISPATCHED
  });
});
