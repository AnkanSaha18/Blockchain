import { ethers } from "ethers";
import { readFileSync } from "fs";

const PDC_RPC   = "http://127.0.0.1:8545";
const ADDRESSES = JSON.parse(readFileSync("./deployed-addresses.json"));

const SC3_ABI = [
  "event RecordAdded(uint256 indexed recordId, address indexed hp, address indexed patient, bytes32 rxHash, uint8 parsScore)"
];
const SC7_ABI = [
  "function checkHash(bytes32 rxHash) external view returns (uint8)",
  "function verifyHash(bytes32 rxHash) external returns (bool)"
];

const latencies = [];

async function main() {
  const provider = new ethers.JsonRpcProvider(PDC_RPC);
  const signer   = await provider.getSigner();
  const sc3      = new ethers.Contract(ADDRESSES.SC3, SC3_ABI, provider);
  const sc7      = new ethers.Contract(ADDRESSES.SC7, SC7_ABI, signer);

  console.log("🌉 DCBA Oracle Bridge started");
  console.log("   SC3:", ADDRESSES.SC3);
  console.log("   SC7:", ADDRESSES.SC7);
  console.log("─".repeat(55));

  sc3.on("RecordAdded", async (recordId, hp, patient, rxHash, parsScore) => {
    const t1 = Date.now();
    console.log(`\n[${new Date().toISOString()}] RecordAdded event caught!`);
    console.log("   recordId :", recordId.toString());
    console.log("   rxHash   :", rxHash);
    console.log("   parsScore:", parsScore.toString());

    const status = await sc7.checkHash(rxHash);
    const t2 = Date.now();

    const latency = t2 - t1;
    latencies.push(latency);

    console.log("   SC7 status:", status === 1n ? "✅ VALID" : `${status}`);
    console.log(`   ⏱  Latency: ${latency}ms`);
    console.log(`   ⏱  Total relayed: ${latencies.length} | Avg: ${Math.round(latencies.reduce((a,b)=>a+b,0)/latencies.length)}ms`);
  });

  console.log("👂 Listening for SC3 RecordAdded events...\n");

  // Keep alive
  setInterval(() => {}, 10000);
}

main().catch(console.error);
