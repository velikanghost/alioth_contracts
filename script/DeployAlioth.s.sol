// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/core/YieldOptimizer.sol";
import "../src/core/CrossChainLending.sol";
import "../src/core/CCIPMessenger.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/adapters/CompoundAdapter.sol";
import "../src/adapters/YearnAdapter.sol";

/**
 * @title DeployAlioth
 * @notice Deployment script for Alioth platform contracts
 * @dev Run with: forge script script/DeployAlioth.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployAlioth is Script {
    // ✅ CHAINLINK CCIP ROUTER ADDRESSES (TESTNET SPECIFIC)
    address constant CCIP_ROUTER_SEPOLIA =
        0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address constant CCIP_ROUTER_ARBITRUM_SEPOLIA =
        0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;
    address constant CCIP_ROUTER_AVALANCHE_FUJI =
        0xF694E193200268f9a4868e4Aa017A0118C9a8177;
    address constant CCIP_ROUTER_OPTIMISM_SEPOLIA =
        0x114A20A10b43D4115e5aeef7345a1A71d2a60C57;

    // ✅ CHAINLINK CHAIN SELECTORS (TESTNET SPECIFIC)
    uint64 constant SEPOLIA_SELECTOR = 16015286601757825753;
    uint64 constant ARBITRUM_SEPOLIA_SELECTOR = 3478487238524512106;
    uint64 constant AVALANCHE_FUJI_SELECTOR = 14767482510784806043;
    uint64 constant OPTIMISM_SEPOLIA_SELECTOR = 5224473277236331295;

    // ✅ LINK TOKEN ADDRESSES (TESTNET SPECIFIC)
    address constant LINK_SEPOLIA = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant LINK_ARBITRUM_SEPOLIA =
        0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;
    address constant LINK_AVALANCHE_FUJI =
        0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;
    address constant LINK_OPTIMISM_SEPOLIA =
        0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    // 🏦 AAVE V3 POOL ADDRESSES (TESTNET SPECIFIC) - UPDATED TO MATCH TESTNET.JSON
    address constant AAVE_POOL_SEPOLIA =
        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951; // Aave V3 Sepolia Pool ✅
    address constant AAVE_POOL_ARBITRUM_SEPOLIA =
        0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff; // Aave V3 Arbitrum Sepolia Pool ✅
    address constant AAVE_POOL_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Not available on testnet
    address constant AAVE_POOL_OPTIMISM_SEPOLIA =
        0xb50201558B00496A145fE76f7424749556E326D8; // Aave V3 Optimism Sepolia Pool ✅

    // 🏛️ COMPOUND PROTOCOL ADDRESSES (TESTNET SPECIFIC)
    // Note: Compound V3 is not widely available on testnets
    // Using mock addresses for development purposes
    address constant COMPOUND_COMPTROLLER_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant COMPOUND_COMPTROLLER_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant COMPOUND_COMPTROLLER_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant COMPOUND_COMPTROLLER_OPTIMISM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address

    // For testing, we'll use the same COMP token addresses
    address constant COMPOUND_COMP_TOKEN =
        0xc00e94Cb662C3520282E6f5717214004A7f26888; // Using mainnet address for interface
    address constant COMPOUND_CETH_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address

    // 🌾 YEARN PROTOCOL ADDRESSES (TESTNET SPECIFIC)
    // Note: Yearn is not available on testnets, using mock addresses
    address constant YEARN_REGISTRY_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant YEARN_REGISTRY_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant YEARN_REGISTRY_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Mock address
    address constant YEARN_REGISTRY_OPTIMISM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Mock address

    // 💰 USDC TOKEN ADDRESSES (TESTNET SPECIFIC - CIRCLE OFFICIAL)
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant USDC_ARBITRUM_SEPOLIA =
        0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant USDC_AVALANCHE_FUJI =
        0x5425890298aed601595a70AB815c96711a31Bc65;
    address constant USDC_OPTIMISM_SEPOLIA =
        0x5fd84259d66Cd46123540766Be93DFE6D43130D7; // Circle official USDC

    // 📊 CHAINLINK PRICE FEED ADDRESSES (TESTNET SPECIFIC)
    // Note: Most testnets have very limited price feed coverage

    // SEPOLIA (Best Coverage) ✅
    address constant USDC_PRICE_FEED_SEPOLIA =
        0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; // USDC/USD Sepolia ✅
    address constant ETH_PRICE_FEED_SEPOLIA =
        0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD Sepolia ✅
    address constant BTC_PRICE_FEED_SEPOLIA =
        0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // BTC/USD Sepolia ✅
    address constant LINK_PRICE_FEED_SEPOLIA =
        0xc59E3633BAAC79493d908e63626716e204A45EdF; // LINK/USD Sepolia ✅

    // ARBITRUM SEPOLIA (Limited Coverage) ⚠️
    address constant ETH_PRICE_FEED_ARBITRUM_SEPOLIA =
        0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165; // ETH/USD Arbitrum Sepolia ✅
    address constant USDC_PRICE_FEED_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Not available ❌
    address constant BTC_PRICE_FEED_ARBITRUM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Not available ❌

    // OPTIMISM SEPOLIA (Limited Coverage) ⚠️
    address constant ETH_PRICE_FEED_OPTIMISM_SEPOLIA =
        0x61Ec26aA57019C486B10502285c5A3D4A4750AD7; // ETH/USD Optimism Sepolia ✅
    address constant USDC_PRICE_FEED_OPTIMISM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Not available ❌
    address constant BTC_PRICE_FEED_OPTIMISM_SEPOLIA =
        0x0000000000000000000000000000000000000000; // Not available ❌

    // AVALANCHE FUJI (Very Limited Coverage) ⚠️
    address constant AVAX_PRICE_FEED_AVALANCHE_FUJI =
        0x5498BB86BC934c8D34FDA08E81D444153d0D06aD; // AVAX/USD Fuji ✅
    address constant USDC_PRICE_FEED_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Not available ❌
    address constant ETH_PRICE_FEED_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Not available ❌
    address constant BTC_PRICE_FEED_AVALANCHE_FUJI =
        0x0000000000000000000000000000000000000000; // Not available ❌

    // 🧪 CCIP TEST TOKENS (AVAILABLE ON ALL TESTNETS)
    address constant CCIP_BNM_SEPOLIA =
        0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;
    address constant CCIP_BNM_ARBITRUM_SEPOLIA =
        0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D;
    address constant CCIP_BNM_AVALANCHE_FUJI =
        0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4;
    address constant CCIP_BNM_OPTIMISM_SEPOLIA =
        0x8aF4204e30565DF93352fE8E1De78925F6664dA7; // CCIP-BnM OP Sepolia

    address constant CCIP_LNM_SEPOLIA =
        0x466D489b6d36E7E3b824ef491C225F5830E81cC1;
    // Note: CCIP-LnM is only native on Sepolia, wrapped on other testnets
    address constant CCIP_LNM_ARBITRUM_SEPOLIA =
        0x139E99f0ab4084E14e6bb7DacA289a91a2d92927; // clCCIP-LnM
    address constant CCIP_LNM_AVALANCHE_FUJI =
        0x70f5C5c40B873EA597776Da2c21929A8282a953A; // clCCIP-LnM
    address constant CCIP_LNM_OPTIMISM_SEPOLIA =
        0x044a6B4b561af69D2319A2f4be5Ec327a6975D0a; // clCCIP-LnM

    struct DeploymentConfig {
        address ccipRouter;
        address admin;
        address feeCollector;
        string networkName;
    }

    struct DeployedContracts {
        CCIPMessenger ccipMessenger;
        YieldOptimizer yieldOptimizer;
        CrossChainLending lending;
        AaveAdapter aaveAdapter;
        CompoundAdapter compoundAdapter;
        YearnAdapter yearnAdapter;
    }

    function run() external {
        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig();

        console.log("Deploying Alioth contracts to:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("Fee Collector:", config.feeCollector);
        console.log("CCIP Router:", config.ccipRouter);

        vm.startBroadcast();

        // Deploy contracts with deployer as initial admin for setup
        DeployedContracts memory contracts = deployContracts(config);

        vm.stopBroadcast();

        // Setup contracts (admin calls need to be outside of broadcast)
        setupContracts(contracts, config);

        // Log deployment addresses
        logDeployment(contracts);

        // Log admin transfer instructions if needed
        if (config.admin != tx.origin) {
            logAdminTransferInstructions(contracts, config.admin);
        }
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

        // Get admin and fee collector from environment or use deployer
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address feeCollector = vm.envOr("FEE_COLLECTOR", deployer);

        if (chainId == 11155111) {
            // Ethereum Sepolia
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_SEPOLIA,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Sepolia"
            });
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_ARBITRUM_SEPOLIA,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Arbitrum Sepolia"
            });
        } else if (chainId == 43113) {
            // Avalanche Fuji
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_AVALANCHE_FUJI,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Avalanche Fuji"
            });
        } else if (chainId == 11155420) {
            // Optimism Sepolia
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_OPTIMISM_SEPOLIA,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Optimism Sepolia"
            });
        } else {
            revert(
                "Unsupported network - only Sepolia, Arbitrum Sepolia, Avalanche Fuji, and Optimism Sepolia are supported"
            );
        }
    }

    function getLinkTokenAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return LINK_SEPOLIA;
        } else if (chainId == 421614) {
            return LINK_ARBITRUM_SEPOLIA;
        } else if (chainId == 43113) {
            return LINK_AVALANCHE_FUJI;
        } else if (chainId == 11155420) {
            return LINK_OPTIMISM_SEPOLIA;
        } else {
            revert("LINK token not available for this network");
        }
    }

    function deployContracts(
        DeploymentConfig memory config
    ) internal returns (DeployedContracts memory contracts) {
        console.log("Deploying contracts...");

        // Deploy CCIP Messenger
        contracts.ccipMessenger = new CCIPMessenger(
            config.ccipRouter,
            getLinkTokenAddress(),
            config.feeCollector
        );
        console.log(
            "CCIPMessenger deployed at:",
            address(contracts.ccipMessenger)
        );

        // Deploy Yield Optimizer with configured admin
        contracts.yieldOptimizer = new YieldOptimizer(
            address(contracts.ccipMessenger),
            config.admin // Use config.admin instead of tx.origin for consistency
        );
        console.log(
            "YieldOptimizer deployed at:",
            address(contracts.yieldOptimizer)
        );

        // Deploy Cross Chain Lending with configured admin
        contracts.lending = new CrossChainLending(
            address(contracts.ccipMessenger),
            address(contracts.yieldOptimizer),
            config.admin, // Use config.admin as initial admin
            config.feeCollector
        );
        console.log(
            "CrossChainLending deployed at:",
            address(contracts.lending)
        );

        // Deploy Aave Adapter (available on Sepolia, Arbitrum Sepolia, and Optimism Sepolia)
        if (
            block.chainid == 11155111 ||
            block.chainid == 421614 ||
            block.chainid == 11155420
        ) {
            address aavePool = getAavePoolAddress();
            contracts.aaveAdapter = new AaveAdapter(aavePool, config.admin); // Use config.admin as initial admin
            console.log(
                "AaveAdapter deployed at:",
                address(contracts.aaveAdapter)
            );
        } else {
            console.log(
                "Aave V3 not available on this testnet - skipping AaveAdapter deployment"
            );
        }

        // Skip Compound and Yearn adapters for testnets as they're not available
        // These can be enabled later when testnet infrastructure is available
        console.log(
            "Compound and Yearn adapters skipped - not available on testnets"
        );
    }

    function setupContracts(
        DeployedContracts memory contracts,
        DeploymentConfig memory config
    ) internal {
        console.log("Setting up contracts...");

        // Setup CCIP Messenger (this doesn't require admin privileges)
        vm.startBroadcast();
        setupCCIPMessenger(contracts.ccipMessenger);
        vm.stopBroadcast();

        // Setup Yield Optimizer (only add Aave adapter if deployed)
        if (address(contracts.aaveAdapter) != address(0)) {
            // Start pranking as the actual admin to call admin functions
            vm.startPrank(config.admin);
            setupYieldOptimizer(
                contracts.yieldOptimizer,
                contracts.aaveAdapter
            );
            vm.stopPrank();
        }

        // Setup Cross Chain Lending - TEMPORARILY DISABLED FOR TESTING
        // setupLending(contracts.lending);

        // Grant roles - TEMPORARILY DISABLED DUE TO DEFAULT_SENDER ISSUE
        // grantRoles(contracts);

        console.log(
            "Setup completed! (Lending setup and role granting skipped for testing)"
        );
        console.log(
            "NOTE: You will need to manually grant roles after deployment"
        );
    }

    function setupCCIPMessenger(CCIPMessenger ccipMessenger) internal {
        // Add supported testnet chains
        ccipMessenger.allowlistDestinationChain(
            SEPOLIA_SELECTOR,
            CCIP_ROUTER_SEPOLIA,
            500000 // Gas limit
        );
        ccipMessenger.allowlistDestinationChain(
            ARBITRUM_SEPOLIA_SELECTOR,
            CCIP_ROUTER_ARBITRUM_SEPOLIA,
            500000 // Gas limit
        );
        ccipMessenger.allowlistDestinationChain(
            AVALANCHE_FUJI_SELECTOR,
            CCIP_ROUTER_AVALANCHE_FUJI,
            500000 // Gas limit
        );
        ccipMessenger.allowlistDestinationChain(
            OPTIMISM_SEPOLIA_SELECTOR,
            CCIP_ROUTER_OPTIMISM_SEPOLIA,
            500000 // Gas limit
        );

        console.log("CCIP Messenger configured with supported testnet chains");
    }

    function setupYieldOptimizer(
        YieldOptimizer yieldOptimizer,
        AaveAdapter aaveAdapter
    ) internal {
        // Add Aave adapter to yield optimizer
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000); // 100% weight initially

        console.log("Yield Optimizer configured with Aave adapter");
    }

    function setupLending(CrossChainLending lending) internal {
        // Add supported tokens with testnet USDC addresses
        if (block.chainid == 11155111) {
            // Sepolia
            lending.addSupportedToken(USDC_SEPOLIA, true, true);
            lending.addSupportedToken(CCIP_BNM_SEPOLIA, true, false); // Test token
            lending.addSupportedToken(CCIP_LNM_SEPOLIA, false, true); // Test token

            // Set price oracle for USDC (if available)
            if (USDC_PRICE_FEED_SEPOLIA != address(0)) {
                lending.setPriceOracle(
                    USDC_SEPOLIA,
                    USDC_PRICE_FEED_SEPOLIA,
                    3600, // 1 hour heartbeat
                    8 // 8 decimals
                );
            }
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia
            lending.addSupportedToken(USDC_ARBITRUM_SEPOLIA, true, true);
            lending.addSupportedToken(CCIP_BNM_ARBITRUM_SEPOLIA, true, false);
            lending.addSupportedToken(CCIP_LNM_ARBITRUM_SEPOLIA, false, true);
        } else if (block.chainid == 43113) {
            // Avalanche Fuji
            lending.addSupportedToken(USDC_AVALANCHE_FUJI, true, true);
            lending.addSupportedToken(CCIP_BNM_AVALANCHE_FUJI, true, false);
            lending.addSupportedToken(CCIP_LNM_AVALANCHE_FUJI, false, true);
        } else if (block.chainid == 11155420) {
            // Optimism Sepolia
            lending.addSupportedToken(USDC_OPTIMISM_SEPOLIA, true, true);
            lending.addSupportedToken(CCIP_BNM_OPTIMISM_SEPOLIA, true, false);
            lending.addSupportedToken(CCIP_LNM_OPTIMISM_SEPOLIA, false, true);
        }

        console.log("Lending configured with supported tokens");
    }

    function grantRoles(
        DeployedContracts memory contracts,
        DeploymentConfig memory config
    ) internal {
        // Grant CCIP Messenger sender role to other contracts
        contracts.ccipMessenger.grantRole(
            contracts.ccipMessenger.SENDER_ROLE(),
            address(contracts.yieldOptimizer)
        );
        contracts.ccipMessenger.grantRole(
            contracts.ccipMessenger.SENDER_ROLE(),
            address(contracts.lending)
        );

        // Grant yield optimizer roles to deployer (tx.origin is the actual signer)
        contracts.yieldOptimizer.grantRole(
            contracts.yieldOptimizer.REBALANCER_ROLE(),
            config.admin
        );
        contracts.yieldOptimizer.grantRole(
            contracts.yieldOptimizer.HARVESTER_ROLE(),
            config.admin
        );

        // Grant lending roles to deployer (tx.origin is the actual signer)
        contracts.lending.grantRole(
            contracts.lending.UNDERWRITER_ROLE(),
            config.admin
        );
        contracts.lending.grantRole(
            contracts.lending.LIQUIDATOR_ROLE(),
            config.admin
        );

        console.log("Roles granted successfully to deployer");
    }

    function logDeployment(DeployedContracts memory contracts) internal pure {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("CCIPMessenger:", address(contracts.ccipMessenger));
        console.log("YieldOptimizer:", address(contracts.yieldOptimizer));
        console.log("CrossChainLending:", address(contracts.lending));

        if (address(contracts.aaveAdapter) != address(0)) {
            console.log("AaveAdapter:", address(contracts.aaveAdapter));
        }

        console.log("\n=== VERIFICATION COMMANDS ===");
        console.log(
            "forge verify-contract",
            address(contracts.ccipMessenger),
            "src/core/CCIPMessenger.sol:CCIPMessenger"
        );
        console.log(
            "forge verify-contract",
            address(contracts.yieldOptimizer),
            "src/core/YieldOptimizer.sol:YieldOptimizer"
        );
        console.log(
            "forge verify-contract",
            address(contracts.lending),
            "src/core/CrossChainLending.sol:CrossChainLending"
        );

        if (address(contracts.aaveAdapter) != address(0)) {
            console.log(
                "forge verify-contract",
                address(contracts.aaveAdapter),
                "src/adapters/AaveAdapter.sol:AaveAdapter"
            );
        }

        console.log("\n=== TESTNET DEPLOYMENT NOTES ===");
        console.log("1. This deployment is configured for testnet use only");
        console.log("2. USDC addresses are official Circle testnet tokens");
        console.log(
            "3. CCIP-BnM and CCIP-LnM tokens are available for testing"
        );
        console.log(
            "4. Aave V3 is available on Sepolia, Arbitrum Sepolia, and Optimism Sepolia"
        );
        console.log("5. Avalanche Fuji does not have Aave V3 available");
        console.log(
            "6. Compound and Yearn adapters are not deployed (testnets unavailable)"
        );
        console.log("7. Get testnet tokens from: https://faucets.chain.link/");
        console.log("8. Get testnet USDC from: https://faucet.circle.com/");
        console.log("9. Warning: Chainlink Price Feeds availability:");
        console.log(
            "   - Sepolia: ETH/USD, BTC/USD, LINK/USD, USDC/USD (Complete)"
        );
        console.log("   - Arbitrum Sepolia: ETH/USD only (Limited)");
        console.log("   - Optimism Sepolia: ETH/USD only (Limited)");
        console.log("   - Avalanche Fuji: AVAX/USD only (Limited)");
        console.log(
            "10. Use mock price feeds for development on limited testnets"
        );

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify contracts on block explorers");
        console.log("2. Configure AI agents with contract addresses");
        console.log("3. Test cross-chain functionality between testnets");
        console.log("4. Set up monitoring for testnet operations");
        console.log("5. Prepare for mainnet deployment after testing");
    }

    function getAavePoolAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return AAVE_POOL_SEPOLIA;
        } else if (chainId == 421614) {
            return AAVE_POOL_ARBITRUM_SEPOLIA;
        } else if (chainId == 11155420) {
            return AAVE_POOL_OPTIMISM_SEPOLIA;
        } else {
            revert("Aave V3 pool not available for this testnet");
        }
    }

    function getUSDCAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return USDC_SEPOLIA;
        } else if (chainId == 421614) {
            return USDC_ARBITRUM_SEPOLIA;
        } else if (chainId == 43113) {
            return USDC_AVALANCHE_FUJI;
        } else if (chainId == 11155420) {
            return USDC_OPTIMISM_SEPOLIA;
        } else {
            revert("USDC not available for this network");
        }
    }

    function getCCIPBnMAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return CCIP_BNM_SEPOLIA;
        } else if (chainId == 421614) {
            return CCIP_BNM_ARBITRUM_SEPOLIA;
        } else if (chainId == 43113) {
            return CCIP_BNM_AVALANCHE_FUJI;
        } else if (chainId == 11155420) {
            return CCIP_BNM_OPTIMISM_SEPOLIA;
        } else {
            revert("CCIP-BnM not available for this network");
        }
    }

    function logAdminTransferInstructions(
        DeployedContracts memory contracts,
        address newAdmin
    ) internal pure {
        console.log("\n=== ADMIN TRANSFER INSTRUCTIONS ===");
        console.log(
            "The contracts were deployed with deployer as admin for setup."
        );
        console.log("To transfer admin rights to:", newAdmin);
        console.log("");
        console.log("Run these commands with the deployer wallet:");
        console.log("1. Grant roles to new admin:");
        console.log("   YieldOptimizer.grantRole(REBALANCER_ROLE, newAdmin)");
        console.log("   YieldOptimizer.grantRole(HARVESTER_ROLE, newAdmin)");
        console.log(
            "   CrossChainLending.grantRole(UNDERWRITER_ROLE, newAdmin)"
        );
        console.log(
            "   CrossChainLending.grantRole(LIQUIDATOR_ROLE, newAdmin)"
        );
        console.log("");
        console.log(
            "2. Update admin variable in CrossChainLending (if function exists)"
        );
        console.log("3. Consider revoking deployer roles after verification");
    }

    function getETHPriceFeedAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return ETH_PRICE_FEED_SEPOLIA; // Available
        } else if (chainId == 421614) {
            return ETH_PRICE_FEED_ARBITRUM_SEPOLIA; // Available
        } else if (chainId == 11155420) {
            return ETH_PRICE_FEED_OPTIMISM_SEPOLIA; // Available
        } else if (chainId == 43113) {
            return address(0); // Not available on Avalanche Fuji
        } else {
            revert("ETH/USD price feed not available for this testnet");
        }
    }

    function getUSDCPriceFeedAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return USDC_PRICE_FEED_SEPOLIA; // Available
        } else if (chainId == 421614) {
            return address(0); // Not available on Arbitrum Sepolia
        } else if (chainId == 11155420) {
            return address(0); // Not available on Optimism Sepolia
        } else if (chainId == 43113) {
            return address(0); // Not available on Avalanche Fuji
        } else {
            revert("USDC/USD price feed not available for this testnet");
        }
    }

    function getBTCPriceFeedAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            return BTC_PRICE_FEED_SEPOLIA; // Available
        } else {
            return address(0); // Not available on other testnets
        }
    }

    function getAVAXPriceFeedAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 43113) {
            return AVAX_PRICE_FEED_AVALANCHE_FUJI; // Available
        } else {
            return address(0); // Not available on other testnets
        }
    }
}

/**
 * @title DeployTestnet
 * @notice Simplified deployment for testnet with mock contracts
 */
contract DeployTestnet is Script {
    function run() external {
        vm.startBroadcast();

        address admin = msg.sender;
        address feeCollector = msg.sender;

        // Mock CCIP router for local testing
        address mockRouter = address(0x1);

        // Deploy core contracts
        CCIPMessenger ccipMessenger = new CCIPMessenger(
            mockRouter,
            admin,
            feeCollector
        );
        YieldOptimizer yieldOptimizer = new YieldOptimizer(
            address(ccipMessenger),
            admin
        );
        CrossChainLending lending = new CrossChainLending(
            address(ccipMessenger),
            address(yieldOptimizer),
            admin,
            feeCollector
        );

        // Mock Aave adapter
        AaveAdapter aaveAdapter = new AaveAdapter(address(0x2), admin);

        // Basic setup
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);

        vm.stopBroadcast();

        console.log("Local testnet deployment completed:");
        console.log("CCIPMessenger:", address(ccipMessenger));
        console.log("YieldOptimizer:", address(yieldOptimizer));
        console.log("CrossChainLending:", address(lending));
        console.log("AaveAdapter:", address(aaveAdapter));
    }
}
