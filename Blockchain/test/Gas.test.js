import { expect } from "chai";
import hre from "hardhat";

describe("Gas Cost Benchmark", function () {
  let sc1, sc2, sc3, sc4, sc5, sc6, sc7;
  let TA, patient, hp, warehouse, ds, uav;

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

  it("GAS-01: SC1.register()", async function () {
    const [_, __, ___, ____, _____, ______, newActor] =
      await hre.ethers.getSigners();
    const tx = await sc1.register(newActor.address, "auditor", "hash_ra");
    const receipt = await tx.wait();
    console.log(
      "    SC1.register()         :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-02: SC1.revoke()", async function () {
    const tx = await sc1.revoke(uav.address, "test");
    const receipt = await tx.wait();
    console.log(
      "    SC1.revoke()           :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-03: SC2.grantAccess()", async function () {
    const [, , , , , , freshHP] = await hre.ethers.getSigners();
    await sc1.register(freshHP.address, "hp", "h_fresh");
    const tx = await sc2.connect(patient).grantAccess(freshHP.address, 30);
    const receipt = await tx.wait();
    console.log(
      "    SC2.grantAccess()      :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-04: SC2.revokeAccess()", async function () {
    const tx = await sc2.connect(patient).revokeAccess(hp.address);
    const receipt = await tx.wait();
    console.log(
      "    SC2.revokeAccess()     :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-05: SC3.addRecord() — CRITICAL priority", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-gas-05"));
    const tx = await sc3
      .connect(hp)
      .addRecord(patient.address, "QmIPFSHash123", 95, rxHash);
    const receipt = await tx.wait();
    console.log(
      "    SC3.addRecord(CRITICAL):",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-06: SC4.openRound()", async function () {
    const tx = await sc4.connect(ds).openRound(1);
    const receipt = await tx.wait();
    console.log(
      "    SC4.openRound()        :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-07: SC4.submitScore()", async function () {
    await sc4.connect(ds).openRound(1);
    const tx = await sc4.connect(uav).submitScore(1, 82);
    const receipt = await tx.wait();
    console.log(
      "    SC4.submitScore()      :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-08: SC4.closeRound() — 1 UAV", async function () {
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav).submitScore(1, 82);
    const tx = await sc4.connect(ds).closeRound(1);
    const receipt = await tx.wait();
    console.log(
      "    SC4.closeRound(1 UAV)  :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-09: SC5.submitOrder()", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-gas-09"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 95, rxHash);
    const tx = await sc5
      .connect(hp)
      .submitOrder(
        patient.address,
        rxHash,
        95,
        "Insulin 10u",
        warehouse.address,
        ds.address,
      );
    const receipt = await tx.wait();
    console.log(
      "    SC5.submitOrder()      :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-10: SC5.confirmStock()", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-gas-10"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 95, rxHash);
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
    const tx = await sc5.connect(warehouse).confirmStock(1);
    const receipt = await tx.wait();
    console.log(
      "    SC5.confirmStock()     :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-11: SC6.logGPS()", async function () {
    await sc6
      .connect(ds)
      .createDelivery(1, uav.address, patient.address, 9999999999);
    await sc6.connect(uav).setInFlight(1);
    const tx = await sc6.connect(uav).logGPS(1, "QmGPSCoordinateHash001");
    const receipt = await tx.wait();
    console.log(
      "    SC6.logGPS()           :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });

  it("GAS-12: SC6.confirmDelivery()", async function () {
    await sc6
      .connect(ds)
      .createDelivery(1, uav.address, patient.address, 9999999999);
    await sc6.connect(uav).setInFlight(1);
    const tx = await sc6.connect(patient).confirmDelivery(1);
    const receipt = await tx.wait();
    console.log(
      "    SC6.confirmDelivery()  :",
      receipt.gasUsed.toString(),
      "gas",
    );
    expect(receipt.gasUsed).to.be.gt(0n);
  });
});
