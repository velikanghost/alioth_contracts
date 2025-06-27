// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import "../src/core/ChainlinkFeedManager.sol";
import "../src/core/AliothYieldOptimizer.sol";
import "../src/core/CCIPMessenger.sol";

/**
 * @title DeployCore
 * @notice Deployment script for core components
 * @dev Deploys ChainlinkFeedManager, CCIPMessenger, AliothYieldOptimizer, and MockV3Aggregators for testing
 */
contract DeployCore is Script {
    // ✅ CHAINLINK CCIP ROUTER ADDRESSES
    address constant CCIP_ROUTER_SEPOLIA =
        0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address constant CCIP_ROUTER_BASE_SEPOLIA =
        0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
    address constant CCIP_ROUTER_AVALANCHE_FUJI =
        0xF694E193200268f9a4868e4Aa017A0118C9a8177;

    // ✅ LINK TOKEN ADDRESSES
    address constant LINK_SEPOLIA = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
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
        ChainlinkFeedManager feedManager;
        CCIPMessenger ccipMessenger;
        AliothYieldOptimizer aliothYieldOptimizer;
    }

    function run() external {
        DeploymentConfig memory config = getDeploymentConfig();

        console.log("=== Deploying AI Core Components ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("CCIP Router:", config.ccipRouter);
        console.log("LINK Token:", config.linkToken);

        vm.startBroadcast();

        DeployedContracts memory contracts = deployContracts(config);

        configureContracts(contracts, config);

        vm.stopBroadcast();

        logDeployment(contracts, config);
    }

    function getDeploymentConfig()
        internal
        view
        returns (DeploymentConfig memory config)
    {
        uint256 chainId = block.chainid;

        address deployer = tx.origin;

        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        if (chainId == 11155111) {
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_SEPOLIA,
                linkToken: LINK_SEPOLIA,
                admin: admin,
                networkName: "Sepolia"
            });
        } else if (chainId == 84532) {
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_BASE_SEPOLIA,
                linkToken: LINK_BASE_SEPOLIA,
                admin: admin,
                networkName: "Base Sepolia"
            });
        } else if (chainId == 43113) {
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

        console.log("Configured Admin:", config.admin);

        console.log("1. Deploying ChainlinkFeedManager...");
        contracts.feedManager = new ChainlinkFeedManager(config.admin);
        console.log(
            "   ChainlinkFeedManager deployed at:",
            address(contracts.feedManager)
        );

        console.log("2. Deploying CCIPMessenger...");
        contracts.ccipMessenger = new CCIPMessenger(
            config.ccipRouter,
            config.linkToken,
            config.admin
        );
        console.log(
            "   CCIPMessenger deployed at:",
            address(contracts.ccipMessenger)
        );

        console.log("3. Deploying standalone AliothYieldOptimizer...");
        contracts.aliothYieldOptimizer = new AliothYieldOptimizer(
            address(contracts.ccipMessenger),
            address(contracts.feedManager),
            config.admin
        );
        console.log(
            "   AliothYieldOptimizer deployed at:",
            address(contracts.aliothYieldOptimizer)
        );
    }

    function configureContracts(
        DeployedContracts memory contracts,
        DeploymentConfig memory config
    ) internal {
        console.log("\n=== Configuring Contracts ===");

        // Authorize deployer as AI backend for testing
        contracts.aliothYieldOptimizer.authorizeAIBackend(config.admin);
        console.log("1. AI Backend authorized:", config.admin);

        // Update rebalance parameters
        contracts.aliothYieldOptimizer.updateRebalanceParams(
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
        console.log("  ChainlinkFeedManager:", address(contracts.feedManager));
        console.log("  CCIPMessenger:", address(contracts.ccipMessenger));
        console.log(
            "  AliothYieldOptimizer:",
            address(contracts.aliothYieldOptimizer)
        );
    }
}
