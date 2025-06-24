// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/vaults/AliothVault.sol";
import "../src/interfaces/IEnhancedYieldOptimizer.sol";

/**
 * @title DeployVault
 * @notice Script to deploy the Alioth Multi-Asset Vault V2 with Receipt Tokens
 * @dev Uses EnhancedYieldOptimizer instead of original YieldOptimizer
 */
contract DeployVault is Script {
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

    // Network configurations
    struct NetworkConfig {
        address enhancedYieldOptimizer;
        address admin;
        string networkName;
    }

    function setUp() public {
        // No setup needed - configurations are handled in getDeploymentConfig()
    }

    /**
     * @notice Get deployment configuration with proper admin handling
     */
    function getDeploymentConfig()
        internal
        view
        returns (NetworkConfig memory config)
    {
        uint256 chainId = block.chainid;

        // Get the actual deployer address (not DEFAULT_SENDER)
        // In broadcast context, tx.origin is the actual signer
        address deployer = tx.origin;

        // Get admin from environment or use deployer as fallback
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        if (chainId == 11155111) {
            // Ethereum Sepolia
            config = NetworkConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_SEPOLIA,
                admin: admin,
                networkName: "Sepolia"
            });
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            config = NetworkConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_ARBITRUM_SEPOLIA,
                admin: admin,
                networkName: "Arbitrum Sepolia"
            });
        } else if (chainId == 84532) {
            // Base Sepolia
            config = NetworkConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_BASE_SEPOLIA,
                admin: admin,
                networkName: "Base Sepolia"
            });
        } else if (chainId == 43113) {
            // Avalanche Fuji
            config = NetworkConfig({
                enhancedYieldOptimizer: ENHANCED_YIELD_OPTIMIZER_AVALANCHE_FUJI,
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

    /**
     * @notice Default deployment function for Sepolia
     */
    function run() external {
        run("auto"); // Auto-detect network
    }

    /**
     * @notice Main deployment function
     * @param networkName The network to deploy on (e.g., "sepolia", "arbitrum") or "auto" for auto-detection
     */
    function run(string memory networkName) public {
        NetworkConfig memory config = getDeploymentConfig();

        console.log("=== Alioth Multi-Asset Vault V2 Deployment ===");
        console.log("Network:", config.networkName);
        console.log("EnhancedYieldOptimizer:", config.enhancedYieldOptimizer);
        console.log("Admin:", config.admin);

        vm.startBroadcast();

        // Get the actual broadcaster address (tx.origin in broadcast context)
        address deployer = tx.origin;
        console.log("Deployer (from tx.origin):", deployer);
        console.log("Configured Admin:", config.admin);

        // Deploy the Multi-Asset Vault V2 with the configured admin as owner
        AliothVault vaultV2 = new AliothVault(
            config.enhancedYieldOptimizer,
            config.admin // Use configured admin
        );

        console.log("Multi-Asset Vault V2 deployed at:", address(vaultV2));
        console.log(
            "Receipt Token Factory deployed at:",
            address(vaultV2.receiptTokenFactory())
        );

        // Verify the owner is set correctly
        address actualOwner = vaultV2.owner();
        console.log("Actual vault owner:", actualOwner);
        require(
            actualOwner == config.admin,
            "Owner mismatch - deployment failed"
        );

        // Authorize the vault in the EnhancedYieldOptimizer
        console.log("\n=== Setting up authorization ===");
        IEnhancedYieldOptimizer optimizer = IEnhancedYieldOptimizer(
            config.enhancedYieldOptimizer
        );

        try optimizer.authorizeVault(address(vaultV2)) {
            console.log("SUCCESS: Vault authorized in EnhancedYieldOptimizer");
        } catch {
            console.log(
                "FAILED: Failed to authorize vault - may need to be done manually by admin"
            );
            console.log("   Run this command manually:");
            console.log(
                string(
                    abi.encodePacked(
                        "   cast send ",
                        vm.toString(config.enhancedYieldOptimizer),
                        ' "authorizeVault(address)" ',
                        vm.toString(address(vaultV2)),
                        " --account ADMIN_ACCOUNT"
                    )
                )
            );
        }

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Multi-Asset Vault V2:", address(vaultV2));
        console.log(
            "Receipt Token Factory:",
            address(vaultV2.receiptTokenFactory())
        );
        console.log("Owner:", config.admin);
        console.log(
            "EnhancedYieldOptimizer Integration:",
            config.enhancedYieldOptimizer
        );

        console.log("\n=== Authorization Setup ===");
        console.log("REQUIRED: Vault needs authorization from optimizer admin");
        console.log(
            "REQUIRED: AI backends need authorization from vault owner"
        );
        console.log(
            "REQUIRED: Users only need to approve vault for token spending"
        );

        console.log("\n=== Key Features ===");
        console.log("- Issues receipt tokens (atUSDC, atDAI, etc.)");
        console.log("- Users can see positions in their wallets");
        console.log("- Receipt tokens are transferable ERC20s");
        console.log("- Automatic factory deployment for new tokens");
        console.log(
            "- AI-driven yield optimization via EnhancedYieldOptimizer"
        );
        console.log("- Proper authorization separation: Vault vs AI backends");

        console.log("\n=== Next Steps ===");
        console.log(
            "1. Authorize vault in EnhancedYieldOptimizer (if not done automatically):"
        );
        console.log(
            string(
                abi.encodePacked(
                    "   cast send ",
                    vm.toString(config.enhancedYieldOptimizer),
                    ' "authorizeVault(address)" ',
                    vm.toString(address(vaultV2)),
                    " --account ADMIN_ACCOUNT"
                )
            )
        );
        console.log("2. Authorize AI backends in vault:");
        console.log(
            string(
                abi.encodePacked(
                    "   cast send ",
                    vm.toString(address(vaultV2)),
                    ' "authorizeAIBackend(address)" AI_BACKEND_ADDRESS',
                    " --account VAULT_OWNER"
                )
            )
        );
        console.log("3. Add supported adapters to EnhancedYieldOptimizer");
        console.log("4. Add tokens manually using:");
        console.log(
            string(
                abi.encodePacked(
                    "   cast send ",
                    vm.toString(address(vaultV2)),
                    ' "addToken(address,uint256,uint256)" TOKEN_ADDRESS MIN_DEPOSIT MAX_DEPOSIT --rpc-url RPC_URL --account ACCOUNT'
                )
            )
        );

        console.log("5. Test deposit flow:");
        console.log("   a. User approves vault for token spending");
        console.log("   b. AI backend calls vault.deposit()");
        console.log(
            "   c. Vault calls optimizer.executeSingleOptimizedDeposit()"
        );
        console.log("   d. User receives receipt tokens");

        // Log all deployment info instead of saving to file
        console.log("\n=== Deployment Info (Save This) ===");
        console.log("Network:", config.networkName);
        console.log("Multi-Asset Vault V2:", address(vaultV2));
        console.log(
            "Receipt Token Factory:",
            address(vaultV2.receiptTokenFactory())
        );
        console.log("EnhancedYieldOptimizer:", config.enhancedYieldOptimizer);
        console.log("Admin/Owner:", config.admin);
        console.log("Block Number:", block.number);
        console.log("Chain ID:", block.chainid);
        console.log("Deployment Complete!");
    }

    /**
     * @notice Deploy to localhost/anvil for testing
     */
    function runLocal() external {
        // For local testing, we need to deploy EnhancedYieldOptimizer first or use existing address
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

        AliothVault vaultV2 = new AliothVault(
            enhancedYieldOptimizerAddr,
            admin
        );

        console.log(
            "Local Multi-Asset Vault V2 deployed at:",
            address(vaultV2)
        );
        console.log(
            "Local Receipt Token Factory deployed at:",
            address(vaultV2.receiptTokenFactory())
        );
        console.log("Owner:", admin);

        vm.stopBroadcast();
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

        console.log("=== Vault V2 Verification ===");
        console.log("Vault Address:", vaultAddress);
        console.log(
            "Enhanced Yield Optimizer:",
            address(vault.enhancedYieldOptimizer())
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
