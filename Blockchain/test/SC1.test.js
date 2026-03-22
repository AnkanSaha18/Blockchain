import { expect } from "chai";
import hre from "hardhat";

describe("SC1 - Identity Registry", function () {
  let sc1, TA, other, patient, hp;

  beforeEach(async function () {
    [TA, other, patient, hp] = await hre.ethers.getSigners();
    const SC1 = await hre.ethers.getContractFactory("SC1_IdentityRegistry");
    sc1 = await SC1.deploy();
  });

  it("TC-SC1-01: TA can register an actor", async function () {
    await sc1.register(patient.address, "patient", "hash_p");
    expect(await sc1.isActive(patient.address)).to.equal(true);
    expect(await sc1.getRole(patient.address)).to.equal("patient");
  });

  it("TC-SC1-02: Non-TA cannot register", async function () {
    await expect(
      sc1.connect(other).register(patient.address, "patient", "hash_p")
    ).to.be.revertedWith("Only TA can do this");
  });

  it("TC-SC1-03: TA can revoke an actor", async function () {
    await sc1.register(patient.address, "patient", "hash_p");
    await sc1.revoke(patient.address, "compromised key");
    expect(await sc1.isActive(patient.address)).to.equal(false);
  });

  it("TC-SC1-04: Revoked actor cannot be used by other contracts", async function () {
    await sc1.register(patient.address, "patient", "hash_p");
    await sc1.revoke(patient.address, "test");
    expect(await sc1.isActive(patient.address)).to.equal(false);
  });

  it("TC-SC1-05: Cannot register already active actor", async function () {
    await sc1.register(patient.address, "patient", "hash_p");
    await expect(
      sc1.register(patient.address, "patient", "hash_p")
    ).to.be.revertedWith("Already registered and active");
  });

  it("TC-SC1-06: Cannot revoke non-active actor", async function () {
    await expect(
      sc1.revoke(patient.address, "not registered")
    ).to.be.revertedWith("Actor not active");
  });

  it("TC-SC1-07: TA transfer works", async function () {
    await sc1.transferTA(other.address);
    expect(await sc1.trustedAuthority()).to.equal(other.address);
    // old TA can no longer register
    await expect(
      sc1.register(patient.address, "patient", "hash_p")
    ).to.be.revertedWith("Only TA can do this");
  });
});
