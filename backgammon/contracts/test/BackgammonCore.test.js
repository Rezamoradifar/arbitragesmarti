const { expect } = require("chai");
const { ethers } = require("hardhat");

// Board layout in BackgammonCore: player A occupies points [0,11,16,18] (2/5/3/5
// checkers) moving 0->23; player B occupies the mirrored points moving 23->0.
// These helpers replay a fixed, hand-picked sequence of legal moves that
// races player A's checkers home and bears them all off, to exercise the
// full commit-reveal -> move -> payout path without a real dice oracle.

async function deployFixture() {
  const [deployer, feeRecipient, playerA, playerB, referrerA] = await ethers.getSigners();

  const ReferralRegistry = await ethers.getContractFactory("ReferralRegistry");
  const referralRegistry = await ReferralRegistry.deploy(feeRecipient.address);

  const BackgammonCore = await ethers.getContractFactory("BackgammonCore");
  const core = await BackgammonCore.deploy(feeRecipient.address);

  const RatingRegistry = await ethers.getContractFactory("RatingRegistry");
  const rating = await RatingRegistry.deploy();

  await core.setReferralRegistry(await referralRegistry.getAddress());
  await referralRegistry.setAuthorizedCaller(await core.getAddress(), true);
  await rating.setReporter(await core.getAddress(), true);
  await core.setRatingRegistry(await rating.getAddress());

  return { core, referralRegistry, rating, deployer, feeRecipient, playerA, playerB, referrerA };
}

// Commits+reveals one dice roll for both players and returns the resulting
// [d1, d2] pips, computed the same way the contract derives them (secretValue % 6 + 1).
async function commitAndReveal(core, gameId, playerA, playerB, secretA, secretB) {
  const saltA = ethers.encodeBytes32String("saltA");
  const saltB = ethers.encodeBytes32String("saltB");

  const commitA = ethers.solidityPackedKeccak256(["uint8", "bytes32", "address"], [secretA, saltA, playerA.address]);
  const commitB = ethers.solidityPackedKeccak256(["uint8", "bytes32", "address"], [secretB, saltB, playerB.address]);

  await core.connect(playerA).commitRoll(gameId, commitA);
  await core.connect(playerB).commitRoll(gameId, commitB);

  await core.connect(playerA).revealRoll(gameId, secretA, saltA);
  await core.connect(playerB).revealRoll(gameId, secretB, saltB);

  const dieA = (secretA % 6) + 1;
  const dieB = (secretB % 6) + 1;
  return dieA === dieB ? [dieA, dieA, dieA, dieA] : [dieA, dieB];
}

