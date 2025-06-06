// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IYieldOptimizer.sol";

/**
 * @title IAliothMultiAssetVault
 * @notice Interface for the Alioth Multi-Asset Vault
 * @dev Defines the interface for managing multiple token positions in a single vault
 */
interface IAliothMultiAssetVault {
    // ===== STRUCTS =====

    struct UserPosition {
        uint256 shares; // User's share amount
        uint256 lastDepositTime; // Last deposit timestamp
        uint256 totalDeposited; // Total amount ever deposited
        uint256 totalWithdrawn; // Total amount ever withdrawn
    }

    struct TokenInfo {
        bool isSupported; // Whether token is supported
        uint256 totalShares; // Total shares for this token
        uint256 totalDeposits; // Total deposits ever made
        uint256 totalWithdrawals; // Total withdrawals ever made
        uint256 minDeposit; // Minimum deposit amount
        uint256 maxDeposit; // Maximum deposit amount (0 = no limit)
        string symbol; // Cached symbol for display
    }

    // ===== EVENTS =====

    event TokenDeposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event TokenWithdraw(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);
    event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event YieldHarvested(address indexed token, uint256 amount);

    // ===== CORE FUNCTIONS =====

    /**
     * @notice Deposit tokens and receive shares in the optimized yield strategies
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares expected (slippage protection)
     * @return shares The number of shares received
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external returns (uint256 shares);

    /**
     * @notice Withdraw tokens by burning shares
     * @param token The token to withdraw
     * @param shares The number of shares to burn
     * @param minAmount Minimum amount expected (slippage protection)
     * @return amount The amount of tokens received
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount
    ) external returns (uint256 amount);

    /**
     * @notice Harvest yield for a specific token
     * @param token The token to harvest yield for
     * @return totalYield Total yield harvested
     */
    function harvestYield(address token) external returns (uint256 totalYield);

    /**
     * @notice Harvest yield for all supported tokens
     * @return totalYields Array of yields harvested per token
     */
    function harvestAllTokens() external returns (uint256[] memory totalYields);

    // ===== VIEW FUNCTIONS =====

    /**
     * @notice Get user's position for a specific token
     * @param user The user address
     * @param token The token address
     * @return shares User's shares
     * @return value Current value in underlying token
     * @return apy Current APY for the token
     */
    function getUserPosition(
        address user,
        address token
    ) external view returns (uint256 shares, uint256 value, uint256 apy);

    /**
     * @notice Get all user positions across all tokens
     * @param user The user address
     * @return tokens Array of token addresses
     * @return shares Array of share amounts
     * @return values Array of current values
     * @return symbols Array of token symbols
     * @return apys Array of current APYs
     */
    function getUserPortfolio(
        address user
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols,
            uint256[] memory apys
        );

    /**
     * @notice Get vault stats for a specific token
     * @param token The token address
     * @return totalShares Total shares for the token
     * @return totalValue Total value locked
     * @return apy Current weighted APY
     * @return userCount Number of users with positions
     */
    function getTokenStats(
        address token
    )
        external
        view
        returns (
            uint256 totalShares,
            uint256 totalValue,
            uint256 apy,
            uint256 userCount
        );

    /**
     * @notice Get current allocation for a token across protocols
     * @param token The token address
     * @return allocations Array of current allocations per protocol
     */
    function getTokenAllocation(
        address token
    )
        external
        view
        returns (IYieldOptimizer.AllocationTarget[] memory allocations);

    /**
     * @notice Preview how many shares would be received for a deposit
     * @param token The token address
     * @param amount The deposit amount
     * @return shares Expected shares to receive
     */
    function previewDeposit(
        address token,
        uint256 amount
    ) external view returns (uint256 shares);

    /**
     * @notice Preview how much amount would be received for a withdrawal
     * @param token The token address
     * @param shares The number of shares to withdraw
     * @return amount Expected amount to receive
     */
    function previewWithdraw(
        address token,
        uint256 shares
    ) external view returns (uint256 amount);

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add support for a new token
     * @param token The token address
     * @param minDeposit Minimum deposit amount
     * @param maxDeposit Maximum deposit amount (0 = no limit)
     */
    function addToken(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external;

    /**
     * @notice Remove support for a token (only if no active positions)
     * @param token The token address
     */
    function removeToken(address token) external;

    /**
     * @notice Set deposit fee (only owner)
     * @param newFee New deposit fee in basis points
     */
    function setDepositFee(uint256 newFee) external;

    /**
     * @notice Set withdrawal fee (only owner)
     * @param newFee New withdrawal fee in basis points
     */
    function setWithdrawalFee(uint256 newFee) external;

    /**
     * @notice Set fee recipient (only owner)
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external;

    /**
     * @notice Update token limits
     * @param token The token address
     * @param minDeposit New minimum deposit
     * @param maxDeposit New maximum deposit (0 = no limit)
     */
    function updateTokenLimits(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external;

    // ===== UTILITY FUNCTIONS =====

    /**
     * @notice Get all supported tokens
     * @return tokens Array of supported token addresses
     */
    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens);

    /**
     * @notice Check if a token is supported
     * @param token The token address
     * @return supported Whether the token is supported
     */
    function isTokenSupported(
        address token
    ) external view returns (bool supported);

    /**
     * @notice Get the total number of supported tokens
     * @return count Number of supported tokens
     */
    function getSupportedTokenCount() external view returns (uint256 count);

    /**
     * @notice Get the underlying YieldOptimizer contract
     * @return optimizer The YieldOptimizer contract address
     */
    function yieldOptimizer() external view returns (IYieldOptimizer optimizer);

    /**
     * @notice Get position data for a user and token
     * @param token The token address
     * @param user The user address
     * @return position The user's position data
     */
    function positions(
        address token,
        address user
    ) external view returns (UserPosition memory position);

    /**
     * @notice Get token information
     * @param token The token address
     * @return isSupported Whether the token is supported
     * @return totalShares Total shares for this token
     * @return totalDeposits Total deposits ever made
     * @return totalWithdrawals Total withdrawals ever made
     * @return minDeposit Minimum deposit amount
     * @return maxDeposit Maximum deposit amount (0 = no limit)
     * @return symbol Cached symbol for display
     */
    function tokenInfo(
        address token
    )
        external
        view
        returns (
            bool isSupported,
            uint256 totalShares,
            uint256 totalDeposits,
            uint256 totalWithdrawals,
            uint256 minDeposit,
            uint256 maxDeposit,
            string memory symbol
        );

    /**
     * @notice Get fee information
     * @return depositFee Current deposit fee in basis points
     * @return withdrawalFee Current withdrawal fee in basis points
     * @return feeRecipient Address that receives fees
     */
    function getFeeInfo()
        external
        view
        returns (
            uint256 depositFee,
            uint256 withdrawalFee,
            address feeRecipient
        );
}
