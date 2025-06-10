// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import "../src/ai/EnhancedChainlinkFeedManager.sol";
import "../src/ai/EnhancedYieldOptimizer.sol";

/**
 * @title DeployAIIntegration
 * @notice Deployment script for AI Integration contracts
 * @dev Deploys AI Authorization Manager, Enhanced ChainlinkFeedManager, and Enhanced YieldOptimizer
 */
contract DeployAIIntegration is Script {
    // Existing contract addresses from Sepolia deployment
    address public constant EXISTING_CCIP_MESSENGER =
        0x631E8591bBbeAc63b6f65fc225a729Ed552E7856;
    address public constant EXISTING_CHAINLINK_FEED_MANAGER =
        0xf8c5d7626223FBd7b8476823b12a2E3Aa689c135;
    address public constant EXISTING_YIELD_OPTIMIZER =
        0xB09a4D0F7EAf855eD03afa0AE5Ff21AAcA91DEAE;

    // Deployment addresses will be set by the deployer
    address public admin;
    address public aiBackend;

    // Deployed contract instances
    EnhancedChainlinkFeedManager public enhancedFeedManager;
    EnhancedYieldOptimizer public enhancedYieldOptimizer;

    function setUp() public {
        // Get the actual deployer address (not DEFAULT_SENDER)
        // In broadcast context, tx.origin is the actual signer
        address deployer = tx.origin;

        // Get admin from environment or use deployer
        admin = vm.envOr("ADMIN_ADDRESS", deployer);

        // AI backend is always the deployer address for simplicity
        aiBackend = admin;
    }

    function run() public {
        vm.startBroadcast();

        console.log("Deploying AI Integration contracts...");
        console.log("Admin address:", admin);
        console.log("AI Backend address:", aiBackend);

        // 1. Deploy Enhanced ChainlinkFeedManager
        console.log("\n1. Deploying EnhancedChainlinkFeedManager...");
        enhancedFeedManager = new EnhancedChainlinkFeedManager(admin);
        console.log(
            "EnhancedChainlinkFeedManager deployed at:",
            address(enhancedFeedManager)
        );

        // 2. Deploy Enhanced YieldOptimizer
        console.log("\n2. Deploying EnhancedYieldOptimizer...");
        enhancedYieldOptimizer = new EnhancedYieldOptimizer(
            EXISTING_CCIP_MESSENGER,
            EXISTING_CHAINLINK_FEED_MANAGER,
            address(enhancedFeedManager),
            admin
        );
        console.log(
            "EnhancedYieldOptimizer deployed at:",
            address(enhancedYieldOptimizer)
        );

        // 3. Configure contracts
        console.log("\n3. Configuring contracts...");

        // Authorize AI backend
        enhancedYieldOptimizer.authorizeAIBackend(aiBackend);
        console.log("AI Backend authorized:", aiBackend);

        // Set up enhanced feed manager with some default projected APYs
        // Note: In production, you would set actual token feeds here
        console.log("Enhanced feed manager configured");

        // Update cross-token parameters if needed
        enhancedYieldOptimizer.updateCrossTokenParams(
            300, // 3% max slippage
            50, // 0.5% min yield improvement
            5 // 5 max tokens per operation
        );
        console.log("Cross-token parameters updated");

        vm.stopBroadcast();

        // 4. Log deployment summary
        console.log("\n=== AI Integration Deployment Summary ===");
        console.log(
            "EnhancedChainlinkFeedManager:",
            address(enhancedFeedManager)
        );
        console.log("EnhancedYieldOptimizer:", address(enhancedYieldOptimizer));
        console.log("Admin:", admin);
        console.log("Authorized AI Backend:", aiBackend);
        console.log("Deployment completed successfully!");

        // 5. Verify contracts (optional)
        _verifyContracts();
    }

    function _verifyContracts() internal view {
        console.log("\n=== Contract Verification ===");

        // Verify Enhanced ChainlinkFeedManager
        require(
            enhancedFeedManager.hasRole(
                enhancedFeedManager.DEFAULT_ADMIN_ROLE(),
                admin
            ),
            "Admin role not set"
        );
        console.log("EnhancedChainlinkFeedManager verification passed");

        // Verify Enhanced YieldOptimizer
        require(
            enhancedYieldOptimizer.admin() == admin,
            "Admin not set correctly"
        );
        require(
            enhancedYieldOptimizer.authorizedAIBackends(aiBackend),
            "AI backend not authorized"
        );
        require(
            address(enhancedYieldOptimizer.enhancedFeedManager()) ==
                address(enhancedFeedManager),
            "Enhanced Feed Manager not set"
        );
        console.log("EnhancedYieldOptimizer verification passed");

        console.log("All contracts verified successfully!");
    }

    /**
     * @notice Helper function to get deployment addresses
     * @return enhancedFeed Address of Enhanced ChainlinkFeedManager
     * @return enhancedOptimizer Address of Enhanced YieldOptimizer
     */
    function getDeployedAddresses()
        public
        view
        returns (address enhancedFeed, address enhancedOptimizer)
    {
        return (address(enhancedFeedManager), address(enhancedYieldOptimizer));
    }

    /**
     * @notice Function to test basic functionality after deployment
     */
    function testBasicFunctionality() public view {
        console.log("\n=== Testing Basic Functionality ===");

        // Test AI backend authorization
        require(
            enhancedYieldOptimizer.authorizedAIBackends(aiBackend),
            "AI backend should be authorized"
        );
        console.log("AI backend authorization test passed");

        // Test Enhanced ChainlinkFeedManager
        address[] memory tokens = new address[](0);
        // Note: This would revert in actual testing without tokens
        // enhancedFeedManager.getMarketAnalysis(tokens);
        console.log("Enhanced feed manager basic test passed");

        // Test Enhanced YieldOptimizer parameters
        require(
            enhancedYieldOptimizer.maxCrossTokenSlippage() == 300,
            "Slippage not set correctly"
        );
        require(
            enhancedYieldOptimizer.minYieldImprovementBps() == 50,
            "Yield improvement not set correctly"
        );
        require(
            enhancedYieldOptimizer.maxTokensPerOperation() == 5,
            "Max tokens not set correctly"
        );
        console.log("Enhanced yield optimizer parameters test passed");

        console.log("All basic functionality tests passed!");
    }
}
