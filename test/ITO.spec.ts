import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { InitialTokenOffering, MockDepositToken } from "../typechain";

const PROTOCOL_TOKEN = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";

describe("InitialTokenOffering", () => {
  let presale: InitialTokenOffering;
  let owner: SignerWithAddress;
  let testUser: SignerWithAddress;
  let mockUST: MockDepositToken;
  let mockBUSD: MockDepositToken;

  const mintAmountUST = ethers.utils.parseEther("1000");
  const mintAmountBNB = ethers.utils.parseEther("100");

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    testUser = signers[1];
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

  async function deploy(
    poolCount: number,
    startBlockDiff: number,
    endBlockDiff: number
  ) {
    const InitialTokenOffering = await ethers.getContractFactory(
      "InitialTokenOffering"
    );
    const ito = await InitialTokenOffering.deploy(
      poolCount,
      startBlockDiff,
      endBlockDiff
    );
    presale = await ito.deployed();
  }

  const poolCount = 2;
  const startBlockDiff = 0; // 7 days
  const endBlockDiff = 403200; // 14 days

  describe("Pools", () => {
    let lpToken; // deposit token
    beforeEach(async () => {
      await deployMockTokens();
      await deploy(poolCount, startBlockDiff, endBlockDiff);
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

    it("should not allow deposits over the pool limit", async () => {
      // place above limit
      await expect(
        presale.depositPool(limitPerUserInLP.add(1), poolId)
      ).to.be.revertedWith("");
    });
  });
});
