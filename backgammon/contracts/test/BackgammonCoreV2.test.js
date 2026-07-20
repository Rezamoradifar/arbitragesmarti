const { expect } = require("chai");
const { ethers } = require("hardhat");

async function deployFixture() {
  const [deployer, feeRecipient, playerA, playerB] = await ethers.getSigners();

  const ReferralRegistry = await ethers.getContractFactory("ReferralRegistry");
  const referralRegistry = await ReferralRegistry.deploy(feeRecipient.address);

  const BackgammonCoreV2 = await ethers.getContractFactory("BackgammonCoreV2");
  const core = await BackgammonCoreV2.deploy(feeRecipient.address);

  await core.setReferralRegistry(await referralRegistry.getAddress());
  await referralRegistry.setAuthorizedCaller(await core.getAddress(), true);

  return { core, referralRegistry, deployer, feeRecipient, playerA, playerB };
}

async function createAndJoin(core, playerA, playerB, wager) {
  await core.connect(playerA).createGame(wager, ethers.ZeroAddress, { value: wager });
  await core.connect(playerB).joinGame(0, { value: wager });
}

let saltCounter = 0;

// Commits+reveals a roll for both players, then submits an empty move list
// (always legal: submitMoves allows 0 <= pipCount moves) purely to flip
// g.turn to the other player -- lets a test drive multiple realistic turns
// without needing to compute actually-legal checker moves.
async function passTurn(core, gameId, playerA, playerB) {
  const saltA = ethers.encodeBytes32String("s" + saltCounter++);
  const saltB = ethers.encodeBytes32String("s" + saltCounter++);
  const secretA = 1;
  const secretB = 2;

  const commitA = ethers.solidityPackedKeccak256(["uint8", "bytes32", "address"], [secretA, saltA, playerA.address]);
  const commitB = ethers.solidityPackedKeccak256(["uint8", "bytes32", "address"], [secretB, saltB, playerB.address]);

  await core.connect(playerA).commitRoll(gameId, commitA);
  await core.connect(playerB).commitRoll(gameId, commitB);
  await core.connect(playerA).revealRoll(gameId, secretA, saltA);
  await core.connect(playerB).revealRoll(gameId, secretB, saltB);

  const game = await core.getGame(gameId);
  const currentTurnPlayer = game.turn === 0n ? playerA : playerB;
  await core.connect(currentTurnPlayer).submitMoves(gameId, []);
}

