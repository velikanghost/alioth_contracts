// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/mocks/MockV3Aggregator.sol";

/**
 * @title DeployAggregators
 * @notice Script to deploy Mock Price Feed Aggregators for testing
 */
contract DeployAggregators is Script {
    uint256 constant PRICE_UPDATE_INTERVAL = 3000; // 50 minutes in seconds

    struct AggregatorConfig {
        string symbol;
        uint8 decimals;
        int256 initialPrice;
        string description;
    }

    struct NetworkConfig {
        string networkName;
        address admin;
    }

    struct DeployedAggregators {
        MockV3Aggregator usdcFeed;
    }

    function setUp() public {}

    /**
     * @notice Get deployment configuration
     */
    function getDeploymentConfig()
        internal
        view
        returns (NetworkConfig memory config)
    {
        uint256 chainId = block.chainid;
        address deployer = tx.origin;
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        if (chainId == 11155111) {
            config = NetworkConfig({networkName: "Sepolia", admin: admin});
        } else if (chainId == 84532) {
            config = NetworkConfig({networkName: "Base Sepolia", admin: admin});
        } else if (chainId == 43113) {
            config = NetworkConfig({
                networkName: "Avalanche Fuji",
                admin: admin
            });
        } else {
            revert(
                "Unsupported network - only Sepolia, Base Sepolia, and Avalanche Fuji are supported"
            );
        }
    }

    /**
     * @notice Default deployment function
     */
    function run() external {
        NetworkConfig memory config = getDeploymentConfig();

        console.log("=== Mock Price Feed Aggregators Deployment ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log(
            "Update Interval:",
            PRICE_UPDATE_INTERVAL,
            "seconds (~50 min)"
        );

        vm.startBroadcast();

        DeployedAggregators memory aggregators = deployAggregators();

        vm.stopBroadcast();

        logDeployment(aggregators, config);
    }

    /**
     * @notice Deploy all mock aggregators
     */
    function deployAggregators()
        internal
        returns (DeployedAggregators memory aggregators)
    {
        console.log("\n=== Deploying Mock Aggregators ===");

        // Define aggregator configuration
        AggregatorConfig[1] memory configs = [
            AggregatorConfig({
                symbol: "USDC",
                decimals: 8,
                initialPrice: 100000000, // $1.00 with 8 decimals
                description: "Mock USDC/USD Price Feed"
            })
        ];

        // Deploy USDC aggregator
        console.log("1. Deploying USDC/USD aggregator...");
        aggregators.usdcFeed = new MockV3Aggregator(
            configs[0].decimals,
            configs[0].initialPrice,
            PRICE_UPDATE_INTERVAL
        );
        console.log("   USDC/USD:", address(aggregators.usdcFeed));
    }

    /**
     * @notice Log deployment summary
     */
    function logDeployment(
        DeployedAggregators memory aggregators,
        NetworkConfig memory config
    ) internal pure {
        console.log("\n=== Mock Aggregators Deployment Summary ===");
        console.log("Network:", config.networkName);
        console.log("Admin:", config.admin);
        console.log("");
        console.log("Deployed Mock Price Feeds (50-min auto-update):");
        console.log("  USDC/USD (8 decimals):", address(aggregators.usdcFeed));
        console.log("");
        console.log("Next Steps:");
        console.log(
            "1. Register each aggregator as Chainlink Automation Upkeep"
        );
        console.log("2. Fund upkeeps with LINK for automated price updates");
        console.log("3. Use addresses in ChainlinkFeedManager configuration");
    }

    /**
     * @notice Utility function to get network config for integration
     */
    function getNetworkConfig() external view returns (NetworkConfig memory) {
        return getDeploymentConfig();
    }

    /**
     * @notice Verify deployment by checking aggregator configuration
     */
    function verifyDeployment(address aggregatorAddress) external view {
        MockV3Aggregator aggregator = MockV3Aggregator(aggregatorAddress);

        console.log("=== Mock Aggregator Verification ===");
        console.log("Aggregator Address:", aggregatorAddress);
        console.log("Decimals:", aggregator.decimals());
        console.log("Description:", aggregator.description());
        console.log("Version:", aggregator.version());
        console.log("Update Interval:", aggregator.interval());

        (, int256 answer, , uint256 updatedAt, ) = aggregator.latestRoundData();
        console.log("Latest Answer:", uint256(answer));
        console.log("Last Updated:", updatedAt);
    }
}
