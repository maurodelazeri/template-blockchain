// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IStargatePool {
    function tvlSD() external view returns (uint64);
    function poolBalanceSD() external view returns (uint64);
    function deficitOffsetSD() external view returns (uint64);
    function treasuryFee() external view returns (uint64);
    function sharedDecimals() external view returns (uint8);
    function getAddressConfig() external view returns (AddressConfig memory);
    function paths(uint32 eid) external view returns (Path memory);
    function token() external view returns (address);
    function _sd2ld(uint64 _amountSD) external view returns (uint256);

    // This would be needed for the actual exploitation
    function redeemSend(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory, OFTReceipt memory);
}

interface IFeeLibV1 {
    function feeConfigs(uint32 eid) external view returns (FeeConfig memory);
    function stargateType() external view returns (uint8);
    function applyFeeView(FeeParams calldata _params) external view returns (uint64 amountOutSD);
}

// Define required structs
struct AddressConfig {
    address feeLib;
    address planner;
    address treasurer;
    address tokenMessaging;
    address creditMessaging;
    address lzToken;
}

struct Path {
    uint64 credit;
}

struct FeeConfig {
    bool paused;
    uint64 zone1UpperBound;
    uint64 zone2UpperBound;
    uint24 zone1FeeMillionth;
    uint24 zone2FeeMillionth;
    uint24 zone3FeeMillionth;
    uint24 rewardMillionth;
}

struct FeeParams {
    address sender;
    uint32 dstEid;
    uint64 amountInSD;
    uint64 deficitSD;
    bool toOFT;
    bool isTaxi;
}

struct SendParam {
    uint32 dstEid;
    bytes32 to;
    uint256 amountLD;
    uint256 minAmountLD;
    bytes extraOptions;
    bytes composeMsg;
    bytes oftCmd;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
    address caller;
}

struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
}

