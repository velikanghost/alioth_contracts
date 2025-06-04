// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title ICCIPMessenger
 * @notice Interface for Chainlink CCIP cross-chain messaging
 * @dev Handles secure cross-chain communication for Alioth platform
 * Based on Chainlink CCIP best practices and defensive programming patterns
 */
interface ICCIPMessenger {
    /// @notice Struct to hold cross-chain message data
    struct CrossChainMessage {
        uint64 sourceChain;
        uint64 destinationChain;
        address sender;
        address receiver;
        bytes data;
        address token;
        uint256 amount;
        bytes32 messageId;
        uint256 timestamp;
    }

    /// @notice Enum for different message types supported by the system
    enum MessageType {
        YIELD_REBALANCE,
        LOAN_REQUEST,
        LOAN_APPROVAL,
        COLLATERAL_TRANSFER,
        LIQUIDATION_TRIGGER,
        PRICE_UPDATE,
        EMERGENCY_STOP,
        ADMIN_MESSAGE
    }

    /// @notice Payment options for CCIP fees
    enum PayFeesIn {
        Native,
        LINK
    }

    /// @notice Configuration for each supported chain
    struct ChainConfig {
        bool isSupported;
        address ccipRouter;
        uint256 gasLimit;
        bool allowlistEnabled;
    }

    /// @notice Configuration for message types
    struct MessageTypeConfig {
        uint256 gasLimit;
        bool enabled;
        uint256 maxRetries;
    }

    // ===== EVENTS =====

