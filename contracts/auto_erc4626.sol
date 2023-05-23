
// SPDX-License-Identifier: MIT


// based on solmate ERC4626
// https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol

// Open Zeppelin ERC4626
// https://docs.openzeppelin.com/contracts/4.x/erc4626
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/interfaces/IERC4626.sol
// 


// todo add LeveragedPosition Interface
// TODO make a call to ERC4626 contract to approve variabledebtWBTC and WETH to LeveragedPosition.sol as we have dont in our deploy script
// todo: add ERC4626 interface
// todo: add ERC4626 events
// TODO: add ERC4626 functions
// TODO: add ERC4626 tests
// TODO: add ERC4626 docs
// TODO: add ERC4626 example
// TODO add ERC4626 example to readme

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "../contracts/ILeveragedPosition.sol";
import "../contracts/LeveragedPosition.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import "@aave/core-v3/contracts/protocol/tokenization/base/DebtTokenBase.sol";
import "solmate/src/mixins/ERC4626.sol";

contract auto_erc4626 is ERC4626 {
    uint8 private immutable target_leverage_ratio;
    address private immutable Automated_Strat_contract_address;
    LeveragedPosition private Automated_Vault_Strat_Contract;
    address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address aavedebtWTBC = 0x40aAbEf1aa8f0eEc637E0E7d92fbfFB2F26A8b7B;

    
    event deposit_completed(address caller,
    uint256 indexed amount_deposited, 
    uint256 indexed final_collateral_amount,
    uint256 indexed final_debt_amount);

    constructor() ERC4626(ERC20(WETH), "auto_erc4626", "SMART4626") {
        target_leverage_ratio = 3;
        Automated_Vault_Strat_Contract = new LeveragedPosition();
        Automated_Strat_contract_address = address(Automated_Vault_Strat_Contract);
    }

    function address_for_underlying_strategy() public view returns(address) {
        return Automated_Strat_contract_address;
    }

    function strat_contract_owner() public view returns(address) {
        return Automated_Vault_Strat_Contract.getOwner();
    }  
    
    function totalAssets() public view override returns(uint256) {
        // we will treat our CDP collateral as our total assets aWETH:ETH, 1:1
        return ERC20(aWETH).balanceOf(address(this));
    }

    function afterDeposit(uint256 assets, uint256 shares) internal override {
        // underlying vault logic
        // instantiate interface for our Automated-Strat Contract
        ILeveragedPosition Automated_Strat_contract_interface = ILeveragedPosition(Automated_Strat_contract_address);
        TransferHelper.safeTransfer(WETH, Automated_Strat_contract_address, assets);
        /////// Required Approvals ///////
        // import variabledebtToken ABI to to call allowance function
        DebtTokenBase variabledebtToken = DebtTokenBase(aavedebtWTBC);
        // here we give the LP contract permission to open debt on behalf of this contract
// TODO update this later to call an estimate of the amount of debt we need to open and approve that amount only
        variabledebtToken.approveDelegation(address(Automated_Strat_contract_address), type(uint256).max);

        /////// Deposit into the automated-strat contract ///////
        Automated_Strat_contract_interface.deposit{value:msg.value}(); // call the deposit function from ILeveragedPosition }
    }
}