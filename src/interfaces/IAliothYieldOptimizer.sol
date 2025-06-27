// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IAliothYieldOptimizer
 * @notice Interface for the AI-driven Alioth Yield Optimizer
 * @dev Used by AliothVault to interact with the optimizer
 */
interface IAliothYieldOptimizer {
    // ===== CORE OPTIMIZATION FUNCTIONS =====

    /**
     * @notice Core function called by authorized vaults for single protocol deposits
     * @param token Token address to deposit
     * @param amount Amount to deposit
     * @param protocol Target protocol string ("aave", "compound", "yearn")
     * @param beneficiary User address to credit
     * @return optimizationId Generated optimization ID
     */
    function executeSingleOptimizedDeposit(
        address token,
        uint256 amount,
        string calldata protocol,
        address beneficiary
    ) external returns (uint256 optimizationId);

    /**
     * @notice Validate deposit with Chainlink feeds
     * @param token Token to validate
     * @param amount Amount to validate
     * @param protocol Target protocol
     * @return isValid Whether validation passed
     */
    function validateDepositWithChainlink(
        address token,
        uint256 amount,
        string calldata protocol
    ) external view returns (bool isValid);

    /**
     * @notice Execute withdrawal from a specific protocol
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     * @param protocol Target protocol string ("aave", "compound", "yearn")
     * @param beneficiary User address to send tokens to
     * @return withdrawnAmount The actual amount withdrawn
     */
    function executeWithdrawal(
        address token,
        uint256 amount,
        string calldata protocol,
        address beneficiary
    ) external returns (uint256 withdrawnAmount);

    // ===== VAULT AUTHORIZATION FUNCTIONS =====

    /**
     * @notice Authorize a vault contract to call deposit functions
     * @param vault Address of the vault contract
     */
    function authorizeVault(address vault) external;

    /**
     * @notice Revoke vault authorization
     * @param vault Address of the vault contract
     */
    function revokeVault(address vault) external;

    // ===== AI BACKEND AUTHORIZATION FUNCTIONS =====

    /**
     * @notice Authorize an AI backend service for automation
     * @param aiBackend Address of the AI backend service
     */
    function authorizeAIBackend(address aiBackend) external;

    /**
     * @notice Revoke AI backend authorization
     * @param aiBackend Address of the AI backend service
     */
    function revokeAIBackend(address aiBackend) external;

    // ===== PROTOCOL MANAGEMENT =====

    /**
     * @notice Add a new protocol adapter to the optimizer
     * @param adapter The protocol adapter contract address
     */
    function addProtocol(address adapter) external;

    /**
     * @notice Remove a protocol adapter from the optimizer
     * @param adapter The protocol adapter contract address
     */
    function removeProtocol(address adapter) external;

    // ===== VIEW FUNCTIONS =====

    /**
     * @notice Check if an address is an authorized AI backend
     * @param backend Address to check
     * @return isAuthorized Whether the address is authorized
     */
    function authorizedAIBackends(
        address backend
    ) external view returns (bool isAuthorized);

    /**
     * @notice Get optimization data by ID
     * @param optimizationId ID of the optimization
     * @return user User address
     * @return token Token address
     * @return amount Amount deposited
     * @return protocol Protocol used (0=AAVE, 1=COMPOUND, 2=YEARN)
     * @return shares Shares received
     * @return timestamp Creation timestamp
     * @return lastRebalance Last rebalance timestamp
     * @return automationId Automation ID
     * @return rebalanceCount Number of rebalances
     * @return status Optimization status (0=ACTIVE, 1=PAUSED, 2=WITHDRAWN)
     */
    function optimizations(
        uint256 optimizationId
    )
        external
        view
        returns (
            address user,
            address token,
            uint256 amount,
            uint8 protocol,
            uint256 shares,
            uint256 timestamp,
            uint256 lastRebalance,
            uint256 automationId,
            uint256 rebalanceCount,
            uint8 status
        );

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Update rebalance parameters
     * @param _rebalanceInterval New rebalance interval in seconds
     * @param _rebalanceThreshold New rebalance threshold in basis points
     */
    function updateRebalanceParams(
        uint256 _rebalanceInterval,
        uint256 _rebalanceThreshold
    ) external;

    /**
     * @notice Emergency stop toggle
     */
    function setEmergencyStop(bool _emergencyStop) external;

    // ===== EVENTS =====

    event OptimizationExecuted(
        uint256 indexed optimizationId,
        address indexed beneficiary,
        address token,
        uint256 amount,
        string protocol,
        uint256 automationId
    );

    event AutomatedRebalanceExecuted(
        uint256 indexed optimizationId,
        uint256 expectedYield,
        uint256 timestamp
    );

    event AIAgentAuthorized(address indexed agent);
    event AIAgentRevoked(address indexed agent);
    event VaultAuthorized(address indexed vault);
    event VaultRevoked(address indexed vault);
    event RebalanceParamsUpdated(uint256 interval, uint256 threshold);
    event ProtocolAdded(address indexed adapter, string name);
    event ProtocolRemoved(address indexed adapter, string name);
}
