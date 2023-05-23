const { expect } = require("chai");
const { ethers } = require("hardhat");


describe("Deploy contract", function () {
  it("Deployment should assign the total supply of tokens to the owner", async function () {
    const [owner] = await ethers.getSigners();

    const LeveragedPosition = await ethers.getContractFactory("LeveragedPosition");

    const leveragecontract = await LeveragedPosition.deploy();

    const makedeposit = await leveragecontract.desposit({value: ethers.utils.parseEther("1").toString()});
    console.log('completed desposit');

    // expect(await hardhatToken.totalSupply()).to.equal(ownerBalance);
  });
});