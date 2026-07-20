// Hardhat deploy script for BackgammonCoreV2 (doubling cube + emergency
// pause). Usage: npx hardhat run deploy/deployV2.js --network bscTestnet
//
// Reuses the ALREADY-DEPLOYED ReferralRegistry and RatingRegistry (V1's
// -- there's no reason to fragment referral/rating history across a new
// pair of those). Their ownership was already transferred to
// PLATFORM_OWNER by the original deploy script, so this deployer key
// (which only owns the brand-new CoreV2 until the final transferOwnership
// call below) CANNOT call their onlyOwner setAuthorizedCaller/setReporter
// itself -- see the printed follow-up step at the end.

const hre = require("hardhat");

const PLATFORM_OWNER = "0x63c5B98AEfd69658B652d5F35FFda3C6c06847E3";
const EXISTING_REFERRAL_REGISTRY = "0xE78cf59B7C015985992550B5a8Cb67940a0bEB11";
const EXISTING_RATING_REGISTRY = "0xF07fe39C8532e3b714cfDFFCee28bcC9603F7092";

async function main() {
  console.log("Deploying BackgammonCoreV2 with platform owner/treasury:", PLATFORM_OWNER);

  const BackgammonCoreV2 = await hre.ethers.getContractFactory("BackgammonCoreV2");
  const core = await BackgammonCoreV2.deploy(PLATFORM_OWNER);
  await core.waitForDeployment();
  const coreAddress = await core.getAddress();
  console.log("BackgammonCoreV2:", coreAddress);

  await (await core.setReferralRegistry(EXISTING_REFERRAL_REGISTRY)).wait();
  await (await core.setRatingRegistry(EXISTING_RATING_REGISTRY)).wait();

  await (await core.transferOwnership(PLATFORM_OWNER)).wait();

  console.log("\nDone. Remember to:");
  console.log("1. Verify BackgammonCoreV2 on BscScan.");
  console.log(
    "2. From the PLATFORM_OWNER wallet (not this deployer key -- it no longer has permission), call:\n" +
      `   referralRegistry.setAuthorizedCaller("${coreAddress}", true)  on ${EXISTING_REFERRAL_REGISTRY}\n` +
      `   ratingRegistry.setReporter("${coreAddress}", true)            on ${EXISTING_RATING_REGISTRY}\n` +
      "   Until then, V2 games still play/wager/pay out correctly -- referral commissions just fall back to the\n" +
      "   platform treasury and rating updates are silently skipped (both fail safe by design, see BackgammonCoreV2.sol)."
  );
  console.log("3. Update the frontend's BackgammonCoreV2 address once you're ready to switch the UI over.");
  console.log("4. Get a professional audit before enabling real-money wagering on mainnet.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
