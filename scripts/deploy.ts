import { ethers } from "hardhat";

const amesAddy = "0xFD6e577bc642238e1E091432Eec1a9f83fBBe03b";
const foxAddy = "0xbC4E6A07646c564a333c971DEDaCDbC485fEe5a8";
const niceAddy = "0xaBcD018b36EA7A16fdB177F85988E156182046Ca";
const briz = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";
const TEAM = [briz, amesAddy, foxAddy, niceAddy];

async function main() {
  /**
   * Steps:
   * - Deploy InitialTokenOffering with pool count and treasury address
   * - Set team as managers
   * - Deploy pools per hard coded settings/parameters
   * - Whitelist users
   * - SET THE OFFERING TOKEN
   * - Fund the contract with Aalto
   * - When ready => presale.startSale()
   * - When done  => presale.endSale()
   * - Final harvest all deposits to treasury
   */

  const poolCount = 10;
  // const aaltoAddress = "";

  // Treasury Multisig
  const treasury = "bnb:0x6bcC0E231A4Ac051b68DBC62F8882c04e2bA9F77";

  const InitialTokenOffering = await ethers.getContractFactory(
    "InitialTokenOffering"
  );
  const ito = await InitialTokenOffering.deploy(poolCount, treasury);
  await ito.deployed();
  console.log("InitialTokenOffering deployed to:", ito.address);

  // Add team as managers
  for (const user of TEAM) {
    await ito.setManager(user, true);
  }
  // Do not auto add, as a reminder to add all
  // await ito.addToWhitelist(TEAM, 1);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
