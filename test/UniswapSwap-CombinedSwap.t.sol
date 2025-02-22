// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/Script.sol";
import "../lib/forge-std/src/console.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Uniswap V2 Router Interface
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

// Uniswap V3 Router Interface
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
    uint24 public constant poolFee = 3000; // 0.3% fee

    event SwapExecuted(string protocol, uint256 amountIn, uint256 amountOut);

    constructor() {
        owner = msg.sender;
    }

    // V2 Swap: DAI -> WETH
    function swapV2_DAItoWETH(uint256 amountIn) external returns (uint256 amountOut) {
        require(msg.sender == owner, "Only owner");

        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        // Log initial balances
        console.log("\n=== V2 Swap (DAI -> WETH) ===");
        console.log("Initial DAI Balance: %s", dai.balanceOf(address(this)) / 1e18);
        console.log("Initial WETH Balance: %s", weth.balanceOf(address(this)) / 1e18);

        // Approve and swap
        dai.approve(address(v2Router), amountIn);
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

        // Log results
        console.log("DAI spent: %s", amountIn / 1e18);
        console.log("WETH received: %s", amountOut / 1e18);
        emit SwapExecuted("Uniswap V2", amountIn, amountOut);
        return amountOut;
    }

    // V3 Swap: WETH -> DAI
    function swapV3_WETHtoDAI(uint256 amountIn) external returns (uint256 amountOut) {
        require(msg.sender == owner, "Only owner");

        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // Log initial balances
        console.log("\n=== V3 Swap (WETH -> DAI) ===");
        console.log("Initial WETH Balance: %s", weth.balanceOf(address(this)) / 1e18);
        console.log("Initial DAI Balance: %s", dai.balanceOf(address(this)) / 1e18);

        // Approve and swap
        weth.approve(address(v3Router), amountIn);

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

        // Log results
        console.log("WETH spent: %s", amountIn / 1e18);
        console.log("DAI received: %s", amountOut / 1e18);
        emit SwapExecuted("Uniswap V3", amountIn, amountOut);
        return amountOut;
    }
}

contract DeployAndExecuteSwaps is Script {
    function logBalances(address contractAddr, string memory stage) internal view {
        IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        console.log("\n%s", stage);
        console.log("Contract DAI Balance: %s", dai.balanceOf(contractAddr) / 1e18);
        console.log("Contract WETH Balance: %s", weth.balanceOf(contractAddr) / 1e18);
        console.log("----------------------------------------");
    }

    function run() external {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address DAI_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

        console.log("Starting Combined Swap Script");

        vm.startBroadcast(DAI_WHALE);

        // Deploy contract
        CombinedSwap swapContract = new CombinedSwap();
        console.log("Swap contract deployed at:", address(swapContract));

        // Transfer 1000 DAI to contract
        uint256 initialAmount = 1000 * 10**18; // 1000 DAI
        IERC20(DAI).transfer(address(swapContract), initialAmount);

        // Log initial balances
        logBalances(address(swapContract), "Initial Balances:");

        // Execute V2 swap (DAI -> WETH)
        uint256 wethAmount = swapContract.swapV2_DAItoWETH(initialAmount);
        logBalances(address(swapContract), "After V2 Swap (DAI -> WETH):");

        // Execute V3 swap (WETH -> DAI)
        swapContract.swapV3_WETHtoDAI(wethAmount);
        logBalances(address(swapContract), "After V3 Swap (WETH -> DAI):");

        vm.stopBroadcast();
    }
}