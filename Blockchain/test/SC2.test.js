import { expect } from "chai";
import hre from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("SC2 - Patient Consent", function () {
  let sc1, sc2, TA, patient, hp, other;

  beforeEach(async function () {
    [TA, patient, hp, other] = await hre.ethers.getSigners();

    // Deploy SC1 first
    const SC1 = await hre.ethers.getContractFactory("SC1_IdentityRegistry");
    sc1 = await SC1.deploy();

    // Deploy SC2 with SC1 address
    const SC2 = await hre.ethers.getContractFactory("SC2_PatientConsent");
    sc2 = await SC2.deploy(await sc1.getAddress());

    // Register patient and HP in SC1
    await sc1.register(patient.address, "patient", "hash_patient");
    await sc1.register(hp.address, "hp", "hash_hp");
  });

  it("TC-SC2-01: Patient can grant access to HP", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 7);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(true);
  });

  it("TC-SC2-02: Non-registered patient cannot grant access", async function () {
    await expect(
      sc2.connect(other).grantAccess(hp.address, 7)
    ).to.be.revertedWith("Patient not registered in SC-1");
  });

  it("TC-SC2-03: Patient cannot grant access to non-registered HP", async function () {
    await expect(
      sc2.connect(patient).grantAccess(other.address, 7)
    ).to.be.revertedWith("HP not registered in SC-1");
  });

  it("TC-SC2-04: Patient can revoke access", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 7);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(true);

    await sc2.connect(patient).revokeAccess(hp.address);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(false);
  });

  it("TC-SC2-05: Cannot revoke non-active consent", async function () {
    await expect(
      sc2.connect(patient).revokeAccess(hp.address)
    ).to.be.revertedWith("No active consent to revoke");
  });

  it("TC-SC2-06: hasAccess returns true for valid consent", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 7);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(true);
  });

  it("TC-SC2-07: hasAccess returns false after expiry", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 7);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(true);

    // Fast forward 8 days (beyond 7 day expiry)
    await time.increase(8 * 24 * 60 * 60);

    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(false);
  });

  it("TC-SC2-08: hasAccess returns false after revoke", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 7);
    await sc2.connect(patient).revokeAccess(hp.address);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(false);
  });

  it("TC-SC2-09: Grant with 0 days never expires", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 0);

    // Fast forward 365 days
    await time.increase(365 * 24 * 60 * 60);

    // Should still have access
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(true);
  });

  it("TC-SC2-10: getConsentInfo returns correct data", async function () {
    await sc2.connect(patient).grantAccess(hp.address, 7);

    const [active, grantedAt, expiresAt] = await sc2.getConsentInfo(patient.address, hp.address);

    expect(active).to.equal(true);
    expect(grantedAt).to.be.gt(0);
    expect(expiresAt).to.be.gt(grantedAt);
  });

  it("TC-SC2-11: Can re-grant access after revoke", async function () {
    // Grant, revoke, then grant again
    await sc2.connect(patient).grantAccess(hp.address, 7);
    await sc2.connect(patient).revokeAccess(hp.address);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(false);

    // Re-grant
    await sc2.connect(patient).grantAccess(hp.address, 5);
    expect(await sc2.hasAccess(hp.address, patient.address)).to.equal(true);
  });

  it("TC-SC2-12: Events are emitted correctly", async function () {
    // Test AccessGranted event
    const tx = await sc2.connect(patient).grantAccess(hp.address, 7);
    const receipt = await tx.wait();

    await expect(tx)
      .to.emit(sc2, "AccessGranted");

    // Test AccessRevoked event
    await expect(sc2.connect(patient).revokeAccess(hp.address))
      .to.emit(sc2, "AccessRevoked")
      .withArgs(patient.address, hp.address);
  });
});
