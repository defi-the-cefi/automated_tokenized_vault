const hre = require("hardhat");
const ERC20abi = require("../artifacts/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol/IERC20Metadata.json");
const WETHabi = require("../artifacts/contracts/LeveragedPosition.sol/IWETH.json");
const DebtTokenabi = require("../artifacts/@aave/core-v3/contracts/protocol/tokenization/base/DebtTokenBase.sol/DebtTokenBase.json");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
require("dotenv").config();

async function sleep(ms){
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

async function main() {
    // reseting chain state to block 17080861
    helpers.reset(process.env.ALCHEMY_MAINNET_RPC_URL,17080861);
    await sleep(3000)

    // deploy our vault wrapper (4626) contract
    console.log("deploying...");
    const IFlashLoan = await hre.ethers.getContractFactory("auto_erc4626");
    const automated4626_contract = await IFlashLoan.deploy(); //pass contructor parameters here
    await automated4626_contract.deployed();

    // verify our wrappy contract address - i.e. our 4626
    vault_contract_address = automated4626_contract.address;
    console.log("Vault wrapper (4626) contract deployed: ", vault_contract_address );

    // verify the address for the contract containing the lgoic for our vault's automated strategy
    underlying_vault_strategy_contract_address = await automated4626_contract.address_for_underlying_strategy();
    console.log("underlying vault strategy contract address: ", underlying_vault_strategy_contract_address);

    // verify that vault wrapper (4626) is the owner for the contract containing the logic for our vault's automated strategy
    strat_contract_owner_address = await automated4626_contract.strat_contract_owner();
    console.log("vault owner address: ", strat_contract_owner_address);

  
    const hre_provider = hre.ethers.provider;

  
    const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
    const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    // const lending_pool_address = "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2";
    const aWETH = "0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8";
    const aavedebtWTBC = "0x40aAbEf1aa8f0eEc637E0E7d92fbfFB2F26A8b7B";


    console.log("start vault deposit test");
    const signer = hre_provider.getSigner();
    const signer_address = await signer.getAddress();
    console.log("signer address: ", signer_address);
  
    
    ////////////////////////////////
    // THIS IS THE MEAT OF OUR CONTRACT
    ////////////////////////////////
    const eth_sent_w_deposit = ethers.utils.parseEther("1").toString();
    // wrap some ETH to deposit WETH into our vault
    const WETH_contract_signered = new ethers.Contract(WETH, WETHabi.abi, signer);
    const test_weth = await WETH_contract_signered.deposit({value: eth_sent_w_deposit});
    console.log("balance of wrapped ETH: ", (await WETH_contract_signered.balanceOf(signer_address)).toString());

    // approve vault to spend WETH
    console.log("approving 4626 for WETH deposit: ", eth_sent_w_deposit);
    approve_WETH_4626 = await WETH_contract_signered.approve(vault_contract_address, eth_sent_w_deposit); // 1 WETH approved
    // this is where we deposit into our vault
    floan = await automated4626_contract.deposit(eth_sent_w_deposit, signer_address);
    console.log("hurray vault deposit call successful!!!");
  
    const debtWBTC_asERC20 = new ethers.Contract(aavedebtWTBC, ERC20abi.abi, signer);
    ending_debt_token_balance = (await debtWBTC_asERC20.balanceOf(vault_contract_address)).toString();
    console.log("deposit done verify variabledebtoken balance on vault contract address : ", ending_debt_token_balance);
    const aWETH_ERC20 = new ethers.Contract(aWETH, ERC20abi.abi, signer);
    ending_collateral_token_balance = (await aWETH_ERC20.balanceOf(vault_contract_address)).toString();
    console.log("deposit done verify collateral token balance on vault contract address : ", ending_collateral_token_balance);
    console.log(floan);

    ////////////////////////////////
    // debuging debt and collateral token balances
    ////////////////////////////////
    singer_debt_token_balance = (await debtWBTC_asERC20.balanceOf(signer_address)).toString();
    console.log("verify variabledebtoken balance on signer address : ", singer_debt_token_balance);
    signer_collateral_token_balance = (await aWETH_ERC20.balanceOf(signer_address)).toString();
    console.log("verify collateral token balance on signer address : ", signer_collateral_token_balance);

    automation_debt_token_balance = (await debtWBTC_asERC20.balanceOf(underlying_vault_strategy_contract_address)).toString();
    console.log("verify variabledebtoken balance on signer address : ", automation_debt_token_balance);
    automation_collateral_token_balance = (await aWETH_ERC20.balanceOf(underlying_vault_strategy_contract_address)).toString();
    console.log("verify collateral token balance on signer address : ", automation_collateral_token_balance);

  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });