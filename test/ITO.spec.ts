import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { InitialTokenOffering, MockDepositToken } from "../typechain";

describe("InitialTokenOffering", () => {
  let presale: InitialTokenOffering;
  let owner: SignerWithAddress;
  let mockUST: MockDepositToken;
  let mockBUSD: MockDepositToken;

  const mintAmountUST = ethers.utils.parseEther("1000");
  const mintAmountBNB = ethers.utils.parseEther("100");

  const offeringToken = mockBUSD;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
  });

  async function deployMockTokens() {
    const MockDepositToken = await ethers.getContractFactory(
      "MockDepositToken"
    );
    const UST = await MockDepositToken.deploy(mintAmountUST);
    mockUST = await UST.deployed();

    const MockDepositTokenBUSD = await ethers.getContractFactory(
      "MockDepositToken"
    );
    const BUSD = await MockDepositTokenBUSD.deploy(mintAmountBNB);
    mockBUSD = await BUSD.deployed();
  }

  async function deploy(poolCount: number) {
    const InitialTokenOffering = await ethers.getContractFactory(
      "InitialTokenOffering"
    );
    const ito = await InitialTokenOffering.deploy(
      poolCount,
      offeringToken.address
    );
    presale = await ito.deployed();
  }

  const poolCount = 2;

  describe("Pools", () => {
    let lpToken; // deposit token
    beforeEach(async () => {
      await deployMockTokens();
      await deploy(poolCount);
      lpToken = mockUST.address;
      await setPool();
      // approval
      await mockUST.approve(presale.address, ethers.constants.MaxUint256);
      // whitelist current user
      await presale.addToWhitelist([owner.address], 1);
    });

    const offeringAmountPool = ethers.utils.parseEther("1000");
    const raisingAmountPool = ethers.utils.parseEther("10000");
    const limitPerUserInLP = ethers.utils.parseEther("10000");
    const poolId = 0;

    const hasWhitelist = true;
    const isStopDeposit = false;

    async function setPool() {
      await presale.setPool(
        offeringAmountPool,
        raisingAmountPool,
        limitPerUserInLP,
        poolId,
        lpToken,
        hasWhitelist,
        isStopDeposit
      );

      const pool = await presale.viewPoolInformation(poolId);
      expect(pool.raisingAmountPool).to.equal(raisingAmountPool);
    }

    it("should deposit in a pool", async () => {
      const amount = ethers.utils.parseEther("10");
      await presale.depositPool(amount, poolId);

      const pool = await presale.viewPoolInformation(poolId);
      console.log(pool);
    });

    it("should allow pool harvesting", async () => {
      const balanceBefore = await mockUST.balanceOf(owner.address);
      console.log(balanceBefore);
      const amount = ethers.utils.parseEther("100");
      await presale.depositPool(amount, poolId);

      const balanceAfter = await mockUST.balanceOf(owner.address);
      console.log(balanceAfter);

      await presale.endSale();
      // Jump up a block to pass check
      await ethers.provider.send("hardhat_mine", []);
      await presale.harvestPool(poolId);

      // User should have offering token amount owed to them
    });
  });
});
