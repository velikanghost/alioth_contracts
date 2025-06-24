// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/adapters/CompoundAdapter.sol";
import "../src/core/EnhancedYieldOptimizer.sol";

/**
 * @title DeployAdapters
 * @notice Script to deploy protocol adapters and configure them with EnhancedYieldOptimizer
 * @dev Deploys Aave, Compound, and Yearn adapters based on network availability
 */
contract DeployAdapters is Script {
    // ✅ ENHANCED YIELD OPTIMIZER ADDRESSES (DEPLOYED BY DeployAIIntegration.s.sol)
    // UPDATE THESE ADDRESSES AFTER RUNNING DeployAIIntegration.s.sol

    // Sepolia Testnet
    address constant ENHANCED_YIELD_OPTIMIZER_SEPOLIA =
        0xDeE85d65aaDaff8e10164e05e0a8d2AD871e8db0;

    // Arbitrum Sepolia Testnet
    address constant ENHANCED_YIELD_OPTIMIZER_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000;

    // Base Sepolia Testnet
    address constant ENHANCED_YIELD_OPTIMIZER_BASE_SEPOLIA =
        0x0000000000000000000000000000000000000000;

    // Avalanche Fuji Testnet
    address constant ENHANCED_YIELD_OPTIMIZER_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000;

    // 🏦 AAVE V3 POOL ADDRESSES (TESTNET SPECIFIC)
    address constant AAVE_POOL_SEPOLIA =
        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant AAVE_POOL_ARBITRUM_SEPOLIA =
        0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff;
    address constant AAVE_POOL_BASE_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Not available

    // 🏛️ COMPOUND PROTOCOL ADDRESSES (TESTNET SPECIFIC)
    // Note: Compound V3 is not widely available on testnets - using mock addresses
    address constant COMPOUND_COMPTROLLER_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant COMPOUND_COMPTROLLER_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant COMPOUND_COMPTROLLER_BASE_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant COMPOUND_COMPTROLLER_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Mock address

    // 🌾 YEARN PROTOCOL ADDRESSES (TESTNET SPECIFIC)
    // Note: Yearn is not available on testnets - using mock addresses
    address constant YEARN_REGISTRY_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant YEARN_REGISTRY_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant YEARN_REGISTRY_BASE_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant YEARN_REGISTRY_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Mock address

    struct DeploymentConfig {
        address enhancedYieldOptimizer;
        address aavePool;
        address compoundComptroller;
        address yearnRegistry;
        address admin;
        string networkName;
    }

    struct DeployedAdapters {
        AaveAdapter aaveAdapter;
        CompoundAdapter compoundAdapter;
    }

    function run() external {
        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig();

        console.log("=== Deploying Protocol Adapters ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("EnhancedYieldOptimizer:", config.enhancedYieldOptimizer);

        vm.startBroadcast();

        // Deploy adapters
        DeployedAdapters memory adapters = deployAdapters(config);

        vm.stopBroadcast();

        // Configure adapters with EnhancedYieldOptimizer
        configureAdapters(adapters, config);

        // Log deployment addresses
        logDeployment(adapters, config);
    }

    function getDeploymentConfig()
        internal
        view
        returns (DeploymentConfig memory config)
    {
        uint256 chainId = block.chainid;

        // Get the actual deployer address (not DEFAULT_SENDER)
        // In broadcast context, tx.origin is the actual signer
        address deployer = tx.origin;

        // Get admin from environment or use deployer as fallback
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        if (chainId == 11155111) {
            // Ethereum Sepolia
            config = DeploymentConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_SEPOLIA,
                aavePool: AAVE_POOL_SEPOLIA,
                compoundComptroller: COMPOUND_COMPTROLLER_SEPOLIA,
                yearnRegistry: YEARN_REGISTRY_SEPOLIA,
                admin: admin,
                networkName: "Sepolia"
            });
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            config = DeploymentConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_ARBITRUM_SEPOLIA,
                aavePool: AAVE_POOL_ARBITRUM_SEPOLIA,
                compoundComptroller: COMPOUND_COMPTROLLER_ARBITRUM_SEPOLIA,
                yearnRegistry: YEARN_REGISTRY_ARBITRUM_SEPOLIA,
                admin: admin,
                networkName: "Arbitrum Sepolia"
            });
        } else if (chainId == 84532) {
            // Base Sepolia
            config = DeploymentConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_BASE_SEPOLIA,
                aavePool: AAVE_POOL_BASE_SEPOLIA, // Not available
                compoundComptroller: COMPOUND_COMPTROLLER_BASE_SEPOLIA,
                yearnRegistry: YEARN_REGISTRY_BASE_SEPOLIA,
                admin: admin,
                networkName: "Base Sepolia"
            });
        } else if (chainId == 43113) {
            // Avalanche Fuji
            config = DeploymentConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_AVALANCHE_FUJI,
                aavePool: address(0), // Not available
                compoundComptroller: COMPOUND_COMPTROLLER_AVALANCHE_FUJI,
                yearnRegistry: YEARN_REGISTRY_AVALANCHE_FUJI,
                admin: admin,
                networkName: "Avalanche Fuji"
            });
        } else {
            revert(
                "Unsupported network - only Sepolia, Arbitrum Sepolia, Base Sepolia, and Avalanche Fuji are supported"
            );
        }

        require(
            config.enhancedYieldOptimizer != address(0),
            string(
                abi.encodePacked(
                    "EnhancedYieldOptimizer not configured for ",
                    config.networkName,
                    ". Please update the constant in this script."
                )
            )
        );
    }

    function deployAdapters(
        DeploymentConfig memory config
    ) internal returns (DeployedAdapters memory adapters) {
        console.log("\n=== Deploying Protocol Adapters ===");

        // Get the actual broadcaster address (tx.origin in broadcast context)
        address deployer = tx.origin;
        console.log("Deployer (from tx.origin):", deployer);
        console.log("Configured Admin:", config.admin);

        // 1. Deploy Aave Adapter (if available on network)
        if (config.aavePool != address(0)) {
            console.log("1. Deploying AaveAdapter...");
            adapters.aaveAdapter = new AaveAdapter(
                config.aavePool,
                config.admin
            );
            console.log(
                "   AaveAdapter deployed at:",
                address(adapters.aaveAdapter)
            );
        } else {
            console.log(
                "1. Skipping AaveAdapter - not available on this network"
            );
        }

        // 2. Skip CompoundAdapter - not available on testnets
        console.log("2. Skipping CompoundAdapter - not available on testnets");

        // 3. Skip YearnAdapter - not available on testnets
        console.log("3. Skipping YearnAdapter - not available on testnets");

        console.log("Adapter deployment completed!");
    }

    function configureAdapters(
        DeployedAdapters memory adapters,
        DeploymentConfig memory config
    ) internal pure {
        console.log(
            "\n=== Configuring Adapters with EnhancedYieldOptimizer ==="
        );

        // Note: This requires admin privileges on EnhancedYieldOptimizer
        // The admin needs to call these functions manually or grant deployer admin role

        if (address(adapters.aaveAdapter) != address(0)) {
            console.log("Configuration required for AaveAdapter:");
            console.log("Run this command with admin wallet:");
            console.log(
                string(
                    abi.encodePacked(
                        "cast send ",
                        vm.toString(config.enhancedYieldOptimizer),
                        ' "addProtocol(address)" ',
                        vm.toString(address(adapters.aaveAdapter)),
                        " --rpc-url RPC_URL --account ADMIN_ACCOUNT"
                    )
                )
            );
        }

        console.log(
            "\nIMPORTANT: Adapter configuration requires manual admin actions!"
        );
        console.log(
            "See the commands above to add adapters to EnhancedYieldOptimizer."
        );
    }

    function logDeployment(
        DeployedAdapters memory adapters,
        DeploymentConfig memory config
    ) internal pure {
        console.log("\n=== Protocol Adapters Deployment Summary ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("EnhancedYieldOptimizer:", config.enhancedYieldOptimizer);
        console.log("");
        console.log("Deployed Adapters:");

        if (address(adapters.aaveAdapter) != address(0)) {
            console.log("  AaveAdapter:", address(adapters.aaveAdapter));
        } else {
            console.log(
                "  AaveAdapter: Not deployed (unavailable on this network)"
            );
        }

        console.log(
            "  CompoundAdapter: Not deployed (unavailable on testnets)"
        );
        console.log("  YearnAdapter: Not deployed (unavailable on testnets)");
        console.log("");
        console.log("=== Adapter Deployment Completed Successfully! ===");
        console.log("");
        console.log("Next Steps:");
        console.log(
            "1. Configure adapters with EnhancedYieldOptimizer (see commands above)"
        );
        console.log("2. Test adapter functionality");
        console.log("3. Monitor adapter performance");
        console.log("4. Set up yield optimization parameters");
        console.log("");
        console.log("IMPORTANT: Save these addresses for configuration:");
        if (address(adapters.aaveAdapter) != address(0)) {
            console.log("export AAVE_ADAPTER=", address(adapters.aaveAdapter));
        }
    }

    /**
     * @notice Deploy to localhost/anvil for testing
     */
    function runLocal() external {
        // For local testing, use environment variables
        address enhancedYieldOptimizerAddr = vm.envOr(
            "ENHANCED_YIELD_OPTIMIZER_ADDRESS",
            address(0)
        );
        require(
            enhancedYieldOptimizerAddr != address(0),
            "Set ENHANCED_YIELD_OPTIMIZER_ADDRESS env var for local testing"
        );

        vm.startBroadcast();

        // Use tx.origin as admin for local testing
        address admin = tx.origin;

        // Deploy mock Aave adapter for local testing
        AaveAdapter aaveAdapter = new AaveAdapter(address(0x1), admin);

        console.log("Local AaveAdapter deployed at:", address(aaveAdapter));
        console.log("Admin:", admin);
        console.log("EnhancedYieldOptimizer:", enhancedYieldOptimizerAddr);

        vm.stopBroadcast();
    }

    /**
     * @notice Verify adapter deployment
     */
    function verifyDeployment(address aaveAdapterAddress) external view {
        if (aaveAdapterAddress != address(0)) {
            AaveAdapter adapter = AaveAdapter(aaveAdapterAddress);

            console.log("=== Aave Adapter Verification ===");
            console.log("Adapter Address:", aaveAdapterAddress);
            console.log("Protocol Name:", adapter.protocolName());
            console.log("Aave Pool:", address(adapter.aavePool()));
        }
    }
}
