// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/vaults/AliothVault.sol";
import "../src/interfaces/IAliothYieldOptimizer.sol";

/**
 * @title DeployVault
 * @notice Script to deploy the Alioth Vault
 */
contract DeployVault is Script {
    address constant ALIOTH_YIELD_OPTIMIZER_SEPOLIA =
        0x3499331d4c0d88028a61bf1516246C29C30AFf8E;

    address constant ALIOTH_YIELD_OPTIMIZER_BASE_SEPOLIA =
        0x9F26D100fdB2Ca6810019062B9a3C6c01Afa21e6;

    address constant ALIOTH_YIELD_OPTIMIZER_AVALANCHE_FUJI =
        0x2F05369A361e7F452F5e5393a565D4d1cA88F80A;

    struct NetworkConfig {
        address aliothYieldOptimizer;
        address admin;
        string networkName;
    }

    function setUp() public {}

    /**
     * @notice Get deployment configuration with proper admin handling
     */
    function getDeploymentConfig()
        internal
        view
        returns (NetworkConfig memory config)
    {
        uint256 chainId = block.chainid;

        address deployer = tx.origin;
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        if (chainId == 11155111) {
            config = NetworkConfig({
                aliothYieldOptimizer: ALIOTH_YIELD_OPTIMIZER_SEPOLIA,
                admin: admin,
                networkName: "Sepolia"
            });
        } else if (chainId == 84532) {
            config = NetworkConfig({
                aliothYieldOptimizer: ALIOTH_YIELD_OPTIMIZER_BASE_SEPOLIA,
                admin: admin,
                networkName: "Base Sepolia"
            });
        } else if (chainId == 43113) {
            config = NetworkConfig({
                aliothYieldOptimizer: ALIOTH_YIELD_OPTIMIZER_AVALANCHE_FUJI,
                admin: admin,
                networkName: "Avalanche Fuji"
            });
        } else {
            revert(
                "Unsupported network - only Sepolia, Arbitrum Sepolia, Base Sepolia, and Avalanche Fuji are supported"
            );
        }

        require(
            config.aliothYieldOptimizer != address(0),
            string(
                abi.encodePacked(
                    "AliothYieldOptimizer not configured for ",
                    config.networkName,
                    ". Please update the constant in this script."
                )
            )
        );
    }

    /**
     * @notice Default deployment function for Sepolia
     */
    function run() external {
        run("auto");
    }

    /**
     * @notice Main deployment function
     */
    function run(string memory) public {
        NetworkConfig memory config = getDeploymentConfig();

        console.log("=== Alioth Multi-Asset Vault V2 Deployment ===");
        console.log("Network:", config.networkName);
        console.log("AliothYieldOptimizer:", config.aliothYieldOptimizer);
        console.log("Admin:", config.admin);

        vm.startBroadcast();

        console.log("Configured Admin:", config.admin);

        AliothVault vaultV2 = new AliothVault(
            config.aliothYieldOptimizer,
            config.admin
        );

        console.log("Alioth Vault deployed at:", address(vaultV2));
        console.log(
            "Receipt Token Factory deployed at:",
            address(vaultV2.receiptTokenFactory())
        );

        address actualOwner = vaultV2.owner();
        console.log("Actual vault owner:", actualOwner);
        require(
            actualOwner == config.admin,
            "Owner mismatch - deployment failed"
        );

        // Authorize the vault in the AliothYieldOptimizer
        console.log("\n=== Setting up authorization ===");
        IAliothYieldOptimizer optimizer = IAliothYieldOptimizer(
            config.aliothYieldOptimizer
        );

        try optimizer.authorizeVault(address(vaultV2)) {
            console.log("SUCCESS: Vault authorized in AliothYieldOptimizer");
        } catch {
            console.log(
                "FAILED: Failed to authorize vault - may need to be done manually by admin"
            );
            console.log("   Run this command manually:");
            console.log(
                string(
                    abi.encodePacked(
                        "   cast send ",
                        vm.toString(config.aliothYieldOptimizer),
                        ' "authorizeVault(address)" ',
                        vm.toString(address(vaultV2)),
                        " --account ADMIN_ACCOUNT"
                    )
                )
            );
        }

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Alioth Vault:", address(vaultV2));
        console.log(
            "Receipt Token Factory:",
            address(vaultV2.receiptTokenFactory())
        );
        console.log("Owner:", config.admin);
        console.log(
            "AliothYieldOptimizer Integration:",
            config.aliothYieldOptimizer
        );
    }

    /**
     * @notice Utility function to get network config for integration
     */
    function getNetworkConfig() external view returns (NetworkConfig memory) {
        return getDeploymentConfig();
    }

    /**
     * @notice Verify deployment by checking vault configuration
     */
    function verifyDeployment(address vaultAddress) external view {
        AliothVault vault = AliothVault(vaultAddress);

        console.log("=== Alioth Vault Verification ===");
        console.log("Vault Address:", vaultAddress);
        console.log(
            "Alioth Yield Optimizer:",
            address(vault.aliothYieldOptimizer())
        );
        console.log(
            "Receipt Token Factory:",
            address(vault.receiptTokenFactory())
        );
        console.log("Owner:", vault.owner());
        console.log("Fee Recipient:", vault.feeRecipient());
        console.log("Deposit Fee:", vault.depositFee());
        console.log("Withdrawal Fee:", vault.withdrawalFee());
    }
}
