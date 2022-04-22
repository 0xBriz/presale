import { ethers } from "hardhat";

const amesAddy = "0xFD6e577bc642238e1E091432Eec1a9f83fBBe03b";
const foxAddy = "0xbC4E6A07646c564a333c971DEDaCDbC485fEe5a8";
const niceAddy = "0xaBcD018b36EA7A16fdB177F85988E156182046Ca";
const briz = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";
const TEST_USERS = [briz, amesAddy, foxAddy, niceAddy];

async function main() {
  const poolCount = 10;
  const aaltoAddress = "0x7B991D38d6aEc50dfE3AAd1472FDd5764D5e3282";

  const InitialTokenOffering = await ethers.getContractFactory(
    "InitialTokenOffering"
  );
  const ito = await InitialTokenOffering.deploy(poolCount, aaltoAddress);
  await ito.deployed();

  console.log("InitialTokenOffering deployed to:", ito.address);

  for (const user of TEST_USERS) {
    await ito.setManager(user, true);
  }

  await ito.addToWhitelist(TEST_USERS, 1);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
