const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BackgammonTournament", function () {
  async function deployFixture() {
    const [organizer, p1, p2, p3] = await ethers.getSigners();
    const Tournament = await ethers.getContractFactory("BackgammonTournament");
    const tournament = await Tournament.deploy();
    return { tournament, organizer, p1, p2, p3 };
  }

  it("collects entry fees, finalizes standings, and pays out by rank", async function () {
    const { tournament, organizer, p1, p2, p3 } = await deployFixture();
    const entryFee = ethers.parseEther("0.1");

    await tournament
      .connect(organizer)
      .createTournament(ethers.ZeroAddress, entryFee, 3, [6000, 3000, 1000]);

    await tournament.connect(p1).register(0, { value: entryFee });
    await tournament.connect(p2).register(0, { value: entryFee });
    await tournament.connect(p3).register(0, { value: entryFee });

    await expect(
      tournament.connect(p1).register(0, { value: entryFee })
    ).to.be.revertedWith("already registered");

    await tournament.connect(organizer).closeRegistration(0);
    await tournament.connect(organizer).finalize(0, [p2.address, p3.address, p1.address]);

    const pool = entryFee * 3n;
    const p2Prize = (pool * 6000n) / 10000n;

    const balanceBefore = await ethers.provider.getBalance(p2.address);
    const tx = await tournament.connect(p2).claimPrize(0);
    const receipt = await tx.wait();
    const gasCost = receipt.gasUsed * receipt.gasPrice;
    const balanceAfter = await ethers.provider.getBalance(p2.address);

    expect(balanceAfter - balanceBefore + gasCost).to.equal(p2Prize);
    await expect(tournament.connect(p2).claimPrize(0)).to.be.revertedWith("already claimed");
  });

  it("rejects payout splits that don't total 100%", async function () {
    const { tournament, organizer } = await deployFixture();
    await expect(
      tournament.connect(organizer).createTournament(ethers.ZeroAddress, 0, 2, [6000, 3000])
    ).to.be.revertedWith("payout splits must total 100%");
  });
});
