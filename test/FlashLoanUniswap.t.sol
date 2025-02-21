//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/Script.sol";
import "../lib/forge-std/src/console.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3FlashCallback} from "../lib/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

contract UniswapFlashLoan is IUniswapV3FlashCallback {
    address public owner;
    IUniswapV3Pool public pool;

    event FlashLoanExecuted(uint256 amount, uint256 fee);

    constructor(address _pool) {
        owner = msg.sender;
        pool = IUniswapV3Pool(_pool);
    }

    function requestFlashLoan(uint256 amount0, uint256 amount1) external {
        require(msg.sender == owner, "Only owner");
        console.log("Requesting flash loan of:", amount0 / 1e6, "USDC");
        pool.flash(address(this), amount0, amount1, "");
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata
    ) external override {
        require(msg.sender == address(pool), "Only pool");

        address token0 = pool.token0();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        console.log("Balance in callback:", balance0 / 1e6, "USDC");
        console.log("Fee to pay:", fee0 / 1e6, "USDC");

        if (fee0 > 0) {
            uint256 repayment = balance0;
            IERC20(token0).transfer(address(pool), repayment);
            console.log("Repaid:", repayment / 1e6, "USDC");
            emit FlashLoanExecuted(balance0 - fee0, fee0);
        }

        if (fee1 > 0) {
            address token1 = pool.token1();
            uint256 balance1 = IERC20(token1).balanceOf(address(this));
            IERC20(token1).transfer(address(pool), balance1);
        }
    }

    function withdraw(address token, uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        IERC20(token).transfer(msg.sender, amount);
    }
}

contract DeployAndFlashLoanUniswap is Script {
    function logBalances(
        address usdc,
        address whale,
        address flashLoan
    ) internal view {
        console.log("USDC Balances:");
        console.log("- Whale:", IERC20(usdc).balanceOf(whale) / 1e6, "USDC");
        console.log("- Contract:", IERC20(usdc).balanceOf(flashLoan) / 1e6, "USDC");
    }

    function run() external {
        address UNIV3_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC_WHALE = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;

        console.log("----------------------------------------");
        console.log("Starting Uniswap V3 Flash Loan Script");
        console.log("Pool:", UNIV3_POOL);

        // Just display pool info
        uint256 usdcBalance = IERC20(USDC).balanceOf(UNIV3_POOL);
        uint256 wethBalance = IERC20(WETH).balanceOf(UNIV3_POOL);

        console.log("Pool Balances (Available for Flash Loan):");
        console.log("- USDC:", usdcBalance / 1e6, "USDC");
        console.log("- WETH:", wethBalance / 1e18, "ETH");

        // Initial balances
        uint256 initialWhaleBalance = IERC20(USDC).balanceOf(USDC_WHALE);
        console.log("Initial Whale Balance:", initialWhaleBalance / 1e6, "USDC");

        // Deploy contract
        vm.broadcast(USDC_WHALE);
        UniswapFlashLoan flashLoan = new UniswapFlashLoan(UNIV3_POOL);
        console.log("FlashLoan deployed at:", address(flashLoan));

        // Fund contract
        vm.broadcast(USDC_WHALE);
        IERC20(USDC).transfer(address(flashLoan), 10_000_000);
        console.log("Funded contract with: 10 USDC");

        console.log("----------------------------------------");
        logBalances(USDC, USDC_WHALE, address(flashLoan));
        console.log("----------------------------------------");

        // Keep the working flash loan amount
        uint256 flashAmount = 10_000 * 1e6; // 10,000 USDC
        vm.broadcast(USDC_WHALE);
        flashLoan.requestFlashLoan(flashAmount, 0);

        console.log("----------------------------------------");
        logBalances(USDC, USDC_WHALE, address(flashLoan));
    }
}