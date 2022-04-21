import { ethers } from "hardhat";

const amesAddy = "0xFD6e577bc642238e1E091432Eec1a9f83fBBe03b";
const foxAddy = "0xbC4E6A07646c564a333c971DEDaCDbC485fEe5a8";
const niceAddy = "0xaBcD018b36EA7A16fdB177F85988E156182046Ca";
const TEST_USERS = [amesAddy, foxAddy, niceAddy];

async function main() {
  const harmonyBlockTime = 2; // seconds
  // const desiredEndTimeInBlocks = 1100; // 1100 blocks should be ~20 minutes on Harmony
  const desiredEndTimeInBlocks = 3300; // 3300 blocks should be ~1 hour on Harmony

  //   const block = await ethers.provider.getBlock(
  //     await ethers.provider.getBlockNumber()
  //   );

  const poolCount = 25;
  //  const startingBlock = block.number + 30; // 30 * harmonyBlockTime = ~1 minute until start time
  const startingBlock = 1;
  const endBlock = desiredEndTimeInBlocks;
  const startBlockDiff = 201600; // 7 days
  const endBlockDiff = 403200; // 14 days
  const aaltoAddress = "0x7B991D38d6aEc50dfE3AAd1472FDd5764D5e3282";

  const InitialTokenOffering = await ethers.getContractFactory(
    "InitialTokenOffering"
  );
  const ito = await InitialTokenOffering.deploy(
    poolCount,
    startingBlock,
    endBlockDiff,
    aaltoAddress
  );
  await ito.deployed();

  console.log("InitialTokenOffering deployed to:", ito.address);

  for (const user of TEST_USERS) {
    await ito.setManager(user, true);
  }

  await ito.addToWhitelist(TEST_USERS, 1);
}

// async function deployMockToken(name: string, symbol: string) {
//   const NamedMockToken = await ethers.getContractFactory("NamedMockToken");
//   const token = await NamedMockToken.deploy(
//     name,
//     symbol,
//     ethers.utils.parseEther("1000000")
//   );
//   await token.deployed();

//   console.log(`${name} deployed to:`, token.address);

//   for (const user of testUsers) {
//     await token.transfer(user, ethers.utils.parseEther("1000"));
//   }
// }

async function deployPools() {
  // UST, BUSD, BNB
  const depositTokens = [
    {
      name: "Moist BNB",
      symbol: "MBNB",
      address: "",
    },
    {
      name: "Moist UST",
      symbol: "MUST",
      address: "",
    },
    {
      name: "Moist BUSD",
      symbol: "MBUSD",
      address: "",
    },
  ];

  //   const pools = [
  //     // UST, BUSD, BNB
  //   ];
  //   const offeringAmountPool = ethers.utils.parseEther("1000");
  //   const raisingAmountPool = ethers.utils.parseEther("10000");
  //   const limitPerUserInLP = ethers.utils.parseEther("10000");
  //   const maxCommitRatio = ethers.utils.parseEther("0");
  //   const minProtocolToJoin = ethers.utils.parseEther("0");
  //   const poolId = 0;
  //   const lpToken = ""; // deposit token
  //   const hasTax = false;
  //   const hasWhitelist = true;
  //   const isStopDeposit = false;
  //   const hasOverflow = false;

  //  for (const token of depositTokens) {
  //     await deployMockToken(token.name, token.symbol);
  //   }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
