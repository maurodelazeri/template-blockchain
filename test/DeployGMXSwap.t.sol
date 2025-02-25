// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol"; // For console.log
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// GMX Router interface
interface IGMXRouter {
    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external;
}

// The SimpleGMXSwap contract (simple swap using GMX, WETH in path, ETH as native, with balances)
contract SimpleGMXSwap {
    IGMXRouter public router;
    address public usdc;
    address public weth;

    constructor(
        address _router,
        address _usdc,
        address _weth
    ) {
        router = IGMXRouter(_router);
        usdc = _usdc;
        weth = _weth;
    }

    // Function to deposit USDC into the contract
    function depositUSDC(uint256 _amount) external {
        console.log("Depositing %s USDC into contract", _amount);
        bool success = IERC20(usdc).transferFrom(msg.sender, address(this), _amount);
        require(success, "USDC transfer failed");
        console.log("USDC deposited, contract balance: %s", IERC20(usdc).balanceOf(address(this)));
    }

    function swapOnGMX(
        uint256 _amount
    ) external {
        console.log("Starting swapOnGMX with amount: %s", _amount);
        require(_amount > 0, "Amount must be greater than 0");

        // Get the contract's USDC balance
        uint256 contractBalance = IERC20(usdc).balanceOf(address(this));
        console.log("Contract USDC balance: %s", contractBalance);
        require(contractBalance >= _amount, "Insufficient USDC balance");

        // Approve input token for the router - approve a higher amount to ensure enough allowance
        console.log("Approving USDC for router");
        IERC20(usdc).approve(address(router), 0); // Clear existing allowance first
        bool success = IERC20(usdc).approve(address(router), _amount);
        require(success, "USDC approval failed");
        console.log("USDC approved for router");

        // Set up swap path (USDC -> WETH)
        address[] memory path = new address[](2);
        path[0] = usdc;
        path[1] = weth;
        console.log("Swap path set: USDC -> WETH");

        // GMX has a minimum amount requirement - increase minOut to a reasonable value
        uint256 minOut = 1 * 10**12; // 0.000001 WETH (18 decimals)

        // Perform the swap
        console.log("Performing swap with amountIn: %s, minOut: %s", _amount, minOut);
        try router.swap(path, _amount, minOut, msg.sender) {
            console.log("Swapped On GMX successfully");
        } catch Error(string memory reason) {
            console.log("Swap failed with reason: %s", reason);
            revert(reason);
        } catch {
            console.log("Swap failed with unknown error");
            revert("Unknown swap error");
        }
    }

    receive() external payable {}
}

// Deployment script with test swap, using impersonation on a forked network
contract DeployGMXSwap is Script {
    function run() external {
        // Arbitrum mainnet addresses (verified)
        address router = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064; // GMX Router
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

        // Define sender address
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        if (sender == address(0)) {
            // Default to anvil's first account if no private key is provided
            sender = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }
        console.log("Using sender address: %s", sender);

        // Use a reasonable amount for testing
        uint256 depositAmount = 5000 * 10**6; // 5,000 USDC (6 decimals)

        // STEP 1: Fund the sender with USDC by impersonating a whale
        // This is Binance's hot wallet which has USDC on Arbitrum
        address usdcWhale = 0x7B7B957c284C2C227C980d6E2F804311947b84d0;

        // Check whale's balance before proceeding
        uint256 whaleBalance = IERC20(usdc).balanceOf(usdcWhale);
        console.log("Whale USDC balance: %s", whaleBalance / 10**6);

        if (whaleBalance < depositAmount) {
            console.log("Not enough USDC in whale account. Trying another whale...");
            // Try another whale
            usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
            whaleBalance = IERC20(usdc).balanceOf(usdcWhale);
            console.log("Alternative whale USDC balance: %s", whaleBalance / 10**6);
        }

        require(whaleBalance >= depositAmount, "No whale with enough USDC found");

        // Impersonate the whale to transfer USDC to our sender
        vm.startPrank(usdcWhale);
        IERC20(usdc).transfer(sender, depositAmount);
        vm.stopPrank();

        console.log("Transferred %s USDC from whale to sender", depositAmount / 10**6);

        // STEP 2: Deploy and test the contract
        vm.startBroadcast();

        // Verify we have the USDC
        uint256 senderBalance = IERC20(usdc).balanceOf(sender);
        console.log("Sender USDC balance: %s", senderBalance / 10**6);
        require(senderBalance >= depositAmount, "Sender does not have enough USDC");

        // Deploy the SimpleGMXSwap contract
        SimpleGMXSwap swapContract = new SimpleGMXSwap(
            router,
            usdc,
            weth
        );
        console.log("SimpleGMXSwap deployed at: %s", address(swapContract));

        // Approve the contract to spend USDC
        IERC20(usdc).approve(address(swapContract), depositAmount);
        console.log("Approved SimpleGMXSwap to spend %s USDC", depositAmount / 10**6);

        // Call depositUSDC to transfer USDC to the contract
        swapContract.depositUSDC(depositAmount);
        console.log("USDC deposited to contract");

        // Check contract balance
        uint256 contractBalance = IERC20(usdc).balanceOf(address(swapContract));
        console.log("Contract USDC balance: %s", contractBalance / 10**6);

        // Test swapOnGMX (using the deposited USDC)
        console.log("Testing swapOnGMX with %s USDC to WETH", depositAmount / 10**6);
        swapContract.swapOnGMX(depositAmount);

        // Check WETH balance after swap
        uint256 wethBalance = IERC20(weth).balanceOf(sender);
        console.log("Sender WETH balance after swap: %s", wethBalance / 10**18);

        vm.stopBroadcast();
    }
}