//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/Script.sol";
import "../lib/forge-std/src/console.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract UniswapSwap {
    address public owner;
    ISwapRouter public constant router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 public constant poolFee = 3000;

    event SwapExecuted(uint256 amountIn, uint256 amountOut);

    constructor() {
        owner = msg.sender;
    }

    function formatWeth(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(amount / 1e18));
    }

    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        require(msg.sender == owner, "Only owner");

        uint256 initialUSDC = IERC20(tokenIn).balanceOf(address(this));
        uint256 initialWETH = IERC20(tokenOut).balanceOf(address(this));

        console.log("Initial Balances:");
        console.log("USDC:", initialUSDC / 1e6, "USDC");
        console.log("WETH Raw Balance:", initialWETH);

        IERC20(tokenIn).approve(address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = router.exactInputSingle(params);

        uint256 finalUSDC = IERC20(tokenIn).balanceOf(address(this));

        console.log("----------------------------------------");
        console.log("Swap Complete!");
        console.log("USDC spent:", (initialUSDC - finalUSDC) / 1e6, "USDC");
        console.log("WETH received raw:", amountOut);
        console.log("WETH received (in eth):", amountOut / 1e14 / 10000);

        uint256 rate = (amountOut * 1e6) / amountIn;
        console.log("Rate raw:", rate);
        console.log("Rate (WETH/USDC):", rate / 1e14 / 10000);

        uint256 ethPrice = 1800;
        uint256 usdValue = (amountOut * ethPrice) / 1e18;
        console.log("Approximate USD value received:", usdValue);

        emit SwapExecuted(amountIn, amountOut);
        return amountOut;
    }

    function withdraw(address token) external {
        require(msg.sender == owner, "Only owner");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            console.log("Withdrawing WETH raw:", balance);
            console.log("Withdrawing WETH (in eth):", balance / 1e14 / 10000);
            IERC20(token).transfer(msg.sender, balance);
        }
    }
}

contract DeployAndSwapUniswap is Script {
    function logBalances(
        address usdc,
        address weth,
        address account,
        string memory label
    ) internal view {
        uint256 usdcBalance = IERC20(usdc).balanceOf(account);
        uint256 wethBalance = IERC20(weth).balanceOf(account);

        console.log(label);
        console.log("- USDC Balance:", usdcBalance / 1e6, "USDC");
        console.log("- WETH Balance raw:", wethBalance);
        console.log("- WETH Balance (in eth):", wethBalance / 1e14 / 10000);
        console.log("----------------------------------------");
    }

    function run() external {
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC_WHALE = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;

        console.log("----------------------------------------");
        console.log("Starting Uniswap V3 Swap Script");

        vm.startBroadcast(USDC_WHALE);

        // Deploy contract
        UniswapSwap swapContract = new UniswapSwap();
        console.log("Swap contract deployed at:", address(swapContract));

        // Transfer USDC
        uint256 amountToSwap = 1000 * 1e6; // 1000 USDC
        IERC20(USDC).transfer(address(swapContract), amountToSwap);

        logBalances(USDC, WETH, address(swapContract), "Before Swap:");

        // Execute swap
        swapContract.swapExactInputSingle(USDC, WETH, amountToSwap);

        logBalances(USDC, WETH, address(swapContract), "After Swap:");

        // Withdraw WETH
        swapContract.withdraw(WETH);


        logBalances(USDC, WETH, address(swapContract), "After Withdrawal:");

        vm.stopBroadcast();
    }
}