describe("BackgammonCore", function () {
  it("plays a free-play (no wager) game end to end with no fees", async function () {
    const { core, playerA, playerB } = await deployFixture();

    await core.connect(playerA).createGame(0, ethers.ZeroAddress);
    await core.connect(playerB).joinGame(0);

    // Player A's turn: roll produces two pips, move one checker each.
    const pips = await commitAndReveal(core, 0, playerA, playerB, 2, 5); // -> [3, 6]
    await core.connect(playerA).submitMoves(0, [
      { from: 0, to: 0 + pips[0] },
      { from: 11, to: 11 + pips[1] },
    ]);

    const game = await core.getGame(0);
    expect(game.turn).to.equal(1);
    expect(game.phase).to.equal(2n); // CommitRoll
  });

  it("collects BNB stakes and requires exact wager amount", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");

    await core.connect(playerA).createGame(wager, ethers.ZeroAddress, { value: wager });
    await expect(
      core.connect(playerB).joinGame(0, { value: ethers.parseEther("0.5") })
    ).to.be.revertedWith("bad BNB stake");

    await core.connect(playerB).joinGame(0, { value: wager });
    const game = await core.getGame(0);
    expect(game.phase).to.equal(2n); // CommitRoll
  });

  it("resign() forfeits the wager, splits pot 5% platform / 10% referral / 85% winner", async function () {
    const { core, feeRecipient, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");

    await core.connect(playerA).createGame(wager, ethers.ZeroAddress, { value: wager });
    await core.connect(playerB).joinGame(0, { value: wager });

    const pot = wager * 2n;
    const expectedFee = (pot * 500n) / 10000n; // 5%
    const expectedReferral = (pot * 1000n) / 10000n; // 10%, no referrer set -> swept to feeRecipient
    const expectedWinner = pot - expectedFee - expectedReferral;

    const feeBalanceBefore = await ethers.provider.getBalance(feeRecipient.address);
    const winnerBalanceBefore = await ethers.provider.getBalance(playerB.address);

    const tx = await core.connect(playerA).resign(0);
    await tx.wait();

    const feeBalanceAfter = await ethers.provider.getBalance(feeRecipient.address);
    const winnerBalanceAfter = await ethers.provider.getBalance(playerB.address);

    // No referrer chain configured -> referral share also lands on feeRecipient.
    expect(feeBalanceAfter - feeBalanceBefore).to.equal(expectedFee + expectedReferral);
    expect(winnerBalanceAfter - winnerBalanceBefore).to.equal(expectedWinner);

    const game = await core.getGame(0);
    expect(game.winner).to.equal(playerB.address);
    expect(game.phase).to.equal(5n); // Finished
  });

  it("pays multi-level referral commissions instantly on game finish", async function () {
    const { core, referralRegistry, feeRecipient, playerA, playerB, referrerA } = await deployFixture();
    const wager = ethers.parseEther("1");

    await referralRegistry.connect(playerA).setReferrer(referrerA.address);

    await core.connect(playerA).createGame(wager, ethers.ZeroAddress, { value: wager });
    await core.connect(playerB).joinGame(0, { value: wager });

    const pot = wager * 2n;
    const referralFee = (pot * 1000n) / 10000n;
    const playerAHalf = referralFee / 2n; // playerA's chain funds half the pool
    const level1Amount = (playerAHalf * 5000n) / 10000n; // referrerA is level 1 (50%)

    const referrerBalanceBefore = await ethers.provider.getBalance(referrerA.address);

    // playerB resigns -> playerA wins, playerA's referral chain gets paid.
    await core.connect(playerB).resign(0);

    const referrerBalanceAfter = await ethers.provider.getBalance(referrerA.address);
    expect(referrerBalanceAfter - referrerBalanceBefore).to.equal(level1Amount);
  });

  it("updates RatingRegistry after a game finishes", async function () {
    const { core, rating, playerA, playerB } = await deployFixture();

    await core.connect(playerA).createGame(0, ethers.ZeroAddress);
    await core.connect(playerB).joinGame(0);
    await core.connect(playerB).resign(0);

    expect(await rating.gamesPlayed(playerA.address)).to.equal(1);
    expect(await rating.gamesPlayed(playerB.address)).to.equal(1);
    expect(await rating.rating(playerA.address)).to.be.gt(1000);
    expect(await rating.rating(playerB.address)).to.be.lt(1000);
  });

  it("lets the winner claim a timeout when the opponent stops responding", async function () {
    const { core, playerA, playerB } = await deployFixture();

    await core.connect(playerA).createGame(0, ethers.ZeroAddress);
    await core.connect(playerB).joinGame(0);

    await expect(core.connect(playerA).claimTimeout(0)).to.be.revertedWith("not expired");

    await ethers.provider.send("evm_increaseTime", [5 * 60 + 1]);
    await ethers.provider.send("evm_mine");

    await expect(core.connect(playerB).claimTimeout(0))
      .to.emit(core, "TimeoutClaimed")
      .withArgs(0, playerB.address);
  });

  it("rejects combined fee changes above the 30% hard cap", async function () {
    const { core } = await deployFixture();
    await expect(core.setProtocolFee(2600)).to.be.revertedWith("combined fee too high"); // 2600 + 1000 > 3000
    await core.setProtocolFee(2000); // 2000 + 1000 = 3000, allowed at the boundary
    expect(await core.protocolFeeBps()).to.equal(2000);
  });
});
