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

contract UniswapV2Swap {
    address public owner;
    // Uniswap V2 Router address
    IUniswapV2Router public constant router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    event SwapExecuted(uint256 amountIn, uint256 amountOut);

    constructor() {
        owner = msg.sender;
    }

    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        require(msg.sender == owner, "Only owner");

        uint256 initialTokenIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 initialTokenOut = IERC20(tokenOut).balanceOf(address(this));
        console.log("\nInitial Balances:");
        console.log("DAI: %s (%s DAI)", initialTokenIn, initialTokenIn / 1e18);
        console.log("WETH: %s (%s WETH)", initialTokenOut, initialTokenOut / 1e18);

        IERC20(tokenIn).approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;  // DAI
        path[1] = tokenOut; // WETH

        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp + 15
        );
        amountOut = amounts[1];

        // Updated logging with decimal precision
        console.log("\n----------------------------------------");
        console.log("Swap Complete!");
        console.log("DAI spent: %s (%s DAI)", amountIn, amountIn / 1e18);
        uint256 wethInteger = amountOut / 1e18;
        uint256 wethFraction = amountOut % 1e18; // Full precision
        console.log("WETH received: %s (%s.%s WETH)", amountOut, wethInteger, wethFraction);
        console.log("----------------------------------------\n");

        emit SwapExecuted(amountIn, amountOut);
        return amountOut;
    }

    function withdraw(address token) external {
        require(msg.sender == owner, "Only owner");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            console.log("Withdrawing token: %s", token);
            console.log("Amount: %s (%s)", balance, balance / 1e18);
            IERC20(token).transfer(msg.sender, balance);
        }
    }
}

contract DeployAndSwapUniswapV2 is Script {
    function logBalances(
        address dai,
        address weth,
        address account,
        string memory label
    ) internal view {
        uint256 daiBalance = IERC20(dai).balanceOf(account);
        uint256 wethBalance = IERC20(weth).balanceOf(account);

        console.log("\n%s", label);
        console.log("DAI Balance: %s (%s DAI)", daiBalance, daiBalance / 1e18);
        // For WETH, split into integer and fractional parts
        uint256 wethInteger = wethBalance / 1e18;
        uint256 wethFraction = wethBalance % 1e18; // Remainder for decimals
        console.log("WETH Balance: %s (%s.%s WETH)", wethBalance, wethInteger, wethFraction);
        console.log("----------------------------------------\n");
    }

    function run() external {
        // Token and whale addresses
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address DAI_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

        console.log("----------------------------------------");
        console.log("Starting Uniswap V2 Swap Script");

        // Impersonate the DAI whale
        vm.startBroadcast(DAI_WHALE);

        // Deploy the swap contract
        UniswapV2Swap swapContract = new UniswapV2Swap();
        console.log("Swap contract deployed at:", address(swapContract));

        // Transfer 1000 DAI to the contract
        uint256 amountToSwap = 1000 * 10**18; // 1000 DAI
        IERC20(DAI).transfer(address(swapContract), amountToSwap);

        // Log balances before swap
        logBalances(DAI, WETH, address(swapContract), "Before Swap:");

        // Execute the swap
        swapContract.swapExactInputSingle(DAI, WETH, amountToSwap);

        // Log balances after swap
        logBalances(DAI, WETH, address(swapContract), "After Swap:");

        vm.stopBroadcast();
    }
}