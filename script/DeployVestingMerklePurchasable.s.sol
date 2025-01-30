// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TokenVestingMerklePurchasable} from "../src/TokenVestingMerklePurchasable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeploymentScript is Script {
    address public multiSigAddress;
    address public tokenAddress;
    address public vestingAddress;

    string public tokenName;
    string public tokenSymbol;

    string public vestingName;
    string public vestingSymbol;
    bytes32 public merkleRoot;
    uint256 public vTokenCost;

    uint256 public deployerPrivateKey;

    // Initialize in constructor
    constructor() {
        multiSigAddress = vm.envAddress("MULTISIG_ADDRESS");
        tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        vestingAddress = vm.envAddress("VESTING_ADDRESS");

        tokenName = vm.envString("TOKEN_NAME");
        tokenSymbol = vm.envString("TOKEN_SYMBOL");

        vestingName = vm.envString("VESTING_NAME");
        vestingSymbol = vm.envString("VESTING_SYMBOL");
        merkleRoot = vm.envBytes32("MERKLE_ROOT");
        vTokenCost = vm.envUint("VTOKEN_COST");

        deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOYER_PROD");
    }
}

// Contract for deploying the vesting contract
contract DeployDAOTokenVesting is DeploymentScript {
    error VestingDeploymentFailed();

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: %s", deployerAddress);
        console.log("DAO Token address: %s", tokenAddress);
        console.log("MultiSig address: %s", multiSigAddress);

        require(tokenAddress != address(0), "Invalid token address");
        require(multiSigAddress != address(0), "Invalid multiSig address");
        require(bytes(vestingName).length > 0, "Invalid vesting name");
        require(bytes(vestingSymbol).length > 0, "Invalid vesting symbol");

        IERC20Metadata token = IERC20Metadata(tokenAddress);
        require(address(token) != address(0), "Invalid token address");

        TokenVestingMerklePurchasable tokenVesting = new TokenVestingMerklePurchasable(
                token,
                vestingName,
                vestingSymbol,
                payable(multiSigAddress),
                multiSigAddress,
                vTokenCost,
                merkleRoot
            );

        if (address(tokenVesting) == address(0)) {
            revert VestingDeploymentFailed();
        }

        console.log(
            "TokenVesting deployed successfully at: %s",
            address(tokenVesting)
        );

        vm.stopBroadcast();
    }
}

// Contract for transferring vesting control to multisig
contract TransferVestingToDAOMultisig is DeploymentScript {
    error AdminTransferFailed();

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: %s", deployerAddress);
        console.log("Vesting address: %s", vestingAddress);
        console.log("MultiSig address: %s", multiSigAddress);

        //check vesting address is not 0
        require(vestingAddress != address(0), "Invalid vesting address");
        require(multiSigAddress != address(0), "Invalid multisig address");

        TokenVestingMerklePurchasable tokenVesting = TokenVestingMerklePurchasable(
                vestingAddress
            );

        // Store the initial admin
        address initialAdmin = tokenVesting.owner();

        tokenVesting.beginDefaultAdminTransfer(multiSigAddress);

        // Verify the transfer was initiated
        (address pendingAdmin, ) = tokenVesting.pendingDefaultAdmin();
        if (pendingAdmin != multiSigAddress) {
            revert AdminTransferFailed();
        }

        console.log("Admin transfer initiated successfully");
        console.log("Initial admin: %s", initialAdmin);
        console.log("Pending admin: %s", pendingAdmin);

        vm.stopBroadcast();
    }
}
