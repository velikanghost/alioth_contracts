// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/vaults/AliothMultiAssetVault.sol";
import "../src/core/YieldOptimizer.sol";

/**
 * @title DeployMultiAssetVault
 * @notice Script to deploy the Alioth Multi-Asset Vault
 */
contract DeployMultiAssetVault is Script {
    // Network configurations
    struct NetworkConfig {
        address yieldOptimizer;
        address admin;
    }

    // Network configurations
    mapping(string => NetworkConfig) public networkConfigs;

    function setUp() public {
        _setupNetworkConfigs();
    }

    /**
     * @notice Get deployment configuration with proper admin handling
     */
    function getDeploymentConfig(
        string memory networkName
    ) internal view returns (NetworkConfig memory config) {
        config = networkConfigs[networkName];
        require(
            config.yieldOptimizer != address(0),
            "Network config not found"
        );

        // Get the actual deployer address (not DEFAULT_SENDER)
        // In broadcast context, tx.origin is the actual signer
        address deployer = tx.origin;

        // Get admin from environment or use deployer as fallback
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        // Override the admin in config with the proper value
        config.admin = admin;
    }

    /**
     * @notice Default deployment function for Sepolia
     */
    function run() external {
        run("sepolia");
    }

    /**
     * @notice Main deployment function
     * @param networkName The network to deploy on (e.g., "sepolia", "mainnet")
     */
    function run(string memory networkName) public {
        NetworkConfig memory config = getDeploymentConfig(networkName);

        console.log("=== Alioth Multi-Asset Vault Deployment ===");
        console.log("Network:", networkName);
        console.log("YieldOptimizer:", config.yieldOptimizer);
        console.log("Admin:", config.admin);

        vm.startBroadcast();

        // Get the actual broadcaster address (tx.origin in broadcast context)
        address deployer = tx.origin;
        console.log("Deployer (from tx.origin):", deployer);
        console.log("Configured Admin:", config.admin);

        // Deploy the Multi-Asset Vault with the configured admin as owner
        AliothMultiAssetVault vault = new AliothMultiAssetVault(
            config.yieldOptimizer,
            config.admin // Use configured admin
        );

        console.log("Multi-Asset Vault deployed at:", address(vault));

        // Verify the owner is set correctly
        address actualOwner = vault.owner();
        console.log("Actual vault owner:", actualOwner);
        require(
            actualOwner == config.admin,
            "Owner mismatch - deployment failed"
        );

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Multi-Asset Vault:", address(vault));
        console.log("Owner:", config.admin);
        console.log("YieldOptimizer Integration:", config.yieldOptimizer);

        console.log("\n=== Next Steps ===");
        console.log("1. Verify the contract on block explorer");
        console.log("2. Add tokens manually using:");
        console.log(
            string(
                abi.encodePacked(
                    "   cast send ",
                    vm.toString(address(vault)),
                    ' "addToken(address,uint256,uint256)" TOKEN_ADDRESS MIN_DEPOSIT MAX_DEPOSIT --rpc-url https://sepolia.infura.io/v3/c7c5f43ca9bc47afa93181f412d404f5 --account monad'
                )
            )
        );

        // Verification commands
        console.log("\n=== Verification Commands ===");
        console.log("Vault verification:");
        console.log(
            string(
                abi.encodePacked(
                    "forge verify-contract ",
                    vm.toString(address(vault)),
                    " src/vaults/AliothMultiAssetVault.sol:AliothMultiAssetVault --chain-id ",
                    vm.toString(block.chainid),
                    " --constructor-args ",
                    vm.toString(abi.encode(config.yieldOptimizer, config.admin))
                )
            )
        );

        // Log all deployment info instead of saving to file
        console.log("\n=== Deployment Info (Save This) ===");
        console.log("Network:", networkName);
        console.log("Multi-Asset Vault:", address(vault));
        console.log("YieldOptimizer:", config.yieldOptimizer);
        console.log("Admin/Owner:", config.admin);
        console.log("Block Number:", block.number);
        console.log("Chain ID:", block.chainid);
        console.log("Deployment Complete!");
    }

    /**
     * @notice Deploy to localhost/anvil for testing
     */
    function runLocal() external {
        // For local testing, we need to deploy YieldOptimizer first or use existing address
        address yieldOptimizerAddr = vm.envOr(
            "YIELD_OPTIMIZER_ADDRESS",
            address(0)
        );
        require(
            yieldOptimizerAddr != address(0),
            "Set YIELD_OPTIMIZER_ADDRESS env var"
        );

        vm.startBroadcast();

        // Use tx.origin as admin for local testing
        address admin = tx.origin;

        AliothMultiAssetVault vault = new AliothMultiAssetVault(
            yieldOptimizerAddr,
            admin
        );

        console.log("Local Multi-Asset Vault deployed at:", address(vault));
        console.log("Owner:", admin);

        vm.stopBroadcast();
    }

    function _setupNetworkConfigs() internal {
        // Sepolia Testnet Configuration
        networkConfigs["sepolia"] = NetworkConfig({
            yieldOptimizer: vm.envOr("SEPOLIA_YIELD_OPTIMIZER", address(0)),
            admin: address(0) // Will be set dynamically in getDeploymentConfig
        });

        // Ethereum Mainnet Configuration
        networkConfigs["mainnet"] = NetworkConfig({
            yieldOptimizer: vm.envOr("MAINNET_YIELD_OPTIMIZER", address(0)),
            admin: address(0) // Will be set dynamically in getDeploymentConfig
        });

        // Polygon Configuration
        networkConfigs["polygon"] = NetworkConfig({
            yieldOptimizer: vm.envOr("POLYGON_YIELD_OPTIMIZER", address(0)),
            admin: address(0) // Will be set dynamically in getDeploymentConfig
        });

        // Arbitrum Configuration
        networkConfigs["arbitrum"] = NetworkConfig({
            yieldOptimizer: vm.envOr("ARBITRUM_YIELD_OPTIMIZER", address(0)),
            admin: address(0) // Will be set dynamically in getDeploymentConfig
        });
    }

    /**
     * @notice Utility function to get deployment info for integration
     */
    function getNetworkConfig(
        string memory networkName
    ) external view returns (NetworkConfig memory) {
        return networkConfigs[networkName];
    }

    /**
     * @notice Verify deployment by checking vault configuration
     */
    function verifyDeployment(address vaultAddress) external view {
        AliothMultiAssetVault vault = AliothMultiAssetVault(vaultAddress);

        console.log("=== Vault Verification ===");
        console.log("Vault Address:", vaultAddress);
        console.log("YieldOptimizer:", address(vault.yieldOptimizer()));
        console.log("Owner:", vault.owner());
        console.log("Fee Recipient:", vault.feeRecipient());
        console.log("Deposit Fee:", vault.depositFee());
        console.log("Withdrawal Fee:", vault.withdrawalFee());
        console.log("Supported Token Count:", vault.getSupportedTokenCount());

        address[] memory tokens = vault.getSupportedTokens();
        console.log("\nSupported Tokens:");
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("  Token", i, ":", tokens[i]);
            console.log("    Supported:", vault.isTokenSupported(tokens[i]));
        }
    }
}
