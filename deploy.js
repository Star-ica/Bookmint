const { ethers } = require("hardhat");
(async () => {
  let bot = process.env.BOT, usdt = process.env.USDT;
  if (!bot) { const T = await ethers.getContractFactory("MockERC20"); bot = await (await T.deploy("BOT")).getAddress(); usdt = await (await T.deploy("USDT")).getAddress(); console.log("Mock tokens", bot, usdt); }
  const bm = await (await ethers.getContractFactory("BookMint")).deploy(bot, usdt);
  console.log("BookMint:", await bm.getAddress(), "\nPut this (and BOT/USDT) in frontend/config in index.html");
})();
