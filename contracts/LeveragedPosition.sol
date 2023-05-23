// SPDX-License-Identifier: MIT

// Smart contract that accepts ETH deposits and does the following:
// 1. retreive Uniswap v3 spot price for ETH in WBTC terms and stores this value in memory as ETH-BTC_price
// 2. from aave, flashloan WBTC worth 2 times our ETH deposit based on the uniswap spot price. Create a memory variable that will record how much WBTC was borrowed called wbtc_borrowed
// 3. swap all borrowed WBTC for ETH on uniswap v3
// 4. deposit all ETH into aave v3
// 5. Borrow enough WBTC to repay our flashloan + the flashloan borrow fee
// 6. retained all aETH and open leverage position, so that this smartcontract is the debt holder
// WETH-WBTC pool - https://info.uniswap.org/#/pools/0x4585fe77225b41b697c938b018e2ac67ac5a20c0


pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/flashloan/base/FlashLoanReceiverBase.sol";
import "@aave/core-v3/contracts/protocol/tokenization/base/DebtTokenBase.sol";
// Tyring to initiate debtToken contract with the following conflicts with openzeppelin IERC20 import below
//import "@aave/core-v3/contracts/protocol/tokenization/VariableDebtToken.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";

interface IWETH is IERC20 {

  function deposit() external payable;

  function withdraw(uint256 wad) external;
}


