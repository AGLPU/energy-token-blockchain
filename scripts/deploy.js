const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("═══════════════════════════════════════════════════════");
  console.log("   Deploying EnergyToken Smart Contract");
  console.log("═══════════════════════════════��═══════════════════════\n");

  // ─── Deployer account ────────────────────────────────────────────────────
  const [deployer] = await hre.ethers.getSigners();
  console.log("🔑 Deployer address :", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance          :", hre.ethers.formatEther(balance), "ETH\n");

  // ─── Deploy ───────────────────────────────────────────────────────────────
  console.log("📦 Deploying EnergyToken...");
  const EnergyToken = await hre.ethers.getContractFactory("EnergyToken");
  const contract = await EnergyToken.deploy(deployer.address);
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();

  // ─── Verify basics ────────────────────────────────────────────────────────
  const name     = await contract.name();
  const symbol   = await contract.symbol();
  const decimals = await contract.decimals();
  const owner    = await contract.owner();

  console.log("\n✅ Contract deployed!");
  console.log("─────────────────────────────────────────────────────");
  console.log("   Address  :", contractAddress);
  console.log("   Name     :", name);
  console.log("   Symbol   :", symbol);
  console.log("   Decimals :", decimals.toString());
  console.log("   Owner    :", owner);
  console.log("─────────────────────────────────────────────────────");

  // ─── Save deployment info ─────────────────────────────────────────────────
  const deploymentInfo = {
    network:         hre.network.name,
    chainId:         (await hre.ethers.provider.getNetwork()).chainId.toString(),
    contractAddress: contractAddress,
    deployer:        deployer.address,
    blockNumber:     (await hre.ethers.provider.getBlockNumber()).toString(),
    deployedAt:      new Date().toISOString(),
    token: { name, symbol, decimals: decimals.toString() }
  };

  // Save to deployments/<network>-deployment.json
  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) fs.mkdirSync(deploymentsDir);

  const outFile = path.join(deploymentsDir, `${hre.network.name}-deployment.json`);
  fs.writeFileSync(outFile, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n💾 Saved to: deployments/${hre.network.name}-deployment.json`);

  // ─── Tell developer what to copy into .env ────────────────────────────────
  console.log("\n📌 Copy these into your FastAPI .env:");
  console.log(`   BLOCKCHAIN_ENABLED=True`);
  console.log(`   BLOCKCHAIN_CONTRACT_ADDRESS=${contractAddress}`);
  console.log(`   BLOCKCHAIN_RPC_URL=http://127.0.0.1:8545`);
  console.log(`   BLOCKCHAIN_NETWORK=${hre.network.name}`);
  console.log(`   BLOCKCHAIN_PRIVATE_KEY=<deployer private key>\n`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("❌ Deployment failed:", err);
    process.exit(1);
  });

