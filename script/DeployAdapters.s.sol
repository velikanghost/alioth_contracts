// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/adapters/CompoundAdapter.sol";
import "../src/core/AliothYieldOptimizer.sol";

/**
 * @title DeployAdapters
 * @notice Script to deploy protocol adapters and configure them with AliothYieldOptimizer
 * @dev Deploys Aave and Compound adapters based on environment variables:
 *      - DEPLOY_AAVE=true/false (default: false)
 *      - DEPLOY_COMPOUND=true/false (default: false)
 */
contract DeployAdapters is Script {
    address constant ALIOTH_YIELD_OPTIMIZER_SEPOLIA =
        0x3499331d4c0d88028a61bf1516246C29C30AFf8E;
    address constant ALIOTH_YIELD_OPTIMIZER_BASE_SEPOLIA =
        0x9F26D100fdB2Ca6810019062B9a3C6c01Afa21e6;
    address constant ALIOTH_YIELD_OPTIMIZER_AVALANCHE_FUJI =
        0x2F05369A361e7F452F5e5393a565D4d1cA88F80A;

    // 🏦 AAVE V3 POOL ADDRESSES
    address constant AAVE_POOL_SEPOLIA =
        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant AAVE_POOL_AVALANCHE_FUJI =
        0xccEa5C65f6d4F465B71501418b88FBe4e7071283;

    // 🏛️ COMPOUND III PROTOCOL ADDRESSES
    address constant COMPOUND_COMET_SEPOLIA =
        0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e; // cUSDCv3
    address constant COMPOUND_REWARDS_SEPOLIA =
        0x8bF5b658bdF0388E8b482ED51B14aef58f90abfD; // Rewards contract
    address constant COMP_TOKEN_SEPOLIA =
        0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531; // COMP token

    address constant COMPOUND_COMET_BASE_SEPOLIA =
        0x571621Ce60Cebb0c1D442B5afb38B1663C6Bf017;
    address constant COMPOUND_REWARDS_BASE_SEPOLIA =
        0x3394fa1baCC0b47dd0fF28C8573a476a161aF7BC;
    address constant COMP_TOKEN_BASE_SEPOLIA =
        0x2f535da74048c0874400f0371Fba20DF983A56e2;

    struct DeploymentConfig {
        address aliothYieldOptimizer;
        address aavePool;
        address compoundComet;
        address compoundRewards;
        address compToken;
        address admin;
        string networkName;
        bool deployAave;
        bool deployCompound;
    }

    struct DeployedAdapters {
        AaveAdapter aaveAdapter;
        CompoundAdapter compoundAdapter;
    }

    function run() external {
        DeploymentConfig memory config = getDeploymentConfig();

        console.log("=== Deploying Protocol Adapters ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("AliothYieldOptimizer:", config.aliothYieldOptimizer);
        console.log("Deploy Aave:", config.deployAave);
        console.log("Deploy Compound:", config.deployCompound);

        vm.startBroadcast();

        DeployedAdapters memory adapters = deployAdapters(config);

        vm.stopBroadcast();

        logDeployment(adapters, config);
    }

    function getDeploymentConfig()
        internal
        view
        returns (DeploymentConfig memory config)
    {
        uint256 chainId = block.chainid;

        address deployer = tx.origin;
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        bool deployAave = vm.envOr("DEPLOY_AAVE", false);
        bool deployCompound = vm.envOr("DEPLOY_COMPOUND", false);

        if (chainId == 11155111) {
            config = DeploymentConfig({
                aliothYieldOptimizer: ALIOTH_YIELD_OPTIMIZER_SEPOLIA,
                aavePool: AAVE_POOL_SEPOLIA,
                compoundComet: COMPOUND_COMET_SEPOLIA,
                compoundRewards: COMPOUND_REWARDS_SEPOLIA,
                compToken: COMP_TOKEN_SEPOLIA,
                admin: admin,
                networkName: "Sepolia",
                deployAave: deployAave,
                deployCompound: deployCompound
            });
        } else if (chainId == 84532) {
            config = DeploymentConfig({
                aliothYieldOptimizer: ALIOTH_YIELD_OPTIMIZER_BASE_SEPOLIA,
                aavePool: 0x0000000000000000000000000000000000000000,
                compoundComet: COMPOUND_COMET_BASE_SEPOLIA,
                compoundRewards: COMPOUND_REWARDS_BASE_SEPOLIA,
                compToken: COMP_TOKEN_BASE_SEPOLIA,
                admin: admin,
                networkName: "Base Sepolia",
                deployAave: deployAave,
                deployCompound: deployCompound
            });
        } else if (chainId == 43113) {
            config = DeploymentConfig({
                aliothYieldOptimizer: ALIOTH_YIELD_OPTIMIZER_AVALANCHE_FUJI,
                aavePool: AAVE_POOL_AVALANCHE_FUJI,
                compoundComet: 0x0000000000000000000000000000000000000000,
                compoundRewards: 0x0000000000000000000000000000000000000000,
                compToken: 0x0000000000000000000000000000000000000000,
                admin: admin,
                networkName: "Avalanche Fuji",
                deployAave: deployAave,
                deployCompound: deployCompound
            });
        } else {
            revert(
                "Unsupported network - only Sepolia, Arbitrum Sepolia, and Base Sepolia are supported"
            );
        }

        require(
            config.aliothYieldOptimizer != address(0),
            string(
                abi.encodePacked(
                    "AliothYieldOptimizer not configured for ",
                    config.networkName,
                    ". Please update the constant in this script."
                )
            )
        );

        if (config.deployAave) {
            require(
                config.aavePool != address(0),
                string(
                    abi.encodePacked(
                        "Aave Pool not configured for ",
                        config.networkName,
                        ". Cannot deploy AaveAdapter."
                    )
                )
            );
        }

        if (config.deployCompound) {
            require(
                config.compoundComet != address(0) &&
                    config.compoundRewards != address(0) &&
                    config.compToken != address(0),
                string(
                    abi.encodePacked(
                        "Compound III addresses not configured for ",
                        config.networkName,
                        ". Cannot deploy CompoundAdapter."
                    )
                )
            );
        }
    }

    function deployAdapters(
        DeploymentConfig memory config
    ) internal returns (DeployedAdapters memory adapters) {
        console.log("\n=== Deploying Protocol Adapters ===");

        console.log("Configured Admin:", config.admin);

        if (config.deployAave && config.aavePool != address(0)) {
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
            console.log("1. Skipping AaveAdapter deployment");
        }

        if (
            config.deployCompound &&
            config.compoundComet != address(0) &&
            config.compoundRewards != address(0) &&
            config.compToken != address(0)
        ) {
            console.log("2. Deploying CompoundAdapter...");
            adapters.compoundAdapter = new CompoundAdapter(
                config.compoundComet,
                config.compoundRewards,
                config.compToken,
                config.admin
            );
            console.log(
                "   CompoundAdapter deployed at:",
                address(adapters.compoundAdapter)
            );
        } else {
            console.log("2. Skipping CompoundAdapter deployment");
        }

        console.log("Adapter deployment completed!");
    }

    function logDeployment(
        DeployedAdapters memory adapters,
        DeploymentConfig memory config
    ) internal pure {
        console.log("\n=== Protocol Adapters Deployment Summary ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("AliothYieldOptimizer:", config.aliothYieldOptimizer);
        console.log("");
        console.log("Deployed Adapters:");

        if (config.deployAave) {
            if (address(adapters.aaveAdapter) != address(0)) {
                console.log("  AaveAdapter:", address(adapters.aaveAdapter));
            } else {
                console.log(
                    "  AaveAdapter: Not deployed (unavailable on this network)"
                );
            }
        } else {
            console.log("  AaveAdapter: Skipped");
        }

        if (config.deployCompound) {
            if (address(adapters.compoundAdapter) != address(0)) {
                console.log(
                    "  CompoundAdapter:",
                    address(adapters.compoundAdapter)
                );
            } else {
                console.log(
                    "  CompoundAdapter: Not deployed (unavailable on this network)"
                );
            }
        } else {
            console.log("  CompoundAdapter: Skipped");
        }
    }

    /**
     * @notice Verify adapter deployment
     */
    function verifyDeployment(
        address aaveAdapterAddress,
        address compoundAdapterAddress
    ) external view {
        if (aaveAdapterAddress != address(0)) {
            AaveAdapter adapter = AaveAdapter(aaveAdapterAddress);

            console.log("=== Aave Adapter Verification ===");
            console.log("Adapter Address:", aaveAdapterAddress);
            console.log("Protocol Name:", adapter.protocolName());
            console.log("Aave Pool:", address(adapter.aavePool()));
        }

        if (compoundAdapterAddress != address(0)) {
            CompoundAdapter adapter = CompoundAdapter(compoundAdapterAddress);

            console.log("\n=== Compound Adapter Verification ===");
            console.log("Adapter Address:", compoundAdapterAddress);
            console.log("Protocol Name:", adapter.protocolName());
            console.log("Comet Address:", adapter.getCometAddress());
            console.log("Base Asset:", adapter.getBaseAsset());
        }
    }
}
