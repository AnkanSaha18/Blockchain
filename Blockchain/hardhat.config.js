import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";

export default {
  solidity: {
    version: "0.8.20",
    settings: { optimizer: { enabled: true, runs: 200 } }
  },
  gasReporter: {
    enabled: true,
    outputFile: "gas-report.txt",
    noColors: true,
  },
  networks: {
    hardhat: {},
    localhost: { url: "http://127.0.0.1:8545" }
  }
};