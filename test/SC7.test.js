import { expect } from "chai";
import hre from "hardhat";

describe("SC7 - Oracle Bridge", function () {
  let sc1, sc2, sc3, sc7, TA, hp, patient;

  beforeEach(async function () {
    [TA, hp, patient] = await hre.ethers.getSigners();
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
    await sc1.register(hp.address, "hp", "h_hp");
    await sc1.register(patient.address, "patient", "h_p");
    await sc2.connect(patient).grantAccess(hp.address, 7);
  });

  it("TC-SC7-01: Hash status is PENDING before registration", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc7-new"));
    expect(await sc7.checkHash(rxHash)).to.equal(0); // PENDING
  });

  it("TC-SC7-02: Hash becomes VALID after SC3.addRecord", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc7-01"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 90, rxHash);
    expect(await sc7.checkHash(rxHash)).to.equal(1); // VALID
  });

  it("TC-SC7-03: verifyHash returns true for VALID hash", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc7-02"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 90, rxHash);
    const result = await sc7.verifyHash.staticCall(rxHash);
    expect(result).to.equal(true);
  });

  it("TC-SC7-04: Hash becomes USED after verifyHash", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc7-03"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 90, rxHash);
    await sc7.verifyHash(rxHash);
    expect(await sc7.checkHash(rxHash)).to.equal(2); // USED
  });

  it("TC-SC7-05: Replay attack blocked — USED hash returns false", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc7-04"));
    await sc3.connect(hp).addRecord(patient.address, "QmH", 90, rxHash);
    await sc7.verifyHash(rxHash); // first use → USED
    const result = await sc7.verifyHash.staticCall(rxHash); // second use
    expect(result).to.equal(false);
  });

  it("TC-SC7-06: Only SC3 can call registerHash", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-sc7-05"));
    await expect(sc7.registerHash(rxHash, hp.address)).to.be.revertedWith(
      "Only SC-3 can register",
    );
  });

  it("TC-SC7-07: setSC3Address can only be called by TA", async function () {
    await expect(sc7.connect(hp).setSC3Address(hp.address)).to.be.revertedWith(
      "Only TA",
    );
  });

  it("TC-SC7-08: PENDING hash verify returns false", async function () {
    const rxHash = hre.ethers.keccak256(
      hre.ethers.toUtf8Bytes("rx-never-registered"),
    );
    const result = await sc7.verifyHash.staticCall(rxHash);
    expect(result).to.equal(false);
  });
});
