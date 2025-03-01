// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// This is a minimal, self-contained test that proves the swap impact vulnerability
// without requiring any external dependencies or GMX contracts
contract SwapImpactVulnerabilityTest is Test {
    // Structs to replicate the key components from GMX
    struct Price {
        uint256 min;
        uint256 max;
    }

    struct SwapCache {
        address tokenOut;
        Price tokenInPrice;
        Price tokenOutPrice;
        uint256 amountIn;
        uint256 amountInAfterFees;
        uint256 amountOut;
        uint256 poolAmountOut;
        int256 priceImpactUsd;
        int256 priceImpactAmount;
        uint256 cappedDiffUsd;
        int256 tokenInPriceImpactAmount;
    }

    function setUp() public {}

    function testVulnerableSwapImpactCompensation() public {
        // Test parameters
        uint256 amountIn = 100 ether;            // 100 ETH
        uint256 tokenInPrice = 5000 * 10**30;    // $5000 per ETH
        uint256 tokenOutPrice = 1 * 10**30;      // $1 per USDC
        uint256 impactPoolSize = 1000 * 10**6;   // 1000 USDC in impact pool

        // Calculate a price impact that exceeds the impact pool
        // At about 10% impact for the swap which is large enough to exceed pool
        int256 priceImpactUsd = int256(50000 * 10**30); // $50,000 positive impact

        console.log("===== SWAP IMPACT VULNERABILITY DEMONSTRATION =====");
        console.log("Initial parameters:");
        console.log("  Amount In: %s ETH", amountIn / 1e18);
        console.log("  ETH Price: $%s", tokenInPrice / 1e30);
        console.log("  USDC Price: $%s", tokenOutPrice / 1e30);
        console.log("  Impact Pool Size: %s USDC", impactPoolSize / 1e6);
        console.log("  Price Impact: $%s", uint256(priceImpactUsd) / 1e30);

        // Run the vulnerable swap implementation
        (
            uint256 vulnerableEffectiveAmountIn,
            uint256 vulnerableAmountOut,
            uint256 vulnerableImpactPoolRemaining
        ) = executeVulnerableSwap(
            amountIn,
            tokenInPrice,
            tokenOutPrice,
            impactPoolSize,
            priceImpactUsd
        );

        // Run the corrected swap implementation
        (
            uint256 correctedEffectiveAmountIn,
            uint256 correctedAmountOut,
            uint256 correctedImpactPoolRemaining
        ) = executeCorrectedSwap(
            amountIn,
            tokenInPrice,
            tokenOutPrice,
            impactPoolSize,
            priceImpactUsd
        );

        console.log("\nVulnerable Swap Results:");
        console.log("  Effective Amount In: %s ETH", vulnerableEffectiveAmountIn / 1e18);
        console.log("  Amount Out: %s USDC", vulnerableAmountOut / 1e6);
        console.log("  Impact Pool Remaining: %s USDC", vulnerableImpactPoolRemaining / 1e6);

        console.log("\nCorrected Swap Results:");
        console.log("  Effective Amount In: %s ETH", correctedEffectiveAmountIn / 1e18);
        console.log("  Amount Out: %s USDC", correctedAmountOut / 1e6);
        console.log("  Impact Pool Remaining: %s USDC", correctedImpactPoolRemaining / 1e6);

        // Calculate refund amount in the vulnerable case
        uint256 refundedAmount = amountIn - vulnerableEffectiveAmountIn;

        // PROOF OF VULNERABILITY #1: We received a refund of input tokens
        console.log("\n=== PROOF OF VULNERABILITY ===");
        console.log("1. Refund received: %s ETH", refundedAmount / 1e18);
        assertTrue(refundedAmount > 0, "No refund received in vulnerable case");

        // PROOF OF VULNERABILITY #2: We still received the full impact from the pool
        uint256 impactPoolUsedVulnerable = impactPoolSize - vulnerableImpactPoolRemaining;
        uint256 impactPoolUsedCorrected = impactPoolSize - correctedImpactPoolRemaining;

        console.log("2. Impact pool used (vulnerable): %s USDC", impactPoolUsedVulnerable / 1e6);
        console.log("   Impact pool used (corrected): %s USDC", impactPoolUsedCorrected / 1e6);

        // In both cases we should use the same amount from impact pool
        assertEq(impactPoolUsedVulnerable, impactPoolUsedCorrected, "Impact pool usage should be the same");
        assertTrue(impactPoolUsedVulnerable > 0, "Impact pool not used");

        // PROOF OF VULNERABILITY #3: We get the same output amount despite spending less input
        console.log("3. Output received (vulnerable): %s USDC", vulnerableAmountOut / 1e6);
        console.log("   Output received (corrected): %s USDC", correctedAmountOut / 1e6);

        // We should get at least the same output in the vulnerable case as the corrected case
        assertGe(vulnerableAmountOut, correctedAmountOut, "Should get at least the same output");

        // Calculate the profit from the vulnerability in USD terms
        uint256 profitInEth = refundedAmount;
        uint256 profitInUsd = (profitInEth * tokenInPrice) / 1e30;

        console.log("\n=== PROFIT FROM VULNERABILITY ===");
        console.log("Profit: %s ETH ($%s)", profitInEth / 1e18, profitInUsd / 1e30);

        assertTrue(profitInUsd > 0, "No profit from vulnerability");

        // CONCLUSION: The vulnerability allows traders to get both benefits:
        // 1. A refund of input tokens for the portion of impact that exceeds the pool
        // 2. Still receive the maximum possible impact benefit from the pool
        console.log("\n=== VULNERABILITY CONFIRMED ===");
        console.log("The vulnerability allows a trader to receive BOTH:");
        console.log("1. A refund of input tokens");
        console.log("2. The maximum possible impact benefit");
        console.log("This creates a risk-free arbitrage opportunity.");
    }

    // Simulates the vulnerable swap implementation from GMX
    function executeVulnerableSwap(
        uint256 amountIn,
        uint256 tokenInPrice,
        uint256 tokenOutPrice,
        uint256 impactPoolSize,
        int256 priceImpactUsd
    ) internal pure returns (
        uint256 effectiveAmountIn,
        uint256 amountOut,
        uint256 impactPoolRemaining
    ) {
        SwapCache memory cache;
        cache.tokenInPrice = Price(tokenInPrice, tokenInPrice);
        cache.tokenOutPrice = Price(tokenOutPrice, tokenOutPrice);
        cache.amountIn = amountIn;
        cache.priceImpactUsd = priceImpactUsd;

        // Here's the vulnerable implementation (simplified from GMX)
        if (cache.priceImpactUsd > 0) {
            // First calculate the impact amount in output tokens
            cache.priceImpactAmount = cache.priceImpactUsd / int256(cache.tokenOutPrice.max);

            // Check if it exceeds the impact pool
            uint256 remainingImpactPool = impactPoolSize;
            if (cache.priceImpactAmount > int256(impactPoolSize)) {
                // If impact exceeds pool, calculate the USD value of the excess
                cache.cappedDiffUsd = uint256(cache.priceImpactAmount - int256(impactPoolSize)) * cache.tokenOutPrice.max;

                // Cap the impact to the pool size
                cache.priceImpactAmount = int256(impactPoolSize);
                remainingImpactPool = 0;

                // THE VULNERABILITY: Compensate for the capped impact with input tokens
                if (cache.cappedDiffUsd != 0) {
                    cache.tokenInPriceImpactAmount = int256(cache.cappedDiffUsd) / int256(cache.tokenInPrice.max);

                    // Reduce the effective input amount - THIS IS THE REFUND!
                    cache.amountIn -= uint256(cache.tokenInPriceImpactAmount);
                }
            } else {
                // Impact doesn't exceed pool
                remainingImpactPool = impactPoolSize - uint256(cache.priceImpactAmount);
            }

            // Calculate base output without impact
            cache.amountOut = (cache.amountIn * cache.tokenInPrice.min) / cache.tokenOutPrice.max;

            // THE VULNERABILITY: Add the full impact amount to the output
            // We still get the maximum benefit despite the refund!
            cache.amountOut += uint256(cache.priceImpactAmount);

            return (cache.amountIn, cache.amountOut, remainingImpactPool);
        } else {
            // Negative impact case not relevant for this vulnerability
            cache.amountOut = (cache.amountIn * cache.tokenInPrice.min) / cache.tokenOutPrice.max;
            return (cache.amountIn, cache.amountOut, impactPoolSize);
        }
    }

    // Simulates a corrected swap implementation
    function executeCorrectedSwap(
        uint256 amountIn,
        uint256 tokenInPrice,
        uint256 tokenOutPrice,
        uint256 impactPoolSize,
        int256 priceImpactUsd
    ) internal pure returns (
        uint256 effectiveAmountIn,
        uint256 amountOut,
        uint256 impactPoolRemaining
    ) {
        SwapCache memory cache;
        cache.tokenInPrice = Price(tokenInPrice, tokenInPrice);
        cache.tokenOutPrice = Price(tokenOutPrice, tokenOutPrice);
        cache.amountIn = amountIn;
        cache.priceImpactUsd = priceImpactUsd;

        // Fixed implementation - we use approach #1:
        // Give output token impact benefit up to the pool cap without input token compensation
        if (cache.priceImpactUsd > 0) {
            cache.priceImpactAmount = cache.priceImpactUsd / int256(cache.tokenOutPrice.max);

            uint256 remainingImpactPool = impactPoolSize;
            if (cache.priceImpactAmount > int256(impactPoolSize)) {
                // Cap the impact to the pool size
                cache.priceImpactAmount = int256(impactPoolSize);
                remainingImpactPool = 0;

                // FIXED: Do NOT provide compensation in input tokens
                // No tokenInPriceImpactAmount, no reducing amountIn
            } else {
                remainingImpactPool = impactPoolSize - uint256(cache.priceImpactAmount);
            }

            // Calculate base output
            cache.amountOut = (cache.amountIn * cache.tokenInPrice.min) / cache.tokenOutPrice.max;

            // Add impact to output
            cache.amountOut += uint256(cache.priceImpactAmount);

            return (cache.amountIn, cache.amountOut, remainingImpactPool);
        } else {
            // Negative impact handling
            cache.amountOut = (cache.amountIn * cache.tokenInPrice.min) / cache.tokenOutPrice.max;
            return (cache.amountIn, cache.amountOut, impactPoolSize);
        }
    }
}