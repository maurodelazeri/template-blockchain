// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
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
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlashLoanSwap is IMorphoFlashLoanCallback {
    IMorpho public immutable morpho;
    IERC20 public immutable dai;
    IERC20 public immutable weth;
    IUniswapV2Router public immutable v2Router;
    ISwapRouter public immutable v3Router;
    uint24 public constant poolFee = 3000;
    address public owner;

    event FlashLoanExecuted(uint256 borrowed, uint256 profit);

    constructor(
        address _morpho,
        address _dai,
        address _weth,
        address _v2Router,
        address _v3Router
    ) {
        morpho = IMorpho(_morpho);
        dai = IERC20(_dai);
        weth = IERC20(_weth);
        v2Router = IUniswapV2Router(_v2Router);
        v3Router = ISwapRouter(_v3Router);
        owner = msg.sender;
    }

    function formatAmount(uint256 amount) public pure returns (uint256 whole, uint256 decimal) {
        whole = amount / 1e18;
        decimal = (amount % 1e18) / 1e14; // Show 4 decimal places
        return (whole, decimal);
    }

    function initiateFlashLoan(uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        bytes memory data = "";
        morpho.flashLoan(address(dai), amount, data);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata /* data */) external override {
        require(msg.sender == address(morpho), "Unauthorized");

        // Log initial balance
        (uint256 daiWhole, uint256 daiDecimal) = formatAmount(dai.balanceOf(address(this)));
        console.log("\nFlash Loan Received: %s.%s DAI", daiWhole, daiDecimal);

        // 1. Swap DAI to WETH on Uniswap V2
        dai.approve(address(v2Router), assets);
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(weth);

        uint[] memory v2Amounts = v2Router.swapExactTokensForTokens(
            assets,
            0,
            path,
            address(this),
            block.timestamp + 15
        );
        uint256 wethReceived = v2Amounts[1];

        (uint256 wethWhole, uint256 wethDecimal) = formatAmount(wethReceived);
        console.log("V2 Swap - WETH Received: %s.%s", wethWhole, wethDecimal);

        // 2. Swap WETH back to DAI on Uniswap V3
        weth.approve(address(v3Router), wethReceived);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(dai),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: wethReceived,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 daiReceived = v3Router.exactInputSingle(params);
        (daiWhole, daiDecimal) = formatAmount(daiReceived);
        console.log("V3 Swap - DAI Received: %s.%s", daiWhole, daiDecimal);

        // 3. Repay the flash loan
        dai.approve(address(morpho), assets);
        uint256 profit = daiReceived > assets ? daiReceived - assets : 0;
        (uint256 profitWhole, uint256 profitDecimal) = formatAmount(profit);
        console.log("Profit: %s.%s DAI", profitWhole, profitDecimal);

        emit FlashLoanExecuted(assets, profit);
    }

    // Allow owner to withdraw any remaining tokens
    function withdraw(address token) external {
        require(msg.sender == owner, "Only owner");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(owner, balance);
        }
    }
}

contract DeployAndFlashLoanMorphoUniswap is Script {
    function logBalances(address contractAddr, string memory stage) internal view {
        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        console.log("\n%s", stage);
        (uint256 daiWhole, uint256 daiDecimal) = FlashLoanSwap(payable(contractAddr)).formatAmount(dai.balanceOf(contractAddr));
        console.log("Contract DAI Balance: %s.%s", daiWhole, daiDecimal);
        (uint256 wethWhole, uint256 wethDecimal) = FlashLoanSwap(payable(contractAddr)).formatAmount(weth.balanceOf(contractAddr));
        console.log("Contract WETH Balance: %s.%s", wethWhole, wethDecimal);
        console.log("----------------------------------------");
    }

    function run() external {
        address MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        address V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        vm.startBroadcast();

        FlashLoanSwap fl = new FlashLoanSwap(
            MORPHO,
            DAI,
            WETH,
            V2_ROUTER,
            V3_ROUTER
        );
        console.log("Flash Loan contract deployed at:", address(fl));

        logBalances(address(fl), "Before Flash Loan:");

        // Initiate flash loan of 100M DAI
        uint256 flashLoanAmount = 100_000_000 * 10**18; // 100M DAI
        fl.initiateFlashLoan(flashLoanAmount);

        logBalances(address(fl), "After Flash Loan:");

        vm.stopBroadcast();
    }
}