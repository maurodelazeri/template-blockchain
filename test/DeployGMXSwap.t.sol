// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol"; // For console.log
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// GMX Router interface - Updated with the correct interface
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
        IERC20(usdc).transferFrom(msg.sender, address(this), _amount);
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
        IERC20(usdc).approve(address(router), _amount);
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
        } catch {
            console.log("Swap failed with unknown error");
        }
    }

    receive() external payable {}
}

// Helper interface for manipulating tokens in a forge script
interface ITokenManipulator {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

// Deployment script with test swap, including funding
contract DeployGMXSwap is Script {
    function run() external {
        // Arbitrum mainnet addresses (verified)
        address router = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064; // GMX Router
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

        // Known USDC whale on Arbitrum with substantial holdings
        address usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

        // Define sender address
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        if (sender == address(0)) {
            // Default to anvil's first account if no private key is provided
            sender = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }
        console.log("Using sender address: %s", sender);

        // Increase the amount - GMX often has minimum swap requirements
        // 10,000 USDC instead of 1,000 (USDC has 6 decimals)
        uint256 depositAmount = 10000 * 10**6;

        // Fund the sender by impersonating a USDC whale
        vm.startPrank(usdcWhale);
        ITokenManipulator(usdc).transfer(sender, depositAmount);
        vm.stopPrank();
        console.log("Funded sender with %s USDC (6 decimals) from whale", depositAmount / 10**6);

        // Start broadcasting transactions
        vm.startBroadcast();

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

        // Test swapOnGMX (using the deposited USDC)
        console.log("Testing swapOnGMX with %s USDC to WETH", depositAmount / 10**6);

        // Call swapOnGMX
        swapContract.swapOnGMX(depositAmount);

        // Stop broadcasting
        vm.stopBroadcast();
    }
}