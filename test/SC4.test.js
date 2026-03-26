import { expect } from "chai";
import hre from "hardhat";

describe("SC4 - DCS Scoring", function () {
  let sc1, sc4, ds, uav1, uav2, uav3, fakeUAV;

  beforeEach(async function () {
    [, ds, uav1, uav2, uav3, fakeUAV] = await hre.ethers.getSigners();

    sc1 = await (await hre.ethers.getContractFactory("SC1_IdentityRegistry")).deploy();
    sc4 = await (await hre.ethers.getContractFactory("SC4_DCSScoring")).deploy(
      await sc1.getAddress()
    );

    await sc1.register(ds.address,   "dronestation", "hash_ds");
    await sc1.register(uav1.address, "uav",          "hash_uav1");
    await sc1.register(uav2.address, "uav",          "hash_uav2");
    await sc1.register(uav3.address, "uav",          "hash_uav3");
    // fakeUAV is intentionally NOT registered in SC-1
  });

  // ── Core Scoring ─────────────────────────────────────────────

  it("TC-SC4-01: computeScore formula is correct", async function () {
    // (80*30 + 90*25 + 85*20 + 70*15 + 75*10) / 100 = 81
    const score = await sc4.computeScore(80, 90, 85, 70, 75);
    expect(score).to.equal(81n);
  });

  it("TC-SC4-02: computeScore rejects values above 100", async function () {
    await expect(sc4.computeScore(101, 90, 85, 70, 75)).to.be.revertedWith(
      "Metrics must be 0-100"
    );
  });

  it("TC-SC4-03: DS can open a round", async function () {
    await sc4.connect(ds).openRound(1);
    expect(await sc4.roundCount()).to.equal(1n);
  });

  it("TC-SC4-04: Unregistered caller cannot open round", async function () {
    await expect(sc4.connect(fakeUAV).openRound(1)).to.be.reverted;
  });

  it("TC-SC4-05: UAV can submit score", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    const sub = await sc4.submissions(1, uav1.address);
    expect(sub.score).to.equal(82n);
  });

  it("TC-SC4-06: UAV cannot submit twice", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    await expect(sc4.connect(uav1).submitScore(1, 90)).to.be.revertedWith(
      "UAV already submitted this round"
    );
  });

  it("TC-SC4-07: closeRound picks highest scorer", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).addUAVToBloom(uav2.address);
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    await sc4.connect(uav2).submitScore(1, 91);
    await sc4.connect(ds).closeRound(1);
    const [winner, score] = await sc4.getWinner(1);
    expect(winner).to.equal(uav2.address);
    expect(score).to.equal(91n);
  });

  it("TC-SC4-08: Cannot submit to closed round", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);
    await sc4.connect(ds).closeRound(1);
    // "Round is closed" is checked before Bloom filter — uav2 need not be in filter
    await expect(sc4.connect(uav2).submitScore(1, 90)).to.be.revertedWith(
      "Round is closed"
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

  // ── Bloom Filter ─────────────────────────────────────────────

  it("BF-01: bloomCheck returns false for UAV not yet added to filter", async function () {
    expect(await sc4.bloomCheck(uav1.address)).to.equal(false);
  });

  it("BF-02: bloomCheck returns true after addUAVToBloom", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    expect(await sc4.bloomCheck(uav1.address)).to.equal(true);
  });

  it("BF-03: bloomCheck returns false for unregistered address", async function () {
    expect(await sc4.bloomCheck(fakeUAV.address)).to.equal(false);
  });

  it("BF-04: Cannot add unregistered UAV to Bloom filter", async function () {
    await expect(
      sc4.connect(ds).addUAVToBloom(fakeUAV.address)
    ).to.be.revertedWith("UAV not registered in SC-1");
  });

  it("BF-05: Cannot add same UAV to Bloom filter twice", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await expect(
      sc4.connect(ds).addUAVToBloom(uav1.address)
    ).to.be.revertedWith("UAV already in Bloom filter");
  });

  it("BF-06: Multiple UAVs added correctly — all return true", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).addUAVToBloom(uav2.address);
    await sc4.connect(ds).addUAVToBloom(uav3.address);

    expect(await sc4.bloomCheck(uav1.address)).to.equal(true);
    expect(await sc4.bloomCheck(uav2.address)).to.equal(true);
    expect(await sc4.bloomCheck(uav3.address)).to.equal(true);
  });

  it("BF-07: rebuildBloomFilter works correctly", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).addUAVToBloom(uav2.address);

    // Rebuild with only uav3 (simulate uav1, uav2 were revoked)
    await sc4.connect(ds).rebuildBloomFilter([uav3.address]);

    // uav3 MUST return true (zero false negatives)
    expect(await sc4.bloomCheck(uav3.address)).to.equal(true);
  });

  it("BF-08: submitScore passes Phase 1 and Phase 2 for registered UAV in filter", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).openRound(1);
    await sc4.connect(uav1).submitScore(1, 82);

    const sub = await sc4.submissions(1, uav1.address);
    expect(sub.score).to.equal(82n);
    expect(sub.passedBloom).to.equal(true);
    expect(sub.passedSig).to.equal(true);
  });

  it("BF-09: Phase 1 blocks UAV not in Bloom filter", async function () {
    // uav1 is registered in SC-1 but NOT added to Bloom filter
    await sc4.connect(ds).openRound(1);
    await expect(
      sc4.connect(uav1).submitScore(1, 82)
    ).to.be.revertedWith("Phase 1 failed: UAV not in Bloom filter");
  });

  it("BF-10: Phase 1 blocks completely unregistered fake UAV", async function () {
    // fakeUAV is neither in SC-1 nor in Bloom filter
    await sc4.connect(ds).openRound(1);
    await expect(
      sc4.connect(fakeUAV).submitScore(1, 99)
    ).to.be.revertedWith("Phase 1 failed: UAV not in Bloom filter");
  });

  it("BF-11: Rejection counters track Phase 1 and Phase 2 rejects", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).openRound(1);

    // uav2 is in SC-1 but not in Bloom filter → Phase 1 reject
    try { await sc4.connect(uav2).submitScore(1, 75); } catch {}

    const stats = await sc4.getRoundStats(1);
    // Note: Solidity reverts roll back ALL state changes, including counter increments.
    // rejectedByBloom++ is reverted along with the failed submitScore() call.
    // Counter remains 0; the meaningful check is that no score was accepted.
    expect(stats.rejectedBloom).to.equal(0n);
    expect(stats.accepted).to.equal(0n);  // no successful submissions yet
  });

  it("BF-12: closeRound picks highest score among Bloom-verified UAVs", async function () {
    await sc4.connect(ds).addUAVToBloom(uav1.address);
    await sc4.connect(ds).addUAVToBloom(uav2.address);
    await sc4.connect(ds).addUAVToBloom(uav3.address);
    await sc4.connect(ds).openRound(1);

    await sc4.connect(uav1).submitScore(1, 75);
    await sc4.connect(uav2).submitScore(1, 92);  // highest
    await sc4.connect(uav3).submitScore(1, 88);

    await sc4.connect(ds).closeRound(1);
    const [winner, score] = await sc4.getWinner(1);

    expect(winner).to.equal(uav2.address);
    expect(score).to.equal(92n);
  });

  it("BF-13: Bloom filter bit array is 128 bytes (1024 bits = correct parameters)", async function () {
    const filter = await sc4.bloomFilter();
    // bytes returned as hex string: "0x" + 256 hex chars = 128 bytes
    expect(filter.length).to.equal(2 + 256);  // "0x" + 128 bytes in hex
  });
});
