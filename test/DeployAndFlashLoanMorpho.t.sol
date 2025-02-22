// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

// Minimal IERC20 interface with only the required function
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}

// Contract to execute the flash loan
contract FlashLoanExample is IMorphoFlashLoanCallback {
    IMorpho public immutable morpho;
    IERC20 public immutable dai;

    // Constructor sets the Morpho and DAI contract addresses
    constructor(address _morpho, address _dai) {
        morpho = IMorpho(_morpho);
        dai = IERC20(_dai);
    }

    // Function to initiate the flash loan
    function initiateFlashLoan(uint256 amount) external {
        // Empty data since no specific callback data is needed
        bytes memory data = "";
        morpho.flashLoan(address(dai), amount, data);
    }

    // Callback function required by Morpho
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        // Ensure only Morpho can call this
        require(msg.sender == address(morpho), "Unauthorized");
        // Approve Morpho to pull back the borrowed assets
        dai.approve(address(morpho), assets);
    }
}

// Script to deploy and execute the flash loan
contract DeployAndFlashLoanMorpho is Script {
    function run() external {
        // Start broadcasting transactions from the sender
        vm.startBroadcast();

        // Deploy the FlashLoanExample contract with Morpho and DAI addresses
        FlashLoanExample fl = new FlashLoanExample(
            0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, // Morpho contract
            0x6B175474E89094C44Da98b954EedeAC495271d0F  // DAI contract
        );

        // Initiate a flash loan of 1000 DAI (1000e18 due to 18 decimals)
        fl.initiateFlashLoan(1000e18);

        // Stop broadcasting
        vm.stopBroadcast();
    }
}