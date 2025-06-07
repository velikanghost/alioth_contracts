// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IYieldOptimizer
 * @notice Interface for the AI-driven yield optimization system
 * @dev Manages allocation across multiple protocols and chains for optimal yield
 */
interface IYieldOptimizer {
    struct AllocationTarget {
        address protocolAdapter;
        uint256 targetPercentage; // in basis points (10000 = 100%)
        uint256 currentAllocation;
        uint256 currentAPY;
    }

    struct RebalanceParams {
        address token;
        AllocationTarget[] targets;
        uint256 maxSlippage; // in basis points
        uint256 deadline;
    }

    /// @notice Emitted when a rebalance operation is executed
    event Rebalanced(
        address indexed token,
        address[] fromProtocols,
        address[] toProtocols,
        uint256[] amounts,
        uint256 newTotalAPY
    );

    /// @notice Emitted when a new protocol adapter is added
    event ProtocolAdded(address indexed adapter, string protocolName);

    /// @notice Emitted when a protocol adapter is removed
    event ProtocolRemoved(address indexed adapter, string protocolName);

    /// @notice Emitted when AI agent triggers a rebalance
    event AIRebalanceTriggered(
        address indexed token,
        uint256 expectedAPYImprovement
    );

    /**
     * @notice Add a new protocol adapter to the optimizer
     * @param adapter The protocol adapter contract address
     * @dev Weight is now calculated dynamically based on APY
     */
    function addProtocol(address adapter) external;

    /**
     * @notice Remove a protocol adapter from the optimizer
     * @param adapter The protocol adapter contract address
     */
    function removeProtocol(address adapter) external;

    /**
     * @notice Get the current allocation for a token across all protocols
     * @param token The token address
     * @return allocations Array of current allocations per protocol
     */
    function getCurrentAllocation(
        address token
    ) external view returns (AllocationTarget[] memory allocations);

    /**
     * @notice Get the weighted average APY for a token across all protocols
     * @param token The token address
     * @return weightedAPY The current weighted average APY
     */
    function getWeightedAPY(
        address token
    ) external view returns (uint256 weightedAPY);

    /**
     * @notice Calculate optimal allocation based on current APYs and constraints
     * @param token The token address
     * @param totalAmount The total amount to allocate
     * @return targets Optimal allocation targets
     */
    function calculateOptimalAllocation(
        address token,
        uint256 totalAmount
    ) external view returns (AllocationTarget[] memory targets);

    /**
     * @notice Execute a rebalance operation based on AI recommendations
     * @param params The rebalance parameters including targets and constraints
     */
    function executeRebalance(RebalanceParams calldata params) external;

    /**
     * @notice Deposit tokens and automatically allocate to optimal protocols
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares expected from the operation
     * @return shares Total shares received across all protocols
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external returns (uint256 shares);

    /**
     * @notice Withdraw tokens from optimal protocols to minimize impact
     * @param token The token to withdraw
     * @param shares The number of shares to burn
     * @param minAmount Minimum amount expected from the operation
     * @return amount Total amount received from withdrawals
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount
    ) external returns (uint256 amount);

    /**
     * @notice Harvest yield from all protocols for a given token
     * @param token The token to harvest yield for
     * @return totalYield Total yield harvested across all protocols
     */
    function harvestAll(address token) external returns (uint256 totalYield);

    /**
     * @notice Check if rebalancing would be profitable for a token
     * @param token The token address
     * @param minImprovementBps Minimum APY improvement required (in basis points)
     * @return shouldRebalance Whether rebalancing is recommended
     * @return expectedImprovement Expected APY improvement in basis points
     */
    function shouldRebalance(
        address token,
        uint256 minImprovementBps
    ) external view returns (bool shouldRebalance, uint256 expectedImprovement);

    /**
     * @notice Get total value locked across all protocols for a token
     * @param token The token address
     * @return totalTVL Combined TVL across all protocols
     */
    function getTotalTVL(
        address token
    ) external view returns (uint256 totalTVL);

    /**
     * @notice Get supported protocols for a given token
     * @param token The token address
     * @return adapters Array of protocol adapter addresses that support the token
     */
    function getSupportedProtocols(
        address token
    ) external view returns (address[] memory adapters);
}
