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
    // Network-specific addresses (replace with actual addresses)
    address constant CCIP_ROUTER_ETHEREUM =
        0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address constant CCIP_ROUTER_POLYGON =
        0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe;
    address constant CCIP_ROUTER_ARBITRUM =
        0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;

    // Chainlink chain selectors
    uint64 constant ETHEREUM_SELECTOR = 5009297550715157269;
    uint64 constant POLYGON_SELECTOR = 4051577828743386545;
    uint64 constant ARBITRUM_SELECTOR = 4949039107694359620;

    // LINK Token addresses
    address constant LINK_ETHEREUM = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant LINK_POLYGON = 0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39;
    address constant LINK_ARBITRUM = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
    address constant LINK_SEPOLIA = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // Mock addresses for demonstration (replace with actual protocol addresses)
    address constant AAVE_POOL_ETHEREUM =
        0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant USDC_ETHEREUM = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant USDC_PRICE_FEED =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

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
    }

    function run() external {
        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig();

        console.log("Deploying Alioth contracts to:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("Fee Collector:", config.feeCollector);
        console.log("CCIP Router:", config.ccipRouter);

        vm.startBroadcast();

        // Deploy contracts
        DeployedContracts memory contracts = deployContracts(config);

        // Setup contracts
        setupContracts(contracts, config);

        vm.stopBroadcast();

        // Log deployment addresses
        logDeployment(contracts);
    }

    function getDeploymentConfig()
        internal
        view
        returns (DeploymentConfig memory config)
    {
        uint256 chainId = block.chainid;

        // Get admin and fee collector from environment or use deployer
        address admin = vm.envOr("ADMIN_ADDRESS", msg.sender);
        address feeCollector = vm.envOr("FEE_COLLECTOR", msg.sender);

        if (chainId == 1) {
            // Ethereum Mainnet
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_ETHEREUM,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Ethereum"
            });
        } else if (chainId == 137) {
            // Polygon
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_POLYGON,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Polygon"
            });
        } else if (chainId == 42161) {
            // Arbitrum
            config = DeploymentConfig({
                ccipRouter: CCIP_ROUTER_ARBITRUM,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Arbitrum"
            });
        } else if (chainId == 11155111) {
            // Sepolia Testnet
            config = DeploymentConfig({
                ccipRouter: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
                admin: admin,
                feeCollector: feeCollector,
                networkName: "Sepolia"
            });
        } else {
            revert("Unsupported network");
        }
    }

    function getLinkTokenAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            return LINK_ETHEREUM;
        } else if (chainId == 137) {
            return LINK_POLYGON;
        } else if (chainId == 42161) {
            return LINK_ARBITRUM;
        } else if (chainId == 11155111) {
            return LINK_SEPOLIA;
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
            getLinkTokenAddress(), // Get LINK token address for the chain
            config.feeCollector
        );
        console.log(
            "CCIPMessenger deployed at:",
            address(contracts.ccipMessenger)
        );

        // Deploy Yield Optimizer
        contracts.yieldOptimizer = new YieldOptimizer(
            address(contracts.ccipMessenger),
            config.admin
        );
        console.log(
            "YieldOptimizer deployed at:",
            address(contracts.yieldOptimizer)
        );

        // Deploy Cross Chain Lending
        contracts.lending = new CrossChainLending(
            address(contracts.ccipMessenger),
            address(contracts.yieldOptimizer),
            config.admin,
            config.feeCollector
        );
        console.log(
            "CrossChainLending deployed at:",
            address(contracts.lending)
        );

        // Deploy Aave Adapter (if on Ethereum)
        if (block.chainid == 1 || block.chainid == 11155111) {
            address aavePool = block.chainid == 1
                ? AAVE_POOL_ETHEREUM
                : address(0x1); // Mock for testnet
            contracts.aaveAdapter = new AaveAdapter(aavePool, config.admin);
            console.log(
                "AaveAdapter deployed at:",
                address(contracts.aaveAdapter)
            );
        }
    }

    function setupContracts(
        DeployedContracts memory contracts,
        DeploymentConfig memory config
    ) internal {
        console.log("Setting up contracts...");

        // Setup CCIP Messenger
        setupCCIPMessenger(contracts.ccipMessenger);

        // Setup Yield Optimizer
        if (address(contracts.aaveAdapter) != address(0)) {
            setupYieldOptimizer(
                contracts.yieldOptimizer,
                contracts.aaveAdapter
            );
        }

        // Setup Cross Chain Lending
        setupLending(contracts.lending);

        // Grant roles
        grantRoles(contracts, config.admin);

        console.log("Setup completed!");
    }

    function setupCCIPMessenger(CCIPMessenger ccipMessenger) internal {
        // Add supported chains
        ccipMessenger.allowlistDestinationChain(
            ETHEREUM_SELECTOR,
            CCIP_ROUTER_ETHEREUM,
            500000 // Gas limit
        );
        ccipMessenger.allowlistDestinationChain(
            POLYGON_SELECTOR,
            CCIP_ROUTER_POLYGON,
            500000 // Gas limit
        );
        ccipMessenger.allowlistDestinationChain(
            ARBITRUM_SELECTOR,
            CCIP_ROUTER_ARBITRUM,
            500000 // Gas limit
        );

        console.log("CCIP Messenger configured with supported chains");
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
        // Add supported tokens (example with USDC)
        if (block.chainid == 1) {
            // Ethereum
            lending.addSupportedToken(USDC_ETHEREUM, true, true); // Both collateral and borrow

            // Set price oracle for USDC
            lending.setPriceOracle(
                USDC_ETHEREUM,
                USDC_PRICE_FEED,
                3600, // 1 hour heartbeat
                8 // 8 decimals
            );
        }

        console.log("Lending configured with supported tokens");
    }

    function grantRoles(
        DeployedContracts memory contracts,
        address admin
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

        // Grant yield optimizer roles to contracts and admin
        contracts.yieldOptimizer.grantRole(
            contracts.yieldOptimizer.REBALANCER_ROLE(),
            admin
        );
        contracts.yieldOptimizer.grantRole(
            contracts.yieldOptimizer.HARVESTER_ROLE(),
            admin
        );

        // Grant lending roles
        contracts.lending.grantRole(
            contracts.lending.UNDERWRITER_ROLE(),
            admin
        );
        contracts.lending.grantRole(contracts.lending.LIQUIDATOR_ROLE(), admin);

        console.log("Roles granted successfully");
    }

    function logDeployment(DeployedContracts memory contracts) internal view {
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

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Configure AI agents with contract addresses");
        console.log("3. Add additional protocol adapters");
        console.log("4. Set up monitoring and alerting");
        console.log("5. Deploy to additional chains");
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

        // Mock CCIP router for testnet
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

        console.log("Testnet deployment completed:");
        console.log("CCIPMessenger:", address(ccipMessenger));
        console.log("YieldOptimizer:", address(yieldOptimizer));
        console.log("CrossChainLending:", address(lending));
        console.log("AaveAdapter:", address(aaveAdapter));
    }
}
