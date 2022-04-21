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
  let mockBNB: MockDepositToken;

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

    const MockDepositTokenBNB = await ethers.getContractFactory(
      "MockDepositToken"
    );
    const BNB = await MockDepositTokenBNB.deploy(mintAmountBNB);
    mockBNB = await BNB.deployed();
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
      endBlockDiff,
      PROTOCOL_TOKEN
    );
    presale = await ito.deployed();
  }

  describe("Construction", () => {
    const poolCount = 2;
    const startBlockDiff = 201600; // 7 days
    const endBlockDiff = 403200; // 14 days

    beforeEach(async () => {
      await deploy(poolCount, startBlockDiff, endBlockDiff);
      await deployMockTokens();
    });

    it("Should construct", async () => {});
  });

  describe("Setting Pools", () => {
    // uint256 _offeringAmountPool,
    // uint256 _raisingAmountPool,
    // uint256 _limitPerUserInLP,
    // uint256 _maxCommitRatio,
    // uint256 _minProtocolToJoin,
    // uint8 _pid,
    // address _lpToken,
    // bool _hasTax,
    // bool _hasWhitelist,
    // bool _isStopDeposit,
    // bool _hasOverflow

    //   struct PoolCharacteristics {
    //     uint256 raisingAmountPool; // amount of tokens raised for the pool (in LP tokens)
    //     uint256 offeringAmountPool; // amount of tokens offered for the pool (in offeringTokens)
    //     uint256 limitPerUserInLP; // limit of tokens per user (if 0, it is ignored)
    //     uint256 maxCommitRatio; // max commit base on protocol token holding
    //     uint256 minProtocolToJoin; // Can zero these out
    //     uint256 totalAmountPool; // total amount pool deposited (in LP tokens)
    //     uint256 sumTaxesOverflow; // total taxes collected (starts at 0, increases with each harvest if overflow)
    //     address lpToken; // lp token for this pool
    //     bool hasTax; // tax on the overflow (if any, it works with _calculateTaxOverflow)
    //     bool hasWhitelist; // only for whitelist
    //     bool isStopDeposit;
    //     bool hasOverflow; // Can deposit overflow
    // }

    it("should set a pool", async () => {
      const offeringAmountPool = ethers.utils.parseEther("1000");
      const raisingAmountPool = ethers.utils.parseEther("10000");
      const limitPerUserInLP = ethers.utils.parseEther("10000");
      const maxCommitRatio = ethers.utils.parseEther("0");
      const minProtocolToJoin = ethers.utils.parseEther("0");
      const poolId = 0;
      const lpToken = mockUST.address; // deposit token
      const hasTax = false;
      const hasWhitelist = true;
      const isStopDeposit = false;
      const hasOverflow = false;

      await presale.setPool(
        offeringAmountPool,
        raisingAmountPool,
        limitPerUserInLP,
        maxCommitRatio,
        minProtocolToJoin,
        poolId,
        lpToken,
        hasTax,
        hasWhitelist,
        isStopDeposit,
        hasOverflow
      );

      const pool = await presale.viewPoolInformation(poolId);
      console.log(pool);
    });
  });
});
