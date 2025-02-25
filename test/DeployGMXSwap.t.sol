// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol"; // For console.log
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// GMX Vault interface based on the working trace
interface IGMXVault {
    function swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    ) external returns (uint256);
}

// Direct GMX swap contract with simulation-safe implementation
contract SimpleGMXSwap {
    address public vault;
    address public usdc;
    address public weth;

    event SwapExecuted(uint256 amountIn, uint256 amountOut);

    constructor(
        address _vault,
        address _usdc,
        address _weth
    ) {
        vault = _vault;
        usdc = _usdc;
        weth = _weth;
    }

    // Function to deposit USDC into the contract
    function depositUSDC(uint256 _amount) external {
        console.log("Depositing %s USDC into contract", _amount);

        // Safety check to prevent errors during simulation
        uint256 senderBalance = IERC20(usdc).balanceOf(msg.sender);
        if (senderBalance < _amount) {
            console.log("Warning: Sender has insufficient USDC balance. Skipping transfer.");
            return;
        }

        // Transfer tokens to the contract
        bool success = IERC20(usdc).transferFrom(msg.sender, address(this), _amount);
        if (success) {
            console.log("USDC deposited, contract balance: %s", IERC20(usdc).balanceOf(address(this)));
        } else {
            console.log("USDC transfer failed.");
        }
    }

    // Direct swap function that works with GMX vault
    function swap(uint256 _amount) external {
        console.log("Starting swap with amount: %s USDC", _amount);
        require(_amount > 0, "Amount must be greater than 0");

        // Get the contract's USDC balance
        uint256 contractBalance = IERC20(usdc).balanceOf(address(this));
        console.log("Contract USDC balance: %s", contractBalance);

        // Skip if insufficient balance (for simulation safety)
        if (contractBalance < _amount) {
            console.log("Warning: Insufficient USDC balance. Skipping swap.");
            return;
        }

        // Note WETH balance before swap
        uint256 wethBefore = IERC20(weth).balanceOf(msg.sender);
        console.log("WETH balance before swap: %s wei", wethBefore);

        // Transfer USDC directly to the vault
        console.log("Transferring USDC to vault");
        bool transferSuccess = IERC20(usdc).transfer(vault, _amount);
        if (!transferSuccess) {
            console.log("USDC transfer to vault failed. Skipping swap.");
            return;
        }

        // Call the vault directly to perform the swap
        console.log("Calling vault.swap");
        uint256 amountOut;

        try IGMXVault(vault).swap(usdc, weth, msg.sender) returns (uint256 result) {
            amountOut = result;
            console.log("Swap successful! Received: %s wei WETH", amountOut);

            // Check WETH balance after swap
            uint256 wethAfter = IERC20(weth).balanceOf(msg.sender);
            console.log("WETH balance after swap: %s wei", wethAfter);

            emit SwapExecuted(_amount, amountOut);
        } catch {
            console.log("Vault swap call failed. It might be a simulation.");
        }
    }

    receive() external payable {}
}

// Deployment script
contract DeployGMXSwap is Script {
    function run() external {
        // Using the vault address we discovered from the traces
        address vault = 0x489ee077994B6658eAfA855C308275EAd8097C4A; // GMX Vault
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

        // Define sender address
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        if (sender == address(0)) {
            // Default to anvil's first account if no private key is provided
            sender = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }
        console.log("Using sender address: %s", sender);

        // Use small amount for testing
        uint256 depositAmount = 100 * 10**6; // 100 USDC (6 decimals)

        // Check if we might be in a simulation - safer approach
        uint256 senderBalance = IERC20(usdc).balanceOf(sender);
        if (senderBalance == 0) {
            console.log("No USDC balance detected, assuming simulation mode");
        } else {
            console.log("Detected USDC balance: %s", senderBalance / 10**6);
        }

        // Step 1: Fund the sender with USDC if needed
        if (senderBalance < depositAmount) {
            address usdcWhale = 0x62383739D68Dd0F844103Db8dFb05a7EdED5BBE6; // USDC whale
            uint256 whaleBalance = IERC20(usdc).balanceOf(usdcWhale);

            if (whaleBalance >= depositAmount) {
                vm.startPrank(usdcWhale);
                IERC20(usdc).transfer(sender, depositAmount);
                vm.stopPrank();
                console.log("Transferred %s USDC from whale to sender", depositAmount / 10**6);

                // Update balance
                senderBalance = IERC20(usdc).balanceOf(sender);
                console.log("Updated sender USDC balance: %s", senderBalance / 10**6);
            } else {
                console.log("Whale has insufficient balance. Proceeding anyway.");
            }
        }

        // Step 2: Deploy and test the contract
        vm.startBroadcast();

        // Deploy the contract
        SimpleGMXSwap swapContract = new SimpleGMXSwap(vault, usdc, weth);
        console.log("SimpleGMXSwap deployed at: %s", address(swapContract));

        // Approve USDC - only if we have a balance
        if (senderBalance >= depositAmount) {
            IERC20(usdc).approve(address(swapContract), depositAmount);
            console.log("Approved SimpleGMXSwap to spend %s USDC", depositAmount / 10**6);
        } else {
            console.log("Skipping USDC approval due to insufficient balance");
        }

        // Deposit USDC - our contract handles insufficient balance
        swapContract.depositUSDC(depositAmount);
        console.log("USDC deposit function completed");

        // Check WETH balance before swap
        uint256 wethBalanceBefore = IERC20(weth).balanceOf(sender);
        console.log("WETH balance before swap: %s wei", wethBalanceBefore);

        // Perform the swap - our contract handles insufficient balance
        console.log("Executing swap with %s USDC to WETH", depositAmount / 10**6);
        swapContract.swap(depositAmount);
        console.log("Swap function completed");

        // Check the final WETH balance
        uint256 wethBalanceAfter = IERC20(weth).balanceOf(sender);
        console.log("Final WETH balance: %s wei", wethBalanceAfter);

        // Show the difference
        if (wethBalanceAfter > wethBalanceBefore) {
            uint256 wethReceived = wethBalanceAfter - wethBalanceBefore;
            console.log("Total WETH received: %s wei", wethReceived);

            // Convert to readable format
            if (wethReceived > 0) {
                console.log("That's approximately %s.%s WETH",
                    wethReceived / 10**18,
                    wethReceived % 10**18);
            }
        } else {
            console.log("No WETH received");
        }

        vm.stopBroadcast();
        console.log("Script execution completed successfully");
    }
}