import { expect } from "chai";
import hre from "hardhat";

describe("SC4 - DCS Scoring", function () {
  let sc1, sc4, TA, ds, uav1, uav2, other;

  beforeEach(async function () {
    [TA, ds, uav1, uav2, other] = await hre.ethers.getSigners();
    sc1 = await (
      await hre.ethers.getContractFactory("SC1_IdentityRegistry")
    ).deploy();
    sc4 = await (
      await hre.ethers.getContractFactory("SC4_DCSScoring")
    ).deploy(await sc1.getAddress());
    await sc1.register(ds.address, "dronestation", "hash_ds");
    await sc1.register(uav1.address, "uav", "hash_uav1");
    await sc1.register(uav2.address, "uav", "hash_uav2");
  });

  it("TC-SC4-01: computeScore formula is correct", async function () {
    // (80*30 + 90*25 + 85*20 + 70*15 + 75*10) / 100 = 82
    const score = await sc4.computeScore(80, 90, 85, 70, 75);
    expect(score).to.equal(81n);
  });

  it("TC-SC4-02: computeScore rejects values above 100", async function () {
    await expect(sc4.computeScore(101, 90, 85, 70, 75)).to.be.revertedWith(
      "Metrics must be 0-100",
    );
  });

  it("TC-SC4-03: DS can open a round", async function () {
    await sc4.connect(ds).openRound(1);
    expect(await sc4.roundCount()).to.equal(1n);
  });

  it("TC-SC4-04: Unregistered caller cannot open round", async function () {
    await expect(sc4.connect(other).openRound(1)).to.be.reverted;
  });

  it("TC-SC4-05: UAV can submit score", async function () {
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    const sub = await sc4.submissions(1, uav1.address);
    expect(sub.score).to.equal(82n);
  });

  it("TC-SC4-06: UAV cannot submit twice", async function () {
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    await expect(sc4.connect(uav1).submitScore(1, 90)).to.be.revertedWith(
      "Already submitted",
    );
  });

  it("TC-SC4-07: closeRound picks highest scorer", async function () {
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    await sc4.connect(uav2).submitScore(1, 91);
    await sc4.connect(ds).closeRound(1);
    const [winner, score] = await sc4.getWinner(1);
    expect(winner).to.equal(uav2.address);
    expect(score).to.equal(91n);
  });

  it("TC-SC4-08: Cannot submit to closed round", async function () {
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    await sc4.connect(ds).closeRound(1);
    await expect(sc4.connect(uav2).submitScore(1, 90)).to.be.revertedWith(
      "Round is closed",
    );
  });

  it("TC-SC4-09: updateReputation works for registered caller", async function () {
    await sc4.connect(ds).updateReputation(uav1.address, 5);
    expect(await sc4.reputationScore(uav1.address)).to.equal(5n);
  });

  it("TC-SC4-10: Reputation can go negative", async function () {
    await sc4.connect(ds).updateReputation(uav1.address, -10);
    expect(await sc4.reputationScore(uav1.address)).to.equal(-10n);
  });
});
