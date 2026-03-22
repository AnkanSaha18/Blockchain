import { expect } from "chai";
import hre from "hardhat";

describe("SC3 - Medical Records", function () {
  let sc1, sc2, sc3, sc7, TA, patient, hp, other;

  beforeEach(async function () {
    [TA, patient, hp, other] = await hre.ethers.getSigners();
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
    await sc1.register(patient.address, "patient", "hash_p");
    await sc1.register(hp.address, "hp", "hash_hp");
    await sc2.connect(patient).grantAccess(hp.address, 7);
  });

  it("TC-SC3-01: HP with consent can add record", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-001"));
    await sc3.connect(hp).addRecord(patient.address, "QmHash1", 95, rxHash);
    expect(await sc3.recordCount()).to.equal(1n);
  });

  it("TC-SC3-02: HP without consent cannot add record", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-002"));
    await expect(
      sc3.connect(other).addRecord(patient.address, "QmHash1", 95, rxHash),
    ).to.be.reverted;
  });

  it("TC-SC3-03: PARS score above 100 rejected", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-003"));
    await expect(
      sc3.connect(hp).addRecord(patient.address, "QmHash1", 101, rxHash),
    ).to.be.revertedWith("PARS score must be between 0 and 100");
  });

  it("TC-SC3-04: Empty rxHash rejected", async function () {
    await expect(
      sc3
        .connect(hp)
        .addRecord(patient.address, "QmHash1", 80, hre.ethers.ZeroHash),
    ).to.be.revertedWith("rxHash cannot be empty");
  });

  it("TC-SC3-05: After addRecord, SC7 hash becomes VALID", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-005"));
    await sc3.connect(hp).addRecord(patient.address, "QmHash1", 90, rxHash);
    expect(await sc7.checkHash(rxHash)).to.equal(1); // 1 = VALID
  });

  it("TC-SC3-06: getRecord returns correct data", async function () {
    const rxHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-006"));
    await sc3.connect(hp).addRecord(patient.address, "QmIPFS_ABC", 75, rxHash);
    const rec = await sc3.getRecord(1);
    expect(rec.hp).to.equal(hp.address);
    expect(rec.patient).to.equal(patient.address);
    expect(rec.parsScore).to.equal(75);
  });

  it("TC-SC3-07: getParsLabel returns correct tier", async function () {
    expect(await sc3.getParsLabel(95)).to.equal("CRITICAL");
    expect(await sc3.getParsLabel(75)).to.equal("HIGH");
    expect(await sc3.getParsLabel(50)).to.equal("MODERATE");
    expect(await sc3.getParsLabel(20)).to.equal("LOW");
  });

  it("TC-SC3-08: Patient record IDs tracked correctly", async function () {
    const rx1 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-a"));
    const rx2 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("rx-b"));
    await sc3.connect(hp).addRecord(patient.address, "QmA", 80, rx1);
    await sc3.connect(hp).addRecord(patient.address, "QmB", 60, rx2);
    const ids = await sc3.getPatientRecordIds(patient.address);
    expect(ids.length).to.equal(2);
  });
});