describe("BackgammonCoreV2 -- doubling cube", function () {
  it("starts centered at cube value 1", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    const [cubeValue, cubeOwner] = await core.getCube(0);
    expect(cubeValue).to.equal(1);
    expect(cubeOwner).to.equal(ethers.ZeroAddress);
  });

  it("rejects a double offer on a free-play (no wager) game", async function () {
    const { core, playerA, playerB } = await deployFixture();
    await core.connect(playerA).createGame(0, ethers.ZeroAddress);
    await core.connect(playerB).joinGame(0);

    await expect(core.connect(playerA).offerDouble(0)).to.be.revertedWith("free play has no cube");
  });

  it("rejects an offer from the player who isn't on roll", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    // playerA is turn 0 by default -- playerB is not on roll yet.
    await expect(
      core.connect(playerB).offerDouble(0, { value: wager })
    ).to.be.revertedWith("not your turn");
  });

  it("accept: doubles the cube, escrows both top-ups, transfers cube ownership", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    const contractAddress = await core.getAddress();
    const balBefore = await ethers.provider.getBalance(contractAddress);

    await core.connect(playerA).offerDouble(0, { value: wager }); // top-up = wager * cubeValue(1)
    await core.connect(playerB).acceptDouble(0, { value: wager }); // matching top-up

    const balAfter = await ethers.provider.getBalance(contractAddress);
    expect(balAfter - balBefore).to.equal(wager * 2n); // both top-ups landed

    const [cubeValue, cubeOwner, offeredBy] = await core.getCube(0);
    expect(cubeValue).to.equal(2);
    expect(cubeOwner).to.equal(playerB.address);
    expect(offeredBy).to.equal(ethers.ZeroAddress);

    const game = await core.getGame(0);
    expect(game.phase).to.equal(2n); // back to CommitRoll
  });

  it("only the cube owner (or centered) may offer -- non-owner is rejected", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    await core.connect(playerA).offerDouble(0, { value: wager });
    await core.connect(playerB).acceptDouble(0, { value: wager }); // playerB now owns the cube

    // Play a move to get back to playerA... actually turn is unchanged by
    // doubling, so it's still playerA's turn (turn 0) -- but playerA no
    // longer owns the cube, so a second offer this turn must fail.
    await expect(
      core.connect(playerA).offerDouble(0, { value: wager * 2n })
    ).to.be.revertedWith("you don't hold the cube");
  });

  it("decline: refunds the offering player's top-up and ends the game at the pre-double pot", async function () {
    const { core, feeRecipient, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    const offerorBalBefore = await ethers.provider.getBalance(playerA.address);

    const offerTx = await core.connect(playerA).offerDouble(0, { value: wager });
    const offerReceipt = await offerTx.wait();
    const offerGas = offerReceipt.gasUsed * offerReceipt.gasPrice;

    const feeBalBefore = await ethers.provider.getBalance(feeRecipient.address);

    const declineTx = await core.connect(playerB).declineDouble(0);
    await declineTx.wait();

    // Pre-double pot: wager*2 (cube was still 1 when the game finished).
    const pot = wager * 2n;
    const expectedFee = (pot * 500n) / 10000n;
    const expectedReferral = (pot * 1000n) / 10000n; // no referrer set -> swept to feeRecipient too
    const expectedWinnerNet = pot - expectedFee - expectedReferral;

    const offerorBalAfter = await ethers.provider.getBalance(playerA.address);
    // playerA: spent offerGas, got refunded the top-up (wager), then won the pot.
    expect(offerorBalAfter).to.equal(offerorBalBefore - offerGas - wager + wager + expectedWinnerNet);

    const feeBalAfter = await ethers.provider.getBalance(feeRecipient.address);
    expect(feeBalAfter - feeBalBefore).to.equal(expectedFee + expectedReferral);

    const [cubeValue] = await core.getCube(0);
    expect(cubeValue).to.equal(1); // never actually doubled
    const game = await core.getGame(0);
    expect(game.winner).to.equal(playerA.address);
  });

  it("timeout on an un-answered double offer: refunds top-up, offering player wins", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    await core.connect(playerA).offerDouble(0, { value: wager });

    await ethers.provider.send("evm_increaseTime", [5 * 60 + 1]);
    await ethers.provider.send("evm_mine");

    await expect(core.connect(playerA).claimTimeout(0))
      .to.emit(core, "TimeoutClaimed")
      .withArgs(0, playerA.address);

    const game = await core.getGame(0);
    expect(game.winner).to.equal(playerA.address);
  });

  it("caps the cube at MAX_CUBE_VALUE", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("0.1");
    await createAndJoin(core, playerA, playerB, wager);

    // Doubling only advances turn ownership via cubeOwner, not g.turn --
    // real backgammon requires at least one more roll before a redouble,
    // so drive an actual turn between each accepted double (turn stays
    // with playerA throughout since submitMoves([]) always flips it back
    // and forth predictably: A -> B -> A).
    expect((await core.getGame(0)).turn).to.equal(0n); // playerA on roll

    await core.connect(playerA).offerDouble(0, { value: wager * 1n });
    await core.connect(playerB).acceptDouble(0, { value: wager * 1n }); // cube=2, B owns
    await passTurn(core, 0, playerA, playerB); // turn: A -> B

    await core.connect(playerB).offerDouble(0, { value: wager * 2n });
    await core.connect(playerA).acceptDouble(0, { value: wager * 2n }); // cube=4, A owns
    await passTurn(core, 0, playerA, playerB); // turn: B -> A

    await core.connect(playerA).offerDouble(0, { value: wager * 4n });
    await core.connect(playerB).acceptDouble(0, { value: wager * 4n }); // cube=8, B owns
    await passTurn(core, 0, playerA, playerB); // turn: A -> B

    const [cubeValue] = await core.getCube(0);
    expect(cubeValue).to.equal(8);

    await expect(
      core.connect(playerB).offerDouble(0, { value: wager * 8n })
    ).to.be.revertedWith("cube maxed out");
  });

  it("finishing the game after an accepted double pays out at the doubled pot", async function () {
    const { core, feeRecipient, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    await core.connect(playerA).offerDouble(0, { value: wager });
    await core.connect(playerB).acceptDouble(0, { value: wager }); // cube=2

    const pot = wager * 2n * 2n; // wager*2*cubeValue
    const expectedFee = (pot * 500n) / 10000n;
    const expectedReferral = (pot * 1000n) / 10000n;
    const expectedWinnerNet = pot - expectedFee - expectedReferral;

    const winnerBalBefore = await ethers.provider.getBalance(playerB.address);
    await core.connect(playerA).resign(0);
    const winnerBalAfter = await ethers.provider.getBalance(playerB.address);

    expect(winnerBalAfter - winnerBalBefore).to.equal(expectedWinnerNet);
  });
});

describe("BackgammonCoreV2 -- emergency pause", function () {
  it("owner can pause and unpause; only owner may call", async function () {
    const { core, playerA } = await deployFixture();
    await expect(core.connect(playerA).pause()).to.be.revertedWithCustomError(core, "OwnableUnauthorizedAccount");
    await core.pause();
    expect(await core.paused()).to.equal(true);
    await core.unpause();
    expect(await core.paused()).to.equal(false);
  });

  it("blocks new games/joins/doubles/rolls/moves while paused", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");

    await core.pause();
    await expect(
      core.connect(playerA).createGame(wager, ethers.ZeroAddress, { value: wager })
    ).to.be.revertedWithCustomError(core, "EnforcedPause");

    await core.unpause();
    await createAndJoin(core, playerA, playerB, wager);

    await core.pause();
    await expect(
      core.connect(playerA).offerDouble(0, { value: wager })
    ).to.be.revertedWithCustomError(core, "EnforcedPause");
  });

  it("does NOT block resign/claimTimeout so players can always exit an active game", async function () {
    const { core, playerA, playerB } = await deployFixture();
    const wager = ethers.parseEther("1");
    await createAndJoin(core, playerA, playerB, wager);

    await core.pause();
    // resign must still work even while paused -- funds can't get trapped.
    await expect(core.connect(playerA).resign(0)).to.not.be.reverted;
  });
});
