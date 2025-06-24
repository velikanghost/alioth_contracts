// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import "../src/core/EnhancedChainlinkFeedManager.sol";
import "../src/core/EnhancedYieldOptimizer.sol";
import "../src/core/CCIPMessenger.sol";

/**
 * @title DeployAIIntegration
 * @notice Deployment script for AI core components only
 * @dev Deploys Enhanced ChainlinkFeedManager, CCIPMessenger, and standalone EnhancedYieldOptimizer
 */
contract DeployAIIntegration is Script {
    // ✅ CHAINLINK CCIP ROUTER ADDRESSES (TESTNET SPECIFIC)
    address constant CCIP_ROUTER_SEPOLIA =
        0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address constant CCIP_ROUTER_ARBITRUM_SEPOLIA =
        0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;
    address constant CCIP_ROUTER_BASE_SEPOLIA =
        0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
    address constant CCIP_ROUTER_AVALANCHE_FUJI =
        0xF694E193200268f9a4868e4Aa017A0118C9a8177;

    // ✅ LINK TOKEN ADDRESSES (TESTNET SPECIFIC)
    address constant LINK_SEPOLIA = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant LINK_ARBITRUM_SEPOLIA =
        0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;
    address constant LINK_BASE_SEPOLIA =
        0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address constant LINK_AVALANCHE_FUJI =
        0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;

    struct DeploymentConfig {
        address ccipRouter;
        address linkToken;
        address admin;
        string networkName;
    }

    struct DeployedContracts {
        EnhancedChainlinkFeedManager enhancedFeedManager;
        CCIPMessenger ccipMessenger;
        EnhancedYieldOptimizer enhancedYieldOptimizer;
    }

    function run() external {
        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig();

        console.log("=== Deploying AI Core Components ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("CCIP Router:", config.ccipRouter);
        console.log("LINK Token:", config.linkToken);

        vm.startBroadcast();

        // Deploy contracts
        DeployedContracts memory contracts = deployContracts(config);

        // Configure contracts
        configureContracts(contracts, config);

        vm.stopBroadcast();

        // Log deployment addresses
        logDeployment(contracts, config);
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
                ccipRouter: CCIP_ROUTER_SEPOLIA,
                linkToken: LINK_SEPOLIA,
                admin: admin,
                networkName: "Sepolia"
            });
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_ARBITRUM_SEPOLIA,
                linkToken: LINK_ARBITRUM_SEPOLIA,
                admin: admin,
                networkName: "Arbitrum Sepolia"
            });
        } else if (chainId == 84532) {
            // Base Sepolia
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_BASE_SEPOLIA,
                linkToken: LINK_BASE_SEPOLIA,
                admin: admin,
                networkName: "Base Sepolia"
            });
        } else if (chainId == 43113) {
            // Avalanche Fuji
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_AVALANCHE_FUJI,
                linkToken: LINK_AVALANCHE_FUJI,
                admin: admin,
                networkName: "Avalanche Fuji"
            });
        } else {
            revert(
                "Unsupported network - only Sepolia, Arbitrum Sepolia, Base Sepolia, and Avalanche Fuji are supported"
            );
        }
    }

    function deployContracts(
        DeploymentConfig memory config
    ) internal returns (DeployedContracts memory contracts) {
        console.log("\n=== Deploying AI Core Contracts ===");

        // Get the actual broadcaster address (tx.origin in broadcast context)
        address deployer = tx.origin;
        console.log("Deployer (from tx.origin):", deployer);
        console.log("Configured Admin:", config.admin);

        // 1. Deploy Enhanced ChainlinkFeedManager
        console.log("1. Deploying EnhancedChainlinkFeedManager...");
        contracts.enhancedFeedManager = new EnhancedChainlinkFeedManager(
            config.admin
        );
        console.log(
            "   EnhancedChainlinkFeedManager deployed at:",
            address(contracts.enhancedFeedManager)
        );

        // 2. Deploy CCIPMessenger
        console.log("2. Deploying CCIPMessenger...");
        contracts.ccipMessenger = new CCIPMessenger(
            config.ccipRouter,
            config.linkToken,
            config.admin // Use admin as fee collector
        );
        console.log(
            "   CCIPMessenger deployed at:",
            address(contracts.ccipMessenger)
        );

        // 3. Deploy standalone EnhancedYieldOptimizer
        console.log("3. Deploying standalone EnhancedYieldOptimizer...");
        contracts.enhancedYieldOptimizer = new EnhancedYieldOptimizer(
            address(contracts.ccipMessenger), // Use CCIPMessenger instead of router
            address(contracts.enhancedFeedManager),
            config.admin
        );
        console.log(
            "   EnhancedYieldOptimizer deployed at:",
            address(contracts.enhancedYieldOptimizer)
        );
    }

    function configureContracts(
        DeployedContracts memory contracts,
        DeploymentConfig memory config
    ) internal {
        console.log("\n=== Configuring Contracts ===");

        // Authorize deployer as AI backend for testing
        contracts.enhancedYieldOptimizer.authorizeAIBackend(config.admin);
        console.log("1. AI Backend authorized:", config.admin);

        // Update rebalance parameters
        contracts.enhancedYieldOptimizer.updateRebalanceParams(
            900, // 15 minutes rebalance interval
            100 // 1% minimum yield improvement
        );
        console.log("2. Rebalance parameters updated");

        console.log("Configuration completed!");
    }

    function logDeployment(
        DeployedContracts memory contracts,
        DeploymentConfig memory config
    ) internal pure {
        console.log("\n=== AI Core Components Deployment Summary ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("");
        console.log("Deployed Contracts:");
        console.log(
            "  EnhancedChainlinkFeedManager:",
            address(contracts.enhancedFeedManager)
        );
        console.log("  CCIPMessenger:", address(contracts.ccipMessenger));
        console.log(
            "  EnhancedYieldOptimizer:",
            address(contracts.enhancedYieldOptimizer)
        );
        console.log("");
        console.log("=== AI Core Deployment Completed Successfully! ===");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Deploy adapters using DeployAdapters.s.sol");
        console.log("2. Deploy vault using DeployVault.s.sol");
        console.log("3. Configure adapters in EnhancedYieldOptimizer");
        console.log("4. Test AI backend integration");
        console.log("5. Configure CCIP cross-chain settings");
        console.log("");
        console.log("IMPORTANT: Save these addresses for other deployments:");
        console.log(
            "export ENHANCED_YIELD_OPTIMIZER=",
            address(contracts.enhancedYieldOptimizer)
        );
        console.log(
            "export ENHANCED_FEED_MANAGER=",
            address(contracts.enhancedFeedManager)
        );
        console.log("export CCIP_MESSENGER=", address(contracts.ccipMessenger));
    }
}