contract StargateVulnChecker is Script {
    address constant STARGATE_POOL = 0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F; // Change to the pool you want to check
    uint32 constant DST_EID = 30110; // Destination chain EID to check (e.g., Arbitrum)

    function run() public {
        // Setup
        IStargatePool pool = IStargatePool(STARGATE_POOL);

        // 1. CHECK DEFICIT CONDITION
        uint64 tvlSD = pool.tvlSD();
        uint64 poolBalanceSD = pool.poolBalanceSD();
        uint64 deficitOffsetSD = pool.deficitOffsetSD();
        uint64 deficitSD = 0;

        if (tvlSD + deficitOffsetSD > poolBalanceSD) {
            deficitSD = tvlSD + deficitOffsetSD - poolBalanceSD;
            console.log("DEFICIT CONDITION:  PRESENT");
        } else {
            console.log("DEFICIT CONDITION:  ABSENT");
        }

        console.log("tvlSD:", tvlSD);
        console.log("deficitOffsetSD:", deficitOffsetSD);
        console.log("poolBalanceSD:", poolBalanceSD);
        console.log("deficitSD:", deficitSD);

        // 2. CHECK TREASURY FEE
        uint64 treasuryFeeSD = pool.treasuryFee();
        console.log("treasuryFeeSD:", treasuryFeeSD);
        if (treasuryFeeSD > 0) {
            console.log("TREASURY FEE:  PRESENT");
        } else {
            console.log("TREASURY FEE:  ABSENT");
        }

        // 3. CHECK REWARD VS FEE RATE
        AddressConfig memory config = pool.getAddressConfig();
        IFeeLibV1 feeLib = IFeeLibV1(config.feeLib);

        FeeConfig memory feeConfig = feeLib.feeConfigs(DST_EID);
        console.log("rewardMillionth:", feeConfig.rewardMillionth);
        console.log("zone1FeeMillionth:", feeConfig.zone1FeeMillionth);
        console.log("zone2FeeMillionth:", feeConfig.zone2FeeMillionth);
        console.log("zone3FeeMillionth:", feeConfig.zone3FeeMillionth);

        bool rewardExceedsFee = false;
        if (feeConfig.rewardMillionth > feeConfig.zone1FeeMillionth) {
            console.log("REWARD VS FEE RATE:  REWARD > ZONE1_FEE");
            rewardExceedsFee = true;
        } else if (feeConfig.rewardMillionth > feeConfig.zone2FeeMillionth) {
            console.log("REWARD VS FEE RATE: REWARD > ZONE2_FEE");
            rewardExceedsFee = true;
        } else if (feeConfig.rewardMillionth > feeConfig.zone3FeeMillionth) {
            console.log("REWARD VS FEE RATE: REWARD > ZONE3_FEE");
            rewardExceedsFee = true;
        } else {
            console.log("REWARD VS FEE RATE:  REWARD <= ALL_FEES");
        }

        // 4. PROFIT CALCULATION
        if (deficitSD > 0 && treasuryFeeSD > 0 && rewardExceedsFee) {
            console.log("\n--- POTENTIAL EXPLOIT SIMULATION ---");

            // Calculate optimal amount
            uint64 optimalAmountSD = deficitSD + 100; // Slightly more than deficit
            uint256 optimalAmountLD = pool._sd2ld(optimalAmountSD);

            // Calculate reward on deficit portion
            uint256 rewardSD = (uint256(deficitSD) * uint256(feeConfig.rewardMillionth)) / 1_000_000;
            uint256 feeSD = (uint256(100) * uint256(feeConfig.zone1FeeMillionth)) / 1_000_000 + 1;

            uint256 netGainSD = rewardSD > feeSD ? rewardSD - feeSD : 0;
            uint256 netGainLD = pool._sd2ld(uint64(netGainSD));

            // Calculate max extraction (capped by treasury fee)
            uint256 maxExtractionSD = treasuryFeeSD < uint64(netGainSD) ? treasuryFeeSD : uint64(netGainSD);
            uint256 maxExtractionLD = pool._sd2ld(uint64(maxExtractionSD));

            console.log("Potential reward in SD:", rewardSD);
            console.log("Fee on excess in SD:", feeSD);
            console.log("Net gain in SD:", netGainSD);
            console.log("Net gain in LD:", netGainLD);
            console.log("Maximum extraction (treasury limited) in SD:", maxExtractionSD);
            console.log("Maximum extraction (treasury limited) in LD:", maxExtractionLD);

            // Gas cost estimate for Arbitrum (conservative)
            uint256 gasPrice = 0.1 gwei;
            uint256 gasUsed = 500000; // Complex transaction
            uint256 gasCostWei = gasPrice * gasUsed;

            console.log("\n--- PROFITABILITY ANALYSIS ---");
            console.log("Estimated gas cost (wei):", gasCostWei);

            // Is it profitable?
            uint256 tokenValueWei = 1 ether; // Assume 1:1 with ETH for simplicity
            uint256 profitWei = maxExtractionLD * tokenValueWei;

            if (profitWei > gasCostWei) {
                console.log("PROFITABILITY:  PROFITABLE");
                console.log("Estimated profit (wei):", profitWei - gasCostWei);
                console.log("Profit ratio:", profitWei / gasCostWei);
            } else {
                console.log("PROFITABILITY:  NOT PROFITABLE");
                console.log("Estimated loss (wei):", gasCostWei - profitWei);
            }

            console.log("\n--- VULNERABILITY STATUS ---");
            console.log("This pool IS VULNERABLE to treasury fee drain attack.");
        } else {
            console.log("\n--- VULNERABILITY STATUS ---");
            if (deficitSD == 0) console.log("Missing condition: No deficit");
            if (treasuryFeeSD == 0) console.log("Missing condition: No treasury fee");
            if (!rewardExceedsFee) console.log("Missing condition: Reward doesn't exceed fees");

            console.log("This pool IS NOT VULNERABLE to treasury fee drain attack.");
        }
    }
}