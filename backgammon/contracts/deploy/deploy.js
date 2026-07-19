// Hardhat deploy script.
// Usage: npx hardhat run deploy/deploy.js --network bscTestnet
//
// Deploys ReferralRegistry -> BackgammonCore -> RatingRegistry ->
// BackgammonTournament, and wires the authorization/ownership links
// between them. All platform fees (5% + referral pool remainder) and
// tournament organizer defaults point at PLATFORM_OWNER.

const hre = require("hardhat");

const PLATFORM_OWNER = "0x63c5B98AEfd69658B652d5F35FFda3C6c06847E3";

async function main() {
  console.log("Deploying with platform owner/treasury:", PLATFORM_OWNER);

  const ReferralRegistry = await hre.ethers.getContractFactory("ReferralRegistry");
  const referralRegistry = await ReferralRegistry.deploy(PLATFORM_OWNER);
  await referralRegistry.waitForDeployment();
  console.log("ReferralRegistry:", await referralRegistry.getAddress());

  const BackgammonCore = await hre.ethers.getContractFactory("BackgammonCore");
  const core = await BackgammonCore.deploy(PLATFORM_OWNER);
  await core.waitForDeployment();
  console.log("BackgammonCore:", await core.getAddress());

  const RatingRegistry = await hre.ethers.getContractFactory("RatingRegistry");
  const rating = await RatingRegistry.deploy();
  await rating.waitForDeployment();
  console.log("RatingRegistry:", await rating.getAddress());

  const BackgammonTournament = await hre.ethers.getContractFactory("BackgammonTournament");
  const tournament = await BackgammonTournament.deploy();
  await tournament.waitForDeployment();
  console.log("BackgammonTournament:", await tournament.getAddress());

  // Wire authorizations
  await (await core.setReferralRegistry(await referralRegistry.getAddress())).wait();
  await (await referralRegistry.setAuthorizedCaller(await core.getAddress(), true)).wait();
  await (await rating.setReporter(await core.getAddress(), true)).wait();
  await (await core.setRatingRegistry(await rating.getAddress())).wait();

  // Hand admin control (fee settings, authorized callers, etc.) to the
  // platform owner wallet — otherwise the deployer key retains control.
  await (await core.transferOwnership(PLATFORM_OWNER)).wait();
  await (await referralRegistry.transferOwnership(PLATFORM_OWNER)).wait();
  await (await rating.transferOwnership(PLATFORM_OWNER)).wait();
  await (await tournament.transferOwnership(PLATFORM_OWNER)).wait();

  console.log("\nDone. Remember to:");
  console.log("1. Verify all four contracts on BscScan.");
  console.log("2. Fill VITE_CORE_ADDRESS_TESTNET/MAINNET in the frontend .env with the BackgammonCore address above.");
  console.log("3. Get a professional audit before enabling real-money wagering on mainnet.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
