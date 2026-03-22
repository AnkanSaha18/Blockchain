import { expect } from "chai";
import hre from "hardhat";

describe("SC6 - Delivery Lifecycle", function () {
  let sc1, sc4, sc6, TA, ds, uav, patient, other;

  beforeEach(async function () {
    [TA, ds, uav, patient, other] = await hre.ethers.getSigners();
    sc1 = await (
      await hre.ethers.getContractFactory("SC1_IdentityRegistry")
    ).deploy();
    sc4 = await (
      await hre.ethers.getContractFactory("SC4_DCSScoring")
    ).deploy(await sc1.getAddress());
    sc6 = await (
      await hre.ethers.getContractFactory("SC6_DeliveryLifecycle")
    ).deploy(await sc1.getAddress(), await sc4.getAddress());
    await sc4.linkSC6(await sc6.getAddress());
    await sc1.register(ds.address, "dronestation", "h_ds");
    await sc1.register(uav.address, "uav", "h_uav");
    await sc1.register(patient.address, "patient", "h_p");

    const slaDeadline = 9999999999;
    await sc6
      .connect(ds)
      .createDelivery(1, uav.address, patient.address, slaDeadline);
  });

  it("TC-SC6-01: DS can create a delivery", async function () {
    const d = await sc6.deliveries(1);
    expect(d.assignedUAV).to.equal(uav.address);
    expect(d.status).to.equal(2n); // DISPATCHED
  });

  it("TC-SC6-02: Cannot create duplicate delivery", async function () {
    const sla = Math.floor(Date.now() / 1000) + 3600;
    await expect(
      sc6.connect(ds).createDelivery(1, uav.address, patient.address, sla),
    ).to.be.revertedWith("Delivery already created");
  });

  it("TC-SC6-03: UAV can set IN_FLIGHT", async function () {
    await sc6.connect(uav).setInFlight(1);
    const d = await sc6.deliveries(1);
    expect(d.status).to.equal(3n); // IN_FLIGHT
  });

  it("TC-SC6-04: Only assigned UAV can set IN_FLIGHT", async function () {
    await expect(sc6.connect(other).setInFlight(1)).to.be.revertedWith(
      "Only the assigned UAV",
    );
  });

  it("TC-SC6-05: UAV can log GPS during flight", async function () {
    await sc6.connect(uav).setInFlight(1);
    await sc6.connect(uav).logGPS(1, "QmGPS_001");
    await sc6.connect(uav).logGPS(1, "QmGPS_002");
    const status = await sc6.getDeliveryStatus(1);
    expect(status.gpsUpdateCount).to.equal(2n);
  });

  it("TC-SC6-06: GPS log rejected if not IN_FLIGHT", async function () {
    await expect(sc6.connect(uav).logGPS(1, "QmGPS_001")).to.be.revertedWith(
      "UAV not in flight",
    );
  });

  it("TC-SC6-07: DS can flag deviation — UAV reputation penalised", async function () {
    await sc6.connect(uav).setInFlight(1);
    await sc6.connect(ds).flagDeviation(1, "off-route detected");
    const status = await sc6.getDeliveryStatus(1);
    expect(status.deviated).to.equal(true);
    expect(await sc4.reputationScore(uav.address)).to.equal(-10n);
  });

  it("TC-SC6-08: Patient can confirm delivery", async function () {
    await sc6.connect(uav).setInFlight(1);
    await sc6.connect(patient).confirmDelivery(1);
    const status = await sc6.getDeliveryStatus(1);
    expect(status.status).to.equal(4n); // DELIVERED
  });

  it("TC-SC6-09: On-time delivery gives UAV +5 reputation", async function () {
    await sc6.connect(uav).setInFlight(1);
    await sc6.connect(patient).confirmDelivery(1);
    expect(await sc4.reputationScore(uav.address)).to.equal(5n);
  });

  it("TC-SC6-10: getGPSLog returns full trail", async function () {
    await sc6.connect(uav).setInFlight(1);
    await sc6.connect(uav).logGPS(1, "QmA");
    await sc6.connect(uav).logGPS(1, "QmB");
    const [hashes] = await sc6.getGPSLog(1);
    expect(hashes[0]).to.equal("QmA");
    expect(hashes[1]).to.equal("QmB");
  });
});
