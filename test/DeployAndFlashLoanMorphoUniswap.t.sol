// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract ArbitrageFlashLoan is IMorphoFlashLoanCallback {
    IMorpho public immutable morpho;
    IERC20 public immutable dai;
    IERC20 public immutable weth;
    IUniswapV2Router public immutable v2Router;
    ISwapRouter public immutable v3Router;
    IUniswapV2Pair public immutable pair;
    uint24 public constant poolFee = 3000;
    address public owner;

    event FlashLoanExecuted(uint256 borrowed, uint256 ethProfit);
    event StepCompleted(string step, uint256 daiBalance, uint256 wethBalance);

    constructor(
        address _morpho,
        address _dai,
        address _weth,
        address _v2Router,
        address _v3Router,
        address _pair
    ) {
        morpho = IMorpho(_morpho);
        dai = IERC20(_dai);
        weth = IERC20(_weth);
        v2Router = IUniswapV2Router(_v2Router);
        v3Router = ISwapRouter(_v3Router);
        pair = IUniswapV2Pair(_pair);
        owner = msg.sender;
    }

    function formatAmount(uint256 amount) public pure returns (uint256 whole, uint256 decimal) {
        whole = amount / 1e18;
        decimal = (amount % 1e18) / 1e14;
        return (whole, decimal);
    }

    function logBalances(string memory step) internal {
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 wethBalance = weth.balanceOf(address(this));
        (uint256 daiWhole, uint256 daiDecimal) = formatAmount(daiBalance);
        (uint256 wethWhole, uint256 wethDecimal) = formatAmount(wethBalance);

        console.log("\n%s", step);
        console.log("DAI Balance: %s.%s", daiWhole, daiDecimal);
        console.log("WETH Balance: %s.%s", wethWhole, wethDecimal);

        emit StepCompleted(step, daiBalance, wethBalance);
    }

    function initiateFlashLoan() external {
        require(msg.sender == owner, "Only owner");
        uint256 amount = 100000000 * 10**18; // 100M DAI
        bytes memory data = "";
        morpho.flashLoan(address(dai), amount, data);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata) external override {
        require(msg.sender == address(morpho), "Unauthorized");

        logBalances("Flash Loan Received");

        // Step 1: Swap 5M DAI for WETH on Uniswap V2
        uint256 swapAmount = 5000000 * 10**18; // 5M DAI
        dai.approve(address(v2Router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(weth);

        uint[] memory v2Amounts = v2Router.swapExactTokensForTokens(
            swapAmount,
            0, // Accept any amount of WETH
            path,
            address(this),
            block.timestamp + 15
        );

        logBalances("After V2 Swap");

        // Step 2: Remove liquidity (simulation in local environment)
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        // Calculate amounts based on pool share (10%)
        uint256 lpShare = 11036 * 10**18 / 10;
        uint256 totalSupply = 110361 * 10**18;

        uint256 amount0 = (uint256(reserve0) * lpShare) / totalSupply;
        uint256 amount1 = (uint256(reserve1) * lpShare) / totalSupply;

        // Adjust DAI and WETH amounts based on token order
        uint256 daiAmount = token0 == address(dai) ? amount0 : amount1;
        uint256 wethAmount = token0 == address(weth) ? amount0 : amount1;

        console.log("\nSimulated Liquidity Removal:");
        (uint256 daiWhole, uint256 daiDecimal) = formatAmount(daiAmount);
        (uint256 wethWhole, uint256 wethDecimal) = formatAmount(wethAmount);
        console.log("DAI Amount: %s.%s", daiWhole, daiDecimal);
        console.log("WETH Amount: %s.%s", wethWhole, wethDecimal);

        // Step 3: Sell WETH on V3 to get DAI for repayment
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 daiNeeded = assets - daiBalance;
        uint256 wethBalance = weth.balanceOf(address(this));

        // Calculate WETH amount to sell based on approximate V3 price
        uint256 ethToSell = (daiNeeded * 1e18) / 2745; // Approx. 2,745 DAI/ETH
        if (ethToSell > wethBalance) ethToSell = wethBalance;

        weth.approve(address(v3Router), ethToSell);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(dai),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: ethToSell,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        v3Router.exactInputSingle(params);

        logBalances("After V3 Swap");

        // Step 4: Repay flash loan
        dai.approve(address(morpho), assets);
        dai.transfer(address(morpho), assets);

        // Log final profit
        uint256 ethProfit = weth.balanceOf(address(this));
        (wethWhole, wethDecimal) = formatAmount(ethProfit);
        console.log("\nFinal ETH Profit: %s.%s", wethWhole, wethDecimal);

        emit FlashLoanExecuted(assets, ethProfit);
    }
}

contract DeployAndFlashLoanMorphoUniswap is Script {
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant PAIR = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        // Deploy the arbitrage contract
        ArbitrageFlashLoan arbitrage = new ArbitrageFlashLoan(
            MORPHO,
            DAI,
            WETH,
            V2_ROUTER,
            V3_ROUTER,
            PAIR
        );

        console.log("Arbitrage contract deployed at:", address(arbitrage));

        // Mock initial reserves for simulation
        vm.mockCall(
            PAIR,
            abi.encodeWithSelector(IUniswapV2Pair.getReserves.selector),
            abi.encode(5900000 * 10**18, 2100 * 10**18, uint32(block.timestamp))
        );

        // Execute the flash loan
        arbitrage.initiateFlashLoan();

        vm.stopBroadcast();
    }
}