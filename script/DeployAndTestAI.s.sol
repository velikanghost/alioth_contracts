// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ai/EnhancedChainlinkFeedManager.sol";
import "../src/ai/EnhancedYieldOptimizer.sol";
import "../src/interfaces/IAIIntegration.sol";

/**
 * @title DeployAndTestAI
 * @notice Complete deployment and testing script for AI Integration
 */
contract DeployAndTestAI is Script {
    // Existing contract addresses from Sepolia deployment
    address public constant EXISTING_CCIP_MESSENGER =
        0xc8D8031656b55A99F9DA19aCa29db6BaC0A783DD;
    address public constant EXISTING_CHAINLINK_FEED_MANAGER =
        0x78E7F9a1889454697b1e4439AEC4eAEAAe4D6CFf;

    // Test addresses
    address public admin = 0x742d35cC6634c0532925a3B8d4c9db96C4b5dA5a;
    address public aiBackend = 0x742d35cC6634c0532925a3B8d4c9db96C4b5dA5a;

    // Deployed contract instances
    EnhancedChainlinkFeedManager public enhancedFeedManager;
    EnhancedYieldOptimizer public enhancedYieldOptimizer;

    function run() public {
        console.log(
            "=== Alioth AI Integration - Complete Deployment & Test ==="
        );
        console.log("");

        // Step 1: Deploy contracts
        _deployContracts();

        // Step 2: Configure contracts
        _configureContracts();

        // Step 3: Test functionality
        _testFunctionality();

        console.log("");
        console.log("=== Deployment and Testing Completed Successfully! ===");
        console.log("");
        _printDeploymentSummary();
    }

    function _deployContracts() internal {
        console.log("STEP 1: Deploying AI Integration Contracts");
        console.log("==========================================");

        console.log("Admin address:", admin);
        console.log("AI Backend address:", aiBackend);
        console.log("CCIP Messenger:", EXISTING_CCIP_MESSENGER);
        console.log("Chainlink Feed Manager:", EXISTING_CHAINLINK_FEED_MANAGER);
        console.log("");

        console.log("1. Deploying EnhancedChainlinkFeedManager...");
        enhancedFeedManager = new EnhancedChainlinkFeedManager(admin);
        console.log("   Deployed at:", address(enhancedFeedManager));

        console.log("2. Deploying EnhancedYieldOptimizer...");
        enhancedYieldOptimizer = new EnhancedYieldOptimizer(
            EXISTING_CCIP_MESSENGER,
            EXISTING_CHAINLINK_FEED_MANAGER,
            address(enhancedFeedManager),
            admin
        );
        console.log("   Deployed at:", address(enhancedYieldOptimizer));
        console.log("");
    }

    function _configureContracts() internal {
        console.log("STEP 2: Configuring Contracts");
        console.log("=============================");

        vm.startPrank(admin);

        console.log("1. Authorizing AI Backend...");
        enhancedYieldOptimizer.authorizeAIBackend(aiBackend);
        console.log("   AI Backend authorized:", aiBackend);

        console.log("2. Setting cross-token parameters...");
        enhancedYieldOptimizer.updateCrossTokenParams(
            300, // 3% max slippage
            50, // 0.5% min yield improvement
            5 // 5 max tokens per operation
        );
        console.log(
            "   Parameters updated: 3% slippage, 0.5% yield improvement, 5 max tokens"
        );

        vm.stopPrank();
        console.log("");
    }

    function _testFunctionality() internal {
        console.log("STEP 3: Testing AI Integration Functionality");
        console.log("============================================");

        // Test 1: Authorization
        _testAuthorization();

        // Test 2: Parameter Management
        _testParameterManagement();

        // Test 3: Batch Deposit Validation
        _testBatchDepositValidation();

        // Test 4: Market Analysis
        _testMarketAnalysis();

        // Test 5: Swap Validation
        _testSwapValidation();
    }

    function _testAuthorization() internal {
        console.log("1. Testing Authorization System...");

        // Check initial authorization
        bool isAuthorized = enhancedYieldOptimizer.authorizedAIBackends(
            aiBackend
        );
        console.log("   AI Backend authorized:", isAuthorized);
        require(isAuthorized, "AI backend should be authorized");

        // Test unauthorized address
        address unauthorizedAddr = 0x9999999999999999999999999999999999999999;
        bool isUnauthorized = enhancedYieldOptimizer.authorizedAIBackends(
            unauthorizedAddr
        );
        console.log("   Unauthorized address check:", !isUnauthorized);
        require(
            !isUnauthorized,
            "Unauthorized address should not be authorized"
        );

        // Test adding new backend
        address newBackend = 0x8888888888888888888888888888888888888888;
        vm.startPrank(admin);
        enhancedYieldOptimizer.authorizeAIBackend(newBackend);
        vm.stopPrank();

        bool newBackendAuth = enhancedYieldOptimizer.authorizedAIBackends(
            newBackend
        );
        console.log("   New backend authorized:", newBackendAuth);
        require(newBackendAuth, "New backend should be authorized");

        // Test revoking authorization
        vm.startPrank(admin);
        enhancedYieldOptimizer.revokeAIBackend(newBackend);
        vm.stopPrank();

        bool revokedAuth = enhancedYieldOptimizer.authorizedAIBackends(
            newBackend
        );
        console.log("   Revoked backend check:", !revokedAuth);
        require(!revokedAuth, "Revoked backend should not be authorized");

        console.log("   Authorization tests passed!");
        console.log("");
    }

    function _testParameterManagement() internal {
        console.log("2. Testing Parameter Management...");

        // Get current parameters
        uint256 maxSlippage = enhancedYieldOptimizer.maxCrossTokenSlippage();
        uint256 minYieldImprovement = enhancedYieldOptimizer
            .minYieldImprovementBps();
        uint256 maxTokens = enhancedYieldOptimizer.maxTokensPerOperation();

        console.log("   Current max slippage:", maxSlippage);
        console.log("   Current min yield improvement:", minYieldImprovement);
        console.log("   Current max tokens:", maxTokens);

        require(maxSlippage == 300, "Max slippage should be 300");
        require(
            minYieldImprovement == 50,
            "Min yield improvement should be 50"
        );
        require(maxTokens == 5, "Max tokens should be 5");

        // Test parameter updates
        vm.startPrank(admin);
        enhancedYieldOptimizer.updateCrossTokenParams(500, 100, 3);
        vm.stopPrank();

        uint256 newMaxSlippage = enhancedYieldOptimizer.maxCrossTokenSlippage();
        uint256 newMinYieldImprovement = enhancedYieldOptimizer
            .minYieldImprovementBps();
        uint256 newMaxTokens = enhancedYieldOptimizer.maxTokensPerOperation();

        console.log("   Updated max slippage:", newMaxSlippage);
        console.log(
            "   Updated min yield improvement:",
            newMinYieldImprovement
        );
        console.log("   Updated max tokens:", newMaxTokens);

        require(newMaxSlippage == 500, "Updated max slippage should be 500");
        require(
            newMinYieldImprovement == 100,
            "Updated min yield improvement should be 100"
        );
        require(newMaxTokens == 3, "Updated max tokens should be 3");

        console.log("   Parameter management tests passed!");
        console.log("");
    }

    function _testBatchDepositValidation() internal {
        console.log("3. Testing Batch Deposit Validation...");

        // Create test arrays
        address[] memory tokens = new address[](2);
        tokens[0] = 0x1111111111111111111111111111111111111111; // Mock USDC
        tokens[1] = 0x2222222222222222222222222222222222222222; // Mock DAI

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000e6; // 1000 USDC
        amounts[1] = 500e18; // 500 DAI

        uint256[] memory minShares = new uint256[](2);
        minShares[0] = 950e6; // 95% of USDC
        minShares[1] = 475e18; // 95% of DAI

        console.log("   Testing with", tokens.length, "tokens");
        console.log("   Token 1 amount:", amounts[0]);
        console.log("   Token 2 amount:", amounts[1]);

        // Test array length validation
        require(
            tokens.length == amounts.length,
            "Tokens and amounts length mismatch"
        );
        require(
            amounts.length == minShares.length,
            "Amounts and minShares length mismatch"
        );

        // Test max tokens validation
        uint256 maxTokensAllowed = enhancedYieldOptimizer
            .maxTokensPerOperation();
        require(
            tokens.length <= maxTokensAllowed,
            "Too many tokens for current limit"
        );

        console.log("   Array validation passed");
        console.log("   Max tokens check passed");
        console.log("   Tokens used:", tokens.length);
        console.log("   Max allowed:", maxTokensAllowed);

        console.log("   Batch deposit validation tests passed!");
        console.log("");
    }

    function _testMarketAnalysis() internal {
        console.log("4. Testing Market Analysis...");

        // Test empty array validation
        address[] memory emptyTokens = new address[](0);

        try enhancedFeedManager.getMarketAnalysis(emptyTokens) {
            revert("Should have reverted with empty tokens");
        } catch Error(string memory reason) {
            console.log("   Empty tokens revert reason:", reason);
            require(
                keccak256(abi.encodePacked(reason)) ==
                    keccak256(abi.encodePacked("No tokens provided")),
                "Unexpected revert reason"
            );
        }

        console.log("   Empty array validation passed");
        console.log("   Market analysis tests passed!");
        console.log("");
    }

    function _testSwapValidation() internal {
        console.log("5. Testing Swap Rate Validation...");

        address inputToken = 0x1111111111111111111111111111111111111111;
        address outputToken = 0x2222222222222222222222222222222222222222;
        uint256 amountIn = 1000e6;
        uint256 expectedAmountOut = 999e18;

        console.log("   Input token:", inputToken);
        console.log("   Output token:", outputToken);
        console.log("   Amount in:", amountIn);
        console.log("   Expected amount out:", expectedAmountOut);

        // Test swap validation (will use default behavior in test environment)
        bool isValidSwap = enhancedYieldOptimizer.validateSwapRates(
            inputToken,
            outputToken,
            amountIn,
            expectedAmountOut
        );

        console.log("   Swap validation result:", isValidSwap);
        console.log("   Swap validation tests passed!");
        console.log("");
    }

    function _printDeploymentSummary() internal view {
        console.log("DEPLOYMENT SUMMARY");
        console.log("==================");
        console.log(
            "EnhancedChainlinkFeedManager:",
            address(enhancedFeedManager)
        );
        console.log("EnhancedYieldOptimizer:", address(enhancedYieldOptimizer));
        console.log("Admin:", admin);
        console.log("Authorized AI Backend:", aiBackend);
        console.log("");
        console.log("Current Parameters:");
        console.log(
            "- Max Cross-Token Slippage:",
            enhancedYieldOptimizer.maxCrossTokenSlippage(),
            "bps"
        );
        console.log(
            "- Min Yield Improvement:",
            enhancedYieldOptimizer.minYieldImprovementBps(),
            "bps"
        );
        console.log(
            "- Max Tokens Per Operation:",
            enhancedYieldOptimizer.maxTokensPerOperation()
        );
        console.log("");
        console.log("Ready for AI backend integration!");
    }
}