    /// @notice Emitted when a cross-chain message is sent
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        address indexed receiver,
        MessageType messageType,
        uint256 fees,
        PayFeesIn payFeesIn
    );

    /// @notice Emitted when a cross-chain message is received
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChain,
        address indexed sender,
        MessageType messageType,
        bool success
    );

    /// @notice Emitted when tokens are sent cross-chain
    event TokensSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        address indexed token,
        uint256 amount,
        address receiver
    );

    /// @notice Emitted when tokens are received cross-chain
    event TokensReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChain,
        address indexed token,
        uint256 amount,
        address receiver
    );

    /// @notice Emitted when a chain is allowlisted
    event ChainAllowlisted(uint64 indexed chainSelector, bool allowed);

    /// @notice Emitted when a sender is allowlisted
    event SenderAllowlisted(address indexed sender, bool allowed);

    /// @notice Emitted when message processing fails
    event MessageFailed(bytes32 indexed messageId, bytes reason);

    /// @notice Emitted when emergency stop is triggered
    event EmergencyStopActivated(bool active);

    // ===== CORE MESSAGING FUNCTIONS =====

    /**
     * @notice Send a cross-chain message with optional token transfer
     * @param destinationChain Chainlink chain selector for destination
     * @param receiver Address of the receiver on destination chain
     * @param messageType Type of message being sent
     * @param data Encoded message data
     * @param token Token address to transfer (address(0) for no transfer)
     * @param amount Amount of tokens to transfer
     * @param payFeesIn How to pay CCIP fees (Native or LINK)
     * @return messageId Unique identifier for the message
     */
    function sendMessage(
        uint64 destinationChain,
        address receiver,
        MessageType messageType,
        bytes calldata data,
        address token,
        uint256 amount,
        PayFeesIn payFeesIn
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Send a yield rebalance instruction to another chain
     * @param destinationChain Target chain for rebalance
     * @param yieldOptimizer Address of yield optimizer on destination chain
     * @param token Token to rebalance
     * @param amount Amount to rebalance
     * @param targetProtocol Target protocol for the funds
     * @param payFeesIn How to pay CCIP fees
     * @return messageId Message identifier
     */
    function sendYieldRebalance(
        uint64 destinationChain,
        address yieldOptimizer,
        address token,
        uint256 amount,
        address targetProtocol,
        PayFeesIn payFeesIn
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Send a loan request to another chain
     * @param destinationChain Chain where the loan will be processed
     * @param lendingContract Address of lending contract on destination
     * @param collateralToken Collateral token address
     * @param borrowToken Borrow token address
     * @param collateralAmount Amount of collateral
     * @param requestedAmount Requested loan amount
     * @param maxRate Maximum acceptable interest rate
     * @param duration Loan duration
     * @param payFeesIn How to pay CCIP fees
     * @return messageId Message identifier
     */
    function sendLoanRequest(
        uint64 destinationChain,
        address lendingContract,
        address collateralToken,
        address borrowToken,
        uint256 collateralAmount,
        uint256 requestedAmount,
        uint256 maxRate,
        uint256 duration,
        PayFeesIn payFeesIn
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Send collateral transfer for cross-chain loan
     * @param destinationChain Chain to send collateral to
     * @param lendingContract Lending contract on destination
     * @param token Collateral token
     * @param amount Amount of collateral
     * @param loanId Associated loan ID
     * @param payFeesIn How to pay CCIP fees
     * @return messageId Message identifier
     */
    function sendCollateralTransfer(
        uint64 destinationChain,
        address lendingContract,
        address token,
        uint256 amount,
        uint256 loanId,
        PayFeesIn payFeesIn
    ) external payable returns (bytes32 messageId);

    // ===== VIEW FUNCTIONS =====

    /**
     * @notice Get the fee for sending a message to a destination chain
     * @param destinationChain Target chain selector
     * @param messageType Type of message
     * @param data Message data
     * @param token Token address (address(0) for no transfer)
     * @param amount Token amount
     * @param payFeesIn How fees will be paid
     * @return fee Required fee amount
     */
    function getFee(
        uint64 destinationChain,
        MessageType messageType,
        bytes calldata data,
        address token,
        uint256 amount,
        PayFeesIn payFeesIn
    ) external view returns (uint256 fee);

    /**
     * @notice Check if a chain is supported and allowlisted
     * @param chainSelector Chainlink chain selector
     * @return supported Whether the chain is supported
     */
    function isSupportedChain(
        uint64 chainSelector
    ) external view returns (bool supported);

    /**
     * @notice Check if a sender is allowlisted
     * @param sender Address to check
     * @return allowed Whether the sender is allowlisted
     */
    function isAllowlistedSender(
        address sender
    ) external view returns (bool allowed);

    /**
     * @notice Get the last received message for a sender
     * @param sender Address of the sender
     * @return message The last message received from the sender
     */
    function getLastMessage(
        address sender
    ) external view returns (CrossChainMessage memory message);

    /**
     * @notice Get chain configuration
     * @param chainSelector Chain selector
     * @return config Chain configuration
     */
    function getChainConfig(
        uint64 chainSelector
    ) external view returns (ChainConfig memory config);

    /**
     * @notice Get message type configuration
     * @param messageType Message type
     * @return config Message type configuration
     */
    function getMessageTypeConfig(
        MessageType messageType
    ) external view returns (MessageTypeConfig memory config);

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add or update support for a destination chain
     * @param chainSelector Chainlink chain selector
     * @param ccipRouter CCIP router address for the chain
     * @param gasLimit Default gas limit for messages to this chain
     */
    function allowlistDestinationChain(
        uint64 chainSelector,
        address ccipRouter,
        uint256 gasLimit
    ) external;

    /**
     * @notice Remove support for a destination chain
     * @param chainSelector Chainlink chain selector to remove
     */
    function denylistDestinationChain(uint64 chainSelector) external;

    /**
     * @notice Allow a sender to send messages through this contract
     * @param sender Address to allowlist
     * @param allowed Whether to allow or deny
     */
    function allowlistSender(address sender, bool allowed) external;

    /**
     * @notice Allow a source chain to send messages to this contract
     * @param sourceChainSelector Source chain selector
     * @param allowed Whether to allow or deny
     */
    function allowlistSourceChain(
        uint64 sourceChainSelector,
        bool allowed
    ) external;

    /**
     * @notice Update gas limit for a specific message type
     * @param messageType Type of message
     * @param gasLimit New gas limit
     */
    function updateMessageTypeConfig(
        MessageType messageType,
        uint256 gasLimit,
        bool enabled,
        uint256 maxRetries
    ) external;

    /**
     * @notice Set the LINK token address for fee payments
     * @param linkToken LINK token contract address
     */
    function setLinkToken(address linkToken) external;

    /**
     * @notice Withdraw fees collected from cross-chain operations
     * @param token Token to withdraw (address(0) for native)
     * @param amount Amount to withdraw
     * @param recipient Address to receive the funds
     */
    function withdrawFees(
        address token,
        uint256 amount,
        address recipient
    ) external;

    /**
     * @notice Emergency stop functionality
     * @param active Whether to activate emergency stop
     */
    function setEmergencyStop(bool active) external;

    /**
     * @notice Emergency withdraw function for stuck funds
     * @param token Token to withdraw (address(0) for native)
     * @param amount Amount to withdraw
     * @param recipient Recipient address
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external;

    // ===== RETRY FUNCTIONALITY =====

    /**
     * @notice Retry a failed message manually
     * @param messageId Failed message ID
     * @param newGasLimit New gas limit for retry
     */
    function retryFailedMessage(
        bytes32 messageId,
        uint256 newGasLimit
    ) external;

    /**
     * @notice Get retry count for a message
     * @param messageId Message ID
     * @return retryCount Number of retries attempted
     */
    function getRetryCount(
        bytes32 messageId
    ) external view returns (uint256 retryCount);
}
