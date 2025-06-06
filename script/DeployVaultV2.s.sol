// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/vaults/AliothMultiAssetVaultV2.sol";
import "../src/core/YieldOptimizer.sol";

/**
 * @title DeployVaultV2
 * @notice Script to deploy the Alioth Multi-Asset Vault V2 with Receipt Tokens
 */
contract DeployVaultV2 is Script {
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

        console.log("=== Alioth Multi-Asset Vault V2 Deployment ===");
        console.log("Network:", networkName);
        console.log("YieldOptimizer:", config.yieldOptimizer);
        console.log("Admin:", config.admin);

        vm.startBroadcast();

        // Get the actual broadcaster address (tx.origin in broadcast context)
        address deployer = tx.origin;
        console.log("Deployer (from tx.origin):", deployer);
        console.log("Configured Admin:", config.admin);

        // Deploy the Multi-Asset Vault V2 with the configured admin as owner
        AliothMultiAssetVaultV2 vaultV2 = new AliothMultiAssetVaultV2(
            config.yieldOptimizer,
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

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Multi-Asset Vault V2:", address(vaultV2));
        console.log(
            "Receipt Token Factory:",
            address(vaultV2.receiptTokenFactory())
        );
        console.log("Owner:", config.admin);
        console.log("YieldOptimizer Integration:", config.yieldOptimizer);

        console.log("\n=== Key Features ===");
        console.log("- Issues receipt tokens (atUSDC, atDAI, etc.)");
        console.log("- Users can see positions in their wallets");
        console.log("- Receipt tokens are transferable ERC20s");
        console.log("- Automatic factory deployment for new tokens");

        console.log("\n=== Next Steps ===");
        console.log("1. Verify the contracts on block explorer");
        console.log("2. Add tokens manually using:");
        console.log(
            string(
                abi.encodePacked(
                    "   cast send ",
                    vm.toString(address(vaultV2)),
                    ' "addToken(address,uint256,uint256)" TOKEN_ADDRESS MIN_DEPOSIT MAX_DEPOSIT --rpc-url https://sepolia.infura.io/v3/c7c5f43ca9bc47afa93181f412d404f5 --account monad'
                )
            )
        );

        console.log("3. Check receipt tokens with:");
        console.log(
            string(
                abi.encodePacked(
                    "   cast call ",
                    vm.toString(address(vaultV2)),
                    ' "getReceiptToken(address)" TOKEN_ADDRESS --rpc-url https://sepolia.infura.io/v3/c7c5f43ca9bc47afa93181f412d404f5'
                )
            )
        );

        // Verification commands
        console.log("\n=== Verification Commands ===");
        console.log("Vault V2 verification:");
        console.log(
            string(
                abi.encodePacked(
                    "forge verify-contract ",
                    vm.toString(address(vaultV2)),
                    " src/vaults/AliothMultiAssetVaultV2.sol:AliothMultiAssetVaultV2 --chain-id ",
                    vm.toString(block.chainid),
                    " --constructor-args ",
                    vm.toString(abi.encode(config.yieldOptimizer, config.admin))
                )
            )
        );

        console.log("\nReceipt Token Factory verification:");
        console.log(
            string(
                abi.encodePacked(
                    "forge verify-contract ",
                    vm.toString(address(vaultV2.receiptTokenFactory())),
                    " src/factories/ReceiptTokenFactory.sol:ReceiptTokenFactory --chain-id ",
                    vm.toString(block.chainid),
                    " --constructor-args ",
                    vm.toString(abi.encode(address(vaultV2)))
                )
            )
        );

        // Log all deployment info instead of saving to file
        console.log("\n=== Deployment Info (Save This) ===");
        console.log("Network:", networkName);
        console.log("Multi-Asset Vault V2:", address(vaultV2));
        console.log(
            "Receipt Token Factory:",
            address(vaultV2.receiptTokenFactory())
        );
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

        AliothMultiAssetVaultV2 vaultV2 = new AliothMultiAssetVaultV2(
            yieldOptimizerAddr,
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
        AliothMultiAssetVaultV2 vault = AliothMultiAssetVaultV2(vaultAddress);

        console.log("=== Vault V2 Verification ===");
        console.log("Vault Address:", vaultAddress);
        console.log("YieldOptimizer:", address(vault.yieldOptimizer()));
        console.log(
            "Receipt Token Factory:",
            address(vault.receiptTokenFactory())
        );
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
            try vault.getReceiptToken(tokens[i]) returns (
                address receiptToken
            ) {
                console.log("    Receipt Token:", receiptToken);
            } catch {
                console.log("    Receipt Token: Not created yet");
            }
        }

        address[] memory receiptTokens = vault.getAllReceiptTokens();
        console.log("\nReceipt Tokens:");
        for (uint256 i = 0; i < receiptTokens.length; i++) {
            console.log("  Receipt Token", i, ":", receiptTokens[i]);
        }
    }

    /**
     * @notice Helper function to test receipt token creation
     */
    function testReceiptTokenCreation(
        address vaultAddress,
        address tokenAddress,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external {
        AliothMultiAssetVaultV2 vault = AliothMultiAssetVaultV2(vaultAddress);

        console.log("=== Testing Receipt Token Creation ===");
        console.log("Vault:", vaultAddress);
        console.log("Token:", tokenAddress);

        vm.startBroadcast();

        // This will create the receipt token automatically
        vault.addToken(tokenAddress, minDeposit, maxDeposit);

        address receiptToken = vault.getReceiptToken(tokenAddress);
        console.log("Created Receipt Token:", receiptToken);

        vm.stopBroadcast();
    }

    /**
     * @notice Helper function to check user receipt tokens
     */
    function checkUserReceiptTokens(
        address vaultAddress,
        address userAddress
    ) external view {
        AliothMultiAssetVaultV2 vault = AliothMultiAssetVaultV2(vaultAddress);

        console.log("=== User Receipt Token Portfolio ===");
        console.log("Vault:", vaultAddress);
        console.log("User:", userAddress);

        (
            address[] memory tokens,
            address[] memory receiptTokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols,
            uint256[] memory apys
        ) = vault.getUserPortfolio(userAddress);

        console.log("Portfolio size:", tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("\nPosition", i, ":");
            console.log("  Token:", tokens[i]);
            console.log("  Receipt Token:", receiptTokens[i]);
            console.log("  Symbol:", symbols[i]);
            console.log("  Receipt Token Balance:", shares[i]);
            console.log("  Underlying Value:", values[i]);
            console.log("  APY:", apys[i], "bps");
        }
    }
}
