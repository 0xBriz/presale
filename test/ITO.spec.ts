import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { InitialTokenOffering, MockDepositToken } from "../typechain";

describe("InitialTokenOffering", () => {
  let presale: InitialTokenOffering;
  let owner: SignerWithAddress;
  let mockUST: MockDepositToken;
  let mockBUSD: MockDepositToken;

  const mintAmountUST = ethers.utils.parseEther("100000000");
  const mintAmountBNB = ethers.utils.parseEther("100000000");

  let offeringToken: MockDepositToken;
  let treasuryAddress: string;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    treasuryAddress = owner.address;
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
    const ito = await InitialTokenOffering.deploy(poolCount, treasuryAddress);
    presale = await ito.deployed();
  }

  const poolCount = 4;

  describe("Pools", () => {
    let lpToken; // deposit token

    beforeEach(async () => {
      await deployMockTokens();
      offeringToken = mockBUSD;

      await deploy(poolCount);
      lpToken = mockUST.address;

      await setPool();

      // whitelist current user
      await presale.addToWhitelist([owner.address], 1);
      await presale.startSale();
      // Jump up a block to pass check
      await ethers.provider.send("hardhat_mine", []);

      // approve for test deposits
      await mockUST.approve(presale.address, ethers.constants.MaxUint256);
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

      await presale.setPool(
        offeringAmountPool,
        raisingAmountPool,
        limitPerUserInLP,
        1,
        lpToken,
        hasWhitelist,
        isStopDeposit
      );

      await presale.setPool(
        offeringAmountPool,
        raisingAmountPool,
        limitPerUserInLP,
        2,
        lpToken,
        hasWhitelist,
        isStopDeposit
      );
    }

    it("should deposit in a pool", async () => {
      const amount = ethers.utils.parseEther("10");
      await presale.depositPool(amount, poolId);

      const pool = await presale.viewPoolInformation(poolId);
    });

    it("should allow pool harvesting", async () => {
      // Deposit UST to pool
      await presale.depositPool(ethers.utils.parseEther("100"), poolId);
      await presale.depositPool(ethers.utils.parseEther("120"), 1);
      await presale.depositPool(ethers.utils.parseEther("120"), 2);

      console.log(await presale.userInfo(owner.address, 2));

      // // Enable claiming
      // await presale.endSale();
      // // Jump up a block to pass check
      // await ethers.provider.send("hardhat_mine", []);

      // // If not set people cant harvest
      // await presale.setOfferingToken(offeringToken.address);

      // // Fund the contract. Or there is nothing to harvest
      // await offeringToken.transfer(
      //   presale.address,
      //   ethers.utils.parseEther("1000")
      // );

      // console.log(await offeringToken.balanceOf(presale.address));

      // await presale.harvestPool(poolId);

      // console.log(await offeringToken.balanceOf(presale.address));

      // User should have offering token amount owed to them
    });
  });
});
