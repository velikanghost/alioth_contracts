// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IProtocolAdapter
 * @notice Interface for protocol adapters that integrate with various DeFi protocols
 * @dev Each adapter handles interaction with a specific protocol (Aave, Compound, etc.)
 */
interface IProtocolAdapter {
    /// @notice Emitted when funds are deposited into the protocol
    event Deposited(address indexed token, uint256 amount, uint256 shares);

    /// @notice Emitted when funds are withdrawn from the protocol
    event Withdrawn(address indexed token, uint256 amount, uint256 shares);

    /// @notice Emitted when yield is harvested from the protocol
    event YieldHarvested(address indexed token, uint256 amount);

    /**
     * @notice Get the name of the protocol this adapter interfaces with
     * @return name The protocol name (e.g., "Aave V3", "Compound V2")
     */
    function protocolName() external pure returns (string memory name);

    /**
     * @notice Get the current Annual Percentage Yield for a token
     * @param token The token address
     * @return apy The current APY in basis points (e.g., 500 = 5%)
     */
    function getAPY(address token) external view returns (uint256 apy);

    /**
     * @notice Get the total value locked for a token in this protocol
     * @param token The token address
     * @return tvl The total value locked
     */
    function getTVL(address token) external view returns (uint256 tvl);

    /**
     * @notice Deposit tokens into the protocol
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares to receive (slippage protection)
     * @return shares The number of shares/tokens received from the protocol
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external payable returns (uint256 shares);

    /**
     * @notice Withdraw tokens from the protocol
     * @param token The token to withdraw
     * @param shares The number of shares to burn/redeem
     * @param minAmount Minimum amount to receive (slippage protection)
     * @return amount The amount of underlying tokens received
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount
    ) external returns (uint256 amount);

    /**
     * @notice Harvest yield/rewards from the protocol
     * @param token The token to harvest yield for
     * @return yield The amount of yield harvested
     */
    function harvestYield(address token) external returns (uint256 yield);

    /**
     * @notice Check if this adapter supports a given token
     * @param token The token address to check
     * @return supported True if the token is supported
     */
    function supportsToken(
        address token
    ) external view returns (bool supported);

    /**
     * @notice Get the current balance of shares for a token
     * @param token The token address
     * @return balance The current share balance
     */
    function getSharesBalance(
        address token
    ) external view returns (uint256 balance);

    /**
     * @notice Convert shares to underlying token amount
     * @param token The token address
     * @param shares The number of shares
     * @return amount The equivalent amount of underlying tokens
     */
    function sharesToTokens(
        address token,
        uint256 shares
    ) external view returns (uint256 amount);

    /**
     * @notice Convert token amount to shares
     * @param token The token address
     * @param amount The amount of tokens
     * @return shares The equivalent number of shares
     */
    function tokensToShares(
        address token,
        uint256 amount
    ) external view returns (uint256 shares);

    /**
     * @notice Check if protocol is currently operational
     * @param token The token address
     * @return isOperational True if protocol is fully operational
     * @return statusMessage Human readable status message
     */
    function getOperationalStatus(
        address token
    ) external view returns (bool isOperational, string memory statusMessage);

    /**
     * @notice Get protocol health metrics for risk assessment
     * @param token The token address
     * @return healthScore Overall protocol health score (0-10000)
     * @return liquidityDepth Available liquidity depth
     * @return utilizationRate Current utilization rate (0-10000)
     */
    function getHealthMetrics(
        address token
    )
        external
        view
        returns (
            uint256 healthScore,
            uint256 liquidityDepth,
            uint256 utilizationRate
        );

    /**
     * @notice Get protocol risk score for a token
     * @param token The token address
     * @return riskScore Risk score from 0 (lowest risk) to 10000 (highest risk)
     */
    function getRiskScore(
        address token
    ) external view returns (uint256 riskScore);

    /**
     * @notice Get maximum recommended allocation percentage for this protocol
     * @param token The token address
     * @return maxAllocation Maximum allocation in basis points (e.g., 5000 = 50%)
     */
    function getMaxRecommendedAllocation(
        address token
    ) external view returns (uint256 maxAllocation);
}
