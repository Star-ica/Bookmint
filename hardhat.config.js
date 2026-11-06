require("@nomicfoundation/hardhat-toolbox");
module.exports = { solidity: "0.8.20", networks: { sepolia: { url: process.env.RPC_URL || "", accounts: process.env.PK ? [process.env.PK] : [] } } };
