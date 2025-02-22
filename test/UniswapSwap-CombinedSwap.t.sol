// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/Script.sol";
import "../lib/forge-std/src/console.sol";
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

contract CombinedSwap {
    address public owner;
    IUniswapV2Router public constant v2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ISwapRouter public constant v3Router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 public constant poolFee = 3000;

    event SwapExecuted(string protocol, uint256 amountIn, uint256 amountOut);

    constructor() {
        owner = msg.sender;
    }

    function formatAmount(uint256 amount) public pure returns (uint256 whole, uint256 decimal) {
        whole = amount / 1e18;
        decimal = (amount % 1e18) / 1e14; // Show 4 decimal places
        return (whole, decimal);
    }

    function swapV2_DAItoWETH(uint256 amountIn) external returns (uint256 amountOut) {
        require(msg.sender == owner, "Only owner");

        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        console.log("\n=== V2 Swap (DAI -> WETH) ===");
        (uint256 daiWhole, uint256 daiDecimal) = formatAmount(dai.balanceOf(address(this)));
        console.log("Initial DAI Balance: %s.%s", daiWhole, daiDecimal);
        (uint256 wethWhole, uint256 wethDecimal) = formatAmount(weth.balanceOf(address(this)));
        console.log("Initial WETH Balance: %s.%s", wethWhole, wethDecimal);

        require(dai.approve(address(v2Router), amountIn), "V2 approval failed");
        console.log("V2 Router approved for %s DAI", amountIn / 1e18);

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(weth);

        uint[] memory amounts = v2Router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp + 15
        );
        amountOut = amounts[1];

        (daiWhole, daiDecimal) = formatAmount(amountIn);
        console.log("DAI spent: %s.%s", daiWhole, daiDecimal);
        (wethWhole, wethDecimal) = formatAmount(amountOut);
        console.log("WETH received: %s.%s", wethWhole, wethDecimal);

        emit SwapExecuted("Uniswap V2", amountIn, amountOut);
        return amountOut;
    }

    function swapV3_WETHtoDAI(uint256 amountIn) external returns (uint256 amountOut) {
        require(msg.sender == owner, "Only owner");
        require(amountIn > 0, "No WETH to swap");

        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        console.log("\n=== V3 Swap (WETH -> DAI) ===");
        (uint256 wethWhole, uint256 wethDecimal) = formatAmount(weth.balanceOf(address(this)));
        console.log("Initial WETH Balance: %s.%s", wethWhole, wethDecimal);
        (uint256 daiWhole, uint256 daiDecimal) = formatAmount(dai.balanceOf(address(this)));
        console.log("Initial DAI Balance: %s.%s", daiWhole, daiDecimal);

        require(weth.approve(address(v3Router), amountIn), "V3 approval failed");
        (wethWhole, wethDecimal) = formatAmount(amountIn);
        console.log("V3 Router approved for %s.%s WETH", wethWhole, wethDecimal);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(dai),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        amountOut = v3Router.exactInputSingle(params);

        (wethWhole, wethDecimal) = formatAmount(amountIn);
        console.log("WETH spent: %s.%s", wethWhole, wethDecimal);
        (daiWhole, daiDecimal) = formatAmount(amountOut);
        console.log("DAI received: %s.%s", daiWhole, daiDecimal);

        emit SwapExecuted("Uniswap V3", amountIn, amountOut);
        return amountOut;
    }
}

contract DeployAndExecuteSwaps is Script {
    function logBalances(address contractAddr, string memory stage) internal view {
        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        console.log("\n%s", stage);
        (uint256 daiWhole, uint256 daiDecimal) = CombinedSwap(payable(contractAddr)).formatAmount(dai.balanceOf(contractAddr));
        console.log("Contract DAI Balance: %s.%s", daiWhole, daiDecimal);
        (uint256 wethWhole, uint256 wethDecimal) = CombinedSwap(payable(contractAddr)).formatAmount(weth.balanceOf(contractAddr));
        console.log("Contract WETH Balance: %s.%s", wethWhole, wethDecimal);
        console.log("----------------------------------------");
    }

    function run() external {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address DAI_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

        console.log("Starting Combined Swap Script");

        vm.startBroadcast(DAI_WHALE);

        CombinedSwap swapContract = new CombinedSwap();
        console.log("Swap contract deployed at:", address(swapContract));

        uint256 initialAmount = 1000 * 10**18;
        require(IERC20(DAI).transfer(address(swapContract), initialAmount), "Transfer failed");

        logBalances(address(swapContract), "Initial Balances:");

        uint256 wethAmount = swapContract.swapV2_DAItoWETH(initialAmount);
        logBalances(address(swapContract), "After V2 Swap (DAI -> WETH):");

        if (wethAmount > 0) {
            swapContract.swapV3_WETHtoDAI(wethAmount);
            logBalances(address(swapContract), "After V3 Swap (WETH -> DAI):");
        } else {
            console.log("Skipping V3 swap due to zero WETH received from V2 swap");
        }

        vm.stopBroadcast();
    }
}