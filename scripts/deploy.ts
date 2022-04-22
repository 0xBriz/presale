import { ethers } from "hardhat";

const amesAddy = "0xFD6e577bc642238e1E091432Eec1a9f83fBBe03b";
const foxAddy = "0xbC4E6A07646c564a333c971DEDaCDbC485fEe5a8";
const niceAddy = "0xaBcD018b36EA7A16fdB177F85988E156182046Ca";
const briz = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";
const TEAM = [briz, amesAddy, foxAddy, niceAddy];

async function main() {
  const poolCount = 10;
  // const aaltoAddress = "";
  const treasury = "";

  const InitialTokenOffering = await ethers.getContractFactory(
    "InitialTokenOffering"
  );
  const ito = await InitialTokenOffering.deploy(poolCount, treasury);
  await ito.deployed();

  console.log("InitialTokenOffering deployed to:", ito.address);

  for (const user of TEAM) {
    await ito.setManager(user, true);
  }

  await ito.addToWhitelist(TEAM, 1);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
