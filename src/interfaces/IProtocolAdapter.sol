// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IProtocolAdapter
 * @notice Interface for protocol adapters that integrate with various DeFi protocols
 * @dev Provides a uniform interface for interacting with different yield-generating protocols
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
     * @return The protocol name (e.g., "Aave", "Compound", "Yearn")
     */
    function protocolName() external view returns (string memory);

    /**
     * @notice Get the current APY for a given token
     * @param token The token address to check APY for
     * @return apy The current annual percentage yield (in basis points, e.g., 500 = 5%)
     */
    function getAPY(address token) external view returns (uint256 apy);

    /**
     * @notice Get the current TVL for a given token in this protocol
     * @param token The token address to check TVL for
     * @return tvl The total value locked for this token
     */
    function getTVL(address token) external view returns (uint256 tvl);

    /**
     * @notice Deposit tokens into the protocol
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares expected to prevent slippage
     * @return shares The number of shares received
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external payable returns (uint256 shares);

    /**
     * @notice Withdraw tokens from the protocol
     * @param token The token to withdraw
     * @param shares The number of shares to burn
     * @param minAmount Minimum amount expected to prevent slippage
     * @return amount The amount of tokens received
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount
    ) external returns (uint256 amount);

    /**
     * @notice Harvest yield from the protocol
     * @param token The token to harvest yield for
     * @return yieldAmount The amount of yield harvested
     */
    function harvestYield(address token) external returns (uint256 yieldAmount);

    /**
     * @notice Check if the protocol supports a given token
     * @param token The token address to check
     * @return supported True if the token is supported
     */
    function supportsToken(
        address token
    ) external view returns (bool supported);

    /**
     * @notice Get the shares balance for a given token
     * @param token The token address
     * @return shares The current shares balance
     */
    function getSharesBalance(
        address token
    ) external view returns (uint256 shares);

    /**
     * @notice Convert shares to underlying token amount
     * @param token The token address
     * @param shares The number of shares
     * @return amount The equivalent token amount
     */
    function sharesToTokens(
        address token,
        uint256 shares
    ) external view returns (uint256 amount);

    /**
     * @notice Convert token amount to shares
     * @param token The token address
     * @param amount The token amount
     * @return shares The equivalent number of shares
     */
    function tokensToShares(
        address token,
        uint256 amount
    ) external view returns (uint256 shares);
}
