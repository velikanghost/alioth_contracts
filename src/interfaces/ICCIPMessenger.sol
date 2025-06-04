// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title ICCIPMessenger
 * @notice Interface for Chainlink CCIP cross-chain messaging
 * @dev Handles secure cross-chain communication for Alioth platform
 */
interface ICCIPMessenger {
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

    enum MessageType {
        YIELD_REBALANCE,
        LOAN_REQUEST,
        LOAN_APPROVAL,
        COLLATERAL_TRANSFER,
        LIQUIDATION_TRIGGER,
        PRICE_UPDATE
    }

    /// @notice Emitted when a cross-chain message is sent
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        address indexed receiver,
        MessageType messageType,
        uint256 fees
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

    /**
     * @notice Send a cross-chain message with optional token transfer
     * @param destinationChain Chainlink chain selector for destination
     * @param receiver Address of the receiver on destination chain
     * @param messageType Type of message being sent
     * @param data Encoded message data
     * @param token Token address to transfer (address(0) for no transfer)
     * @param amount Amount of tokens to transfer
     * @return messageId Unique identifier for the message
     */
    function sendMessage(
        uint64 destinationChain,
        address receiver,
        MessageType messageType,
        bytes calldata data,
        address token,
        uint256 amount
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Send a yield rebalance instruction to another chain
     * @param destinationChain Target chain for rebalance
     * @param yieldOptimizer Address of yield optimizer on destination chain
     * @param token Token to rebalance
     * @param amount Amount to rebalance
     * @param targetProtocol Target protocol for the funds
     * @return messageId Message identifier
     */
    function sendYieldRebalance(
        uint64 destinationChain,
        address yieldOptimizer,
        address token,
        uint256 amount,
        address targetProtocol
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
        uint256 duration
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Send collateral transfer for cross-chain loan
     * @param destinationChain Chain to send collateral to
     * @param lendingContract Lending contract on destination
     * @param token Collateral token
     * @param amount Amount of collateral
     * @param loanId Associated loan ID
     * @return messageId Message identifier
     */
    function sendCollateralTransfer(
        uint64 destinationChain,
        address lendingContract,
        address token,
        uint256 amount,
        uint256 loanId
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Send liquidation trigger to another chain
     * @param destinationChain Chain where liquidation should occur
     * @param lendingContract Lending contract address
     * @param loanId Loan ID to liquidate
     * @param maxCollateralSeized Maximum collateral to seize
     * @return messageId Message identifier
     */
    function sendLiquidationTrigger(
        uint64 destinationChain,
        address lendingContract,
        uint256 loanId,
        uint256 maxCollateralSeized
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Get the fee for sending a message to a destination chain
     * @param destinationChain Target chain selector
     * @param messageType Type of message
     * @param data Message data
     * @param token Token address (address(0) for no transfer)
     * @param amount Token amount
     * @return fee Required fee in native tokens
     */
    function getFee(
        uint64 destinationChain,
        MessageType messageType,
        bytes calldata data,
        address token,
        uint256 amount
    ) external view returns (uint256 fee);

    /**
     * @notice Check if a chain is supported for cross-chain operations
     * @param chainSelector Chainlink chain selector
     * @return supported Whether the chain is supported
     */
    function isSupportedChain(uint64 chainSelector) external view returns (bool supported);

    /**
     * @notice Get the last received message for a sender
     * @param sender Address of the sender
     * @return message The last message received from the sender
     */
    function getLastMessage(address sender) external view returns (CrossChainMessage memory message);

    /**
     * @notice Add support for a new destination chain
     * @param chainSelector Chainlink chain selector
     * @param routerAddress CCIP router address for the chain
     */
    function addSupportedChain(uint64 chainSelector, address routerAddress) external;

    /**
     * @notice Remove support for a destination chain
     * @param chainSelector Chainlink chain selector to remove
     */
    function removeSupportedChain(uint64 chainSelector) external;

    /**
     * @notice Update the gas limit for a specific message type
     * @param messageType Type of message
     * @param gasLimit New gas limit
     */
    function updateGasLimit(MessageType messageType, uint256 gasLimit) external;

    /**
     * @notice Withdraw fees collected from cross-chain operations
     * @param token Token to withdraw (address(0) for native)
     * @param amount Amount to withdraw
     * @param recipient Address to receive the funds
     */
    function withdrawFees(address token, uint256 amount, address recipient) external;
} 