//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/Script.sol";
import "../lib/forge-std/src/console.sol";
import {FlashLoanSimple} from "src/FlashLoanSimple.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract FlashLoanSimpleTest is Test {
    FlashLoanSimple public flashLoanSimple;

    function setUp() public {
        // Create a new instance of the flashLoanSimple contract.
        flashLoanSimple = new FlashLoanSimple();
        // Give 10 USDC to the flashLoanSimple contract. (6 decimals)
        deal(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, address(flashLoanSimple), 10_000_000);
    }

    // Request a flash loan of 10,000 USDC.
    function testRequestFlashLoan() public {
        flashLoanSimple.requestFlashLoan(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 10_000);
    }

    // Request a flash loan of 10,000 USDC and execute the operation.
    function testExecuteOperation() public {
        flashLoanSimple.requestFlashLoan(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 10_000);
        flashLoanSimple.executeOperation(
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), 10_000, 10_000_000_000 * 9 / 10000, address(0), ""
        );
    }

    // Withdraw the initial 10 USDC.
    function testWithdraw() public {
        flashLoanSimple.withdraw(address(this), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 10);
    }

    // Request a flash loan of 100,000 USDC, transaction is expected to revert.
    function testRequestFlashLoanFail() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        flashLoanSimple.requestFlashLoan(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 100_000);
    }

    // Withdraw 11 USDC, which is more than the initial amount.
    function testWithdrawBalanceFail() public {
        vm.expectRevert("Insufficient balance.");
        flashLoanSimple.withdraw(address(this), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 11);
    }

    // Withdrawal with non-owner address.
    function testWithdrawOwnerFail() public {
        vm.prank(address(1));
        vm.expectRevert("Only callable by the owner.");
        flashLoanSimple.withdraw(address(this), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 10);
    }
}


contract DeployAndRunContract is Script {
    function run() external {
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address USDC_WHALE = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;

        // In AAVE V3, the liquidity is actually held in the aToken contract
        address AUSDC_V3 = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;  // aUSDC v3 token address

        console.log("----------------------------------------");
        console.log("Starting Flash Loan Script");
        console.log("USDC Address:", USDC);
        console.log("USDC Whale Address:", USDC_WHALE);
        console.log("aUSDC V3 Address:", AUSDC_V3);

        // Check initial balances
        uint256 whaleBalance = IERC20(USDC).balanceOf(USDC_WHALE);
        console.log("USDC Whale Initial Balance:", whaleBalance / 1e6, "USDC");

        // Check aUSDC balance (this represents the actual pool liquidity)
        uint256 aTokenBalance = IERC20(AUSDC_V3).totalSupply();
        console.log("Aave V3 Pool Total Liquidity:", aTokenBalance / 1e6, "USDC");
        console.log("----------------------------------------");

        // Deploy FlashLoanSimple contract
        vm.broadcast(USDC_WHALE);
        FlashLoanSimple flashLoanSimple = new FlashLoanSimple();
        console.log("FlashLoanSimple deployed at:", address(flashLoanSimple));

        // Get pool information
        address poolAddress = address(flashLoanSimple.POOL());
        console.log("Aave Pool Address:", poolAddress);
        console.log("----------------------------------------");

        // Initial transfer to contract
        uint256 transferAmount = 10_000_000; // 10 USDC (with 6 decimals)
        vm.broadcast(USDC_WHALE);
        IERC20(USDC).transfer(address(flashLoanSimple), transferAmount);
        console.log("Transferred to FlashLoanSimple:", transferAmount / 1e6, "USDC");

        uint256 contractBalance = IERC20(USDC).balanceOf(address(flashLoanSimple));
        console.log("FlashLoanSimple Contract Balance:", contractBalance / 1e6, "USDC");
        console.log("----------------------------------------");

        // Flash loan parameters
        uint256 borrowAmount = 10_000; // Raw amount, not scaled by decimals
        uint256 fee = (borrowAmount * 5) / 10000; // 0.05% fee
        uint256 feeInUSDC = fee * 1e6; // Convert fee to USDC decimals

        console.log("Flash Loan Parameters:");
        console.log("Borrowing Amount:", borrowAmount, "USDC");
        console.log("Flash Loan Fee (0.05%):", feeInUSDC / 1e6, "USDC");
        console.log("Total to Repay:", (borrowAmount + fee), "USDC");
        console.log("----------------------------------------");

        // Request flash loan
        vm.broadcast(USDC_WHALE);
        flashLoanSimple.requestFlashLoan(USDC, borrowAmount);
        console.log("Flash Loan Requested Successfully");

        // Calculate premium and execute operation
        uint256 premium = (borrowAmount * 1e9 * 9) / 10000;

        vm.broadcast(USDC_WHALE);
        flashLoanSimple.executeOperation(
            address(USDC),
            borrowAmount,
            premium,
            address(0),
            ""
        );

        console.log("Flash Loan Operation Executed");
        console.log("Premium Paid:", premium / 1e6, "USDC");
        console.log("----------------------------------------");

        // Final balance checks
        uint256 finalContractBalance = IERC20(USDC).balanceOf(address(flashLoanSimple));
        uint256 finalWhaleBalance = IERC20(USDC).balanceOf(USDC_WHALE);

        console.log("Final Balances:");
        console.log("FlashLoanSimple Contract Final Balance:", finalContractBalance / 1e6, "USDC");
        console.log("USDC Whale Final Balance:", finalWhaleBalance / 1e6, "USDC");

        uint256 totalCost = whaleBalance - finalWhaleBalance;
        console.log("Total Cost of Operation:", totalCost / 1e6, "USDC");
        console.log("----------------------------------------");
    }
}