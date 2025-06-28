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
        MockV3Aggregator linkFeed;
        MockV3Aggregator ethFeed;
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

        uint256 chainId = block.chainid;

        if (chainId == 11155111 || chainId == 84532) {
            console.log("1. Deploying USDC/USD aggregator...");
            aggregators.usdcFeed = new MockV3Aggregator(
                6,
                1e6,
                PRICE_UPDATE_INTERVAL
            );
            console.log("   USDC/USD:", address(aggregators.usdcFeed));
        } else if (chainId == 43113) {
            console.log("1. Deploying USDC/USD aggregator...");
            aggregators.usdcFeed = new MockV3Aggregator(
                6,
                1e6,
                PRICE_UPDATE_INTERVAL
            );
            console.log("   USDC/USD:", address(aggregators.usdcFeed));

            console.log("2. Deploying LINK/USD aggregator...");
            aggregators.linkFeed = new MockV3Aggregator(
                18,
                15 * 1e18,
                PRICE_UPDATE_INTERVAL
            );
            console.log("   LINK/USD:", address(aggregators.linkFeed));

            console.log("3. Deploying ETH/USD aggregator...");
            aggregators.ethFeed = new MockV3Aggregator(
                18,
                3000 * 1e18,
                PRICE_UPDATE_INTERVAL
            );
            console.log("   ETH/USD:", address(aggregators.ethFeed));
        }
        // ────────────────────── Unsupported ────────────────────────────────
        else {
            revert(
                "Unsupported network. No aggregators configured for this chain ID."
            );
        }
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
        if (address(aggregators.usdcFeed) != address(0)) {
            console.log(
                "  USDC/USD (6 decimals):",
                address(aggregators.usdcFeed)
            );
        }
        if (address(aggregators.linkFeed) != address(0)) {
            console.log(
                "  LINK/USD (18 decimals):",
                address(aggregators.linkFeed)
            );
        }
        if (address(aggregators.ethFeed) != address(0)) {
            console.log(
                "  ETH/USD (18 decimals):",
                address(aggregators.ethFeed)
            );
        }
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