contract LeveragedPosition is FlashLoanReceiverBase {
    address payable immutable owner;

    //aave vars
    address private constant _ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    IPoolAddressesProvider private aave_address_provider = IPoolAddressesProvider(_ADDRESSES_PROVIDER);
    IPool private lendingPool;
    address private constant aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address private constant aavedebtWTBC = 0x40aAbEf1aa8f0eEc637E0E7d92fbfFB2F26A8b7B;
    DebtTokenBase private debttoken_contract= DebtTokenBase(aavedebtWTBC);

    //uniswap vars
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant address_uniswapv3_wbtc_weth_pool = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0;
    IUniswapV3Pool private uniswapv3_wbtc_weth_pool = IUniswapV3Pool(address_uniswapv3_wbtc_weth_pool);
    ISwapRouter private UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint256 public ethBtcPrice;

    //debuging
    uint256 public last_deposit_amount;


    //Dev Events
    event debug(string);
    event user_deposit(address indexed user, uint256 amount);
    event got_swap_params(uint256);
    event calc(string, uint256);

    //swap events
    event swap_broadcast(address indexed token_in, uint256 indexed amountIn);
    event swap_completed(address indexed token_out, uint256 indexed amountOut);

    //aave events
    event deposit_initiated(address indexed initiator, uint256 indexed amount);
    event flashloan_broadcast(address indexed token_in, uint256 indexed amountIn);
    event flashloan_completed(address indexed token_out, uint256 indexed amountOut);

    event comfirm_collat_and_debt_balances(uint256 indexed final_atoken_balance, uint256 indexed final_debttoken_balance);



    constructor() FlashLoanReceiverBase(aave_address_provider) 
    {
        owner = payable(msg.sender);
        lendingPool = IPool(aave_address_provider.getPool());

    }

    // import Ownable from openzeppelin util contracts and add onlyOwner modifier to contracts we want to restrict to factory contract - 4626
    modifier onlyOwner {
    require(msg.sender == owner, "You are not the owner");
    _;
    }

    function getOwner() public view returns(address) {
        return owner;
    }

    function getLendingPool() public view returns(address) {
        return address(lendingPool);
    }

    // wrapping ETH into WETH
    function wrap_ETH () public payable returns(bool) {
        // wrap ETH into WETH
        TransferHelper.safeApprove(WETH, address(this), msg.value);
        console.log("contract.balanceOf(WETH) before wraping: %s", IERC20Metadata(WETH).balanceOf(address(this)));
        IWETH(WETH).deposit{value: msg.value}();
        console.log("contract.balanceOf(WETH) after deposit in WETH: %s", IERC20Metadata(WETH).balanceOf(address(this)));
        return  true;
    }
    function unwrap_ETH (uint256 amountIn) public payable returns(bool) {
        // Unwrap WETH into ETH
        console.log("contract.balanceOf(WETH): %s", IERC20Metadata(WETH).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountIn);
        console.log("contract.balanceOf(WETH): %s", IERC20Metadata(WETH).balanceOf(address(this)));
        return  true;
    }

// Uniswap Functions
    function sqrtPriceX96ToUint(uint160 sqrtPriceX96, address token_in) internal view returns (uint256, uint256) {
        // token0 is WBTC in the WBTC-WETH pool
        address token0address = uniswapv3_wbtc_weth_pool.token0();
        console.log("token0address: ", token0address);
        console.log("verify the above is indeed WBTC: ", token0address==WBTC);
        address token1address = uniswapv3_wbtc_weth_pool.token1();

        uint256 decimalsToken0 = IERC20Metadata(token0address).decimals();
        uint256 decimalsToken1 = IERC20Metadata(token1address).decimals();
        uint256 decimals_difference = decimalsToken1 - decimalsToken0;
        console.log("decimalsToken0: ", decimalsToken0);
        console.log("decimalsToken1: ", decimalsToken1);
        
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2 = 10**decimalsToken0;
        uint256 numerator3 = 10**decimalsToken1;
        uint256 one2zero_decimals_shift = 10**decimals_difference;

        uint256 token1_per_token0 = FullMath.mulDiv(numerator1, numerator2, 1 << 192);

        // token1 per token0
        if(token_in==token0address){
            console.log("expected received ETH per BTC in 18decimals: ", token1_per_token0);
            return (token1_per_token0, decimalsToken1);}
                    
        // token0 per token1
        else if(token_in==token1address){
            uint256 token0_per_token1 = FullMath.mulDiv(numerator2, numerator3, token1_per_token0);                   
            console.log("expected received BTC per WETH in 8decimals: ", token0_per_token1);
            return (token0_per_token1, decimalsToken0);}

        // return if token not in pool
        else {console.log("error: wrong pool address");}
    }

    function verify_price_conv() public view returns(uint256, uint256) {
        // 1. Retrieve Uniswap v3 spot price for ETH in WBTC terms
        (uint160 sqrtPriceX96, , , , , , ) = uniswapv3_wbtc_weth_pool.slot0();
        console.log("sqrtPriceX96: %s", sqrtPriceX96);

        // our original price calc
        (uint256 eth_per_btc_price, uint256 weth_decimals) = sqrtPriceX96ToUint(sqrtPriceX96, WBTC);
        console.log("token_in = WBTC, eth_per_btc_price: ", eth_per_btc_price, " in eth_decimals: ", weth_decimals);

        // 2. Retrieve Uniswap v3 spot price for WBTC in ETH terms
        (uint256 btc_per_eth_price, uint256 wbtc_decimals) = sqrtPriceX96ToUint(sqrtPriceX96, WETH);
        console.log("token_in = WETH, btc_per_eth_price: ", btc_per_eth_price, " in WBTC decimals: ", wbtc_decimals);
        return(eth_per_btc_price, btc_per_eth_price);
    }


    function univ3_swap (address token_in, uint256 amountIn, address token_out, uint256 amountOutMin, uint160 sqrtPriceLimitX96) public payable returns (uint256 amountOut) {
        ISwapRouter router = UNISWAP_ROUTER;
        console.log("contract.balanceOf", token_in," before swap: %s", IERC20Metadata(token_in).balanceOf(address(this)));
        // Approve the router to spend token_in
        TransferHelper.safeApprove(token_in, address(router), amountIn);
        // Swap token_in for token_out on Uniswap v3
        emit swap_broadcast(token_in, amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: token_in,
            tokenOut: token_out,
            fee: uniswapv3_wbtc_weth_pool.fee(),
            recipient: address(this),
            deadline: block.timestamp + 300, // 5 minutes from now (later we can update this to a parameter we can pass thru)
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        amountOut = router.exactInputSingle(params);
        console.log("amountOut: %s", amountOut);
        console.log("contract.balanceOf", token_in," after swap: %s", IERC20Metadata(token_in).balanceOf(address(this)));
        emit swap_completed(token_out, amountOut);
        return amountOut;
    }


// TODO make this ownable by ERC4626 contract - onlyOwner
    function deposit() external payable {
// TODO make leverage_ratio a param we can pass thru contructor by ERC4626 contract
        uint16 leverage_ratio = 3;
        uint16 debt_to_collat_ratio = (leverage_ratio-1);
        uint256 deposited_collateral = IERC20(WETH).balanceOf(address(this));
        uint256 wbtc2Borrow;
        uint total_target_collateral = leverage_ratio*deposited_collateral;
        console.log("Deposit made, automated leverage position initiated");
        console.log("lendingpool address: ", address(lendingPool));
        console.log("caller address: ", msg.sender);
        console.log("owner address: ", owner);
        console.log("msg.value: %s", msg.value);
        console.log("deposited_collateral: %s", deposited_collateral);


        // 1. Retrieve Uniswap v3 spot price for ETH in WBTC terms
        (uint160 sqrtPriceX96, , , , , , ) = uniswapv3_wbtc_weth_pool.slot0();
        console.log("sqrtPriceX96: %s", sqrtPriceX96);
        (uint256 receivedETH_perBTC, uint256 eth_decimals) = sqrtPriceX96ToUint(sqrtPriceX96, WBTC);
        console.log("ETH-BTC price: %s", receivedETH_perBTC);
        wbtc2Borrow = FullMath.mulDiv(deposited_collateral, debt_to_collat_ratio*10**IERC20Metadata(WBTC).decimals(), receivedETH_perBTC);
        console.log("wbtc2Borrow: %s", wbtc2Borrow);

        // 2. Wrap ETH to get out WETH
        // if(msg.value > 0){
        //     wrap_ETH();
        // }

        // 3. Flashloan WBTC worth 2 times our ETH deposit based on the Uniswap spot price
        //flashloan parameters
        // we are not using flashloanSimple here, so we can add multiple assets to borrow if we like, but we only do WBTC for now
        address receiverAddress = address(this);
        address[] memory flashborrow_assets = new address[](1);
        flashborrow_assets[0] = WBTC;
        uint256[] memory amounts = new uint256[](1);   
        amounts[0] = wbtc2Borrow;
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 2;
        address onBehalfOf = owner;
        bytes memory params = abi.encode(deposited_collateral);
        uint16 referralCode = 0;

        // making flashloan call
        console.log("verify approval amount of VariableDebtWTBC: %s", debttoken_contract.borrowAllowance(owner, address(this)));
        console.log("attempting to flashloan WBTC, WBTC2borrow: %s", wbtc2Borrow);
        lendingPool.flashLoan(receiverAddress, flashborrow_assets, amounts, interestRateModes, onBehalfOf, params, referralCode);
        console.log("confirmiig successful exit from executeOperation callback");
        console.log("verify balance of DebtWBTC: %s", IERC20(aavedebtWTBC).balanceOf(owner));
        console.log("successfully initiated flashloan, waiting for executeOperation function to be calledback. WBTC borrowed: %s", wbtc2Borrow);
// todo - emit event comfirming our debt and collateral balances here
        emit comfirm_collat_and_debt_balances(IERC20(aWETH).balanceOf(owner), IERC20(aavedebtWTBC).balanceOf(owner));

    }

        

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(lendingPool), "Invalid caller");
        
        console.log("flashloan received, callback for executeOperation initiated");
        uint256 wbtcToRepay = amounts[0] + premiums[0];
        uint intial_WETH_deposited;
        uint256 amount_received_from_swap;
        uint256 leveraged_wethBalance;
        intial_WETH_deposited = abi.decode(params, (uint));

        // 3. Swap all borrowed WBTC for ETH on Uniswap v3
        console.log("initiator address: %s", initiator);
        console.log("contract balanceOf WBTC before swap: %s", IERC20(WBTC).balanceOf(address(this)));
        console.log("contract balanceOf WETH before swap: %s", IERC20(WETH).balanceOf(address(this)));
        amount_received_from_swap = univ3_swap (WBTC, amounts[0], WETH, 0, 0);
        
        leveraged_wethBalance = intial_WETH_deposited + amount_received_from_swap;
        console.log("contract balanceOf WETH after swap: %s", leveraged_wethBalance);


        // 4. Deposit all WETH into Aave v3
        // WETH is deposited on hebalf of contract owner - in this case the ERC4626 contract
        // eventually we can update this with supplywithPermit we need to be able to get v,r,s params from 721 signature privided by msg.sender
        TransferHelper.safeApprove(WETH, address(lendingPool), leveraged_wethBalance);
        // we updated this approval call to be more explicit
        // TransferHelper.safeApprove(WETH, msg.sender, leveraged_wethBalance);
        console.log("supplying our WETH to aave v3 lending pool");

        // function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        lendingPool.supply(WETH, leveraged_wethBalance, owner, 0);
        console.log("hurray! successfully supplied WETH to aave v3 lending pool");
        console.log("verifying updated aWETH balance after supplying to pool: ", IERC20(aWETH).balanceOf(owner));
        (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
        ) = lendingPool.getUserAccountData(owner);
        console.log("totalCollateralBase: %s", totalCollateralBase);
        console.log("totalDebtBase: %s", totalDebtBase);
        console.log("availableBorrowsBase: %s", availableBorrowsBase);
        console.log("currentLiquidationThreshold: %s", currentLiquidationThreshold);
        console.log("ltv: %s", ltv);
        console.log("healthFactor: %s", healthFactor);
        leveraged_wethBalance = IERC20(WETH).balanceOf(address(this));
        console.log("collateral: contract balanceOf WETH after supplying aave: %s", leveraged_wethBalance);

        
        console.log("WBTC to repay: %s", wbtcToRepay);
        console.log("executeOperation completed, borrow and swap successful, converting flashloan to variable interest debt position");
        return true;
    }

    // Fallback function to receive ETH
    receive() external payable {}
}

