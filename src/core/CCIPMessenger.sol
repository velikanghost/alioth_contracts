// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/ICCIPMessenger.sol";
import "../libraries/ValidationLib.sol";

/**
 * @title CCIPMessenger
 * @notice Chainlink CCIP cross-chain messaging for Alioth platform
 * @dev Implements defensive programming patterns and allowlisting as per CCIP best practices
 * Separates message reception from business logic to handle failures gracefully
 */
contract CCIPMessenger is
    ICCIPMessenger,
    CCIPReceiver,
    ReentrancyGuard,
    AccessControl,
    Pausable
{
    using SafeERC20 for IERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    /// @notice Role for authorized message senders
    bytes32 public constant SENDER_ROLE = keccak256("SENDER_ROLE");

    /// @notice Role for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Role for admin operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Maximum gas limit for cross-chain messages
    uint256 public constant MAX_GAS_LIMIT = 2000000;

    /// @notice Minimum gas limit for cross-chain messages
    uint256 public constant MIN_GAS_LIMIT = 200000;

    /// @notice LINK token for fee payments
    LinkTokenInterface public immutable i_linkToken;

    /// @notice Mapping of supported destination chains
    mapping(uint64 => ChainConfig) public chainConfigs;

    /// @notice Mapping of allowlisted source chains
    mapping(uint64 => bool) public allowlistedSourceChains;

    /// @notice Mapping of allowlisted senders
    mapping(address => bool) public allowlistedSenders;

    /// @notice Mapping of message type configurations
    mapping(MessageType => MessageTypeConfig) public messageTypeConfigs;

    /// @notice Mapping of sender to last message received
    mapping(address => CrossChainMessage) public lastMessages;

    /// @notice Mapping to track processed messages for deduplication
    mapping(bytes32 => bool) public processedMessages;

    /// @notice Mapping to track failed messages for retry
    mapping(bytes32 => uint256) public failedMessages;

    /// @notice Mapping to track retry counts
    mapping(bytes32 => uint256) public retryCount;

    /// @notice Fee collector address
    address public feeCollector;

    /// @notice Fee percentage in basis points (1% = 100)
    uint256 public feeRate = 100;

    /// @notice Custom errors for gas efficiency
    error ChainNotAllowlisted(uint64 chainSelector);
    error SenderNotAllowlisted(address sender);
    error MessageTypeDisabled(MessageType messageType);
    error InvalidGasLimit(uint256 gasLimit);
    error InsufficientFee(uint256 required, uint256 provided);
    error MessageAlreadyProcessed(bytes32 messageId);
    error MaxRetriesExceeded(bytes32 messageId);
    error OnlySelf();

    /// @notice Modifier to check if destination chain is allowlisted
    modifier onlyAllowlistedChain(uint64 chainSelector) {
        if (!chainConfigs[chainSelector].isSupported) {
            revert ChainNotAllowlisted(chainSelector);
        }
        _;
    }

    /// @notice Modifier to check if sender is allowlisted
    modifier onlyAllowlistedSender() {
        if (
            !allowlistedSenders[msg.sender] &&
            !hasRole(SENDER_ROLE, msg.sender) &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert SenderNotAllowlisted(msg.sender);
        }
        _;
    }

    /// @notice Modifier to check if message type is enabled
    modifier onlyEnabledMessageType(MessageType messageType) {
        if (!messageTypeConfigs[messageType].enabled) {
            revert MessageTypeDisabled(messageType);
        }
        _;
    }

    constructor(
        address _router,
        address _linkToken,
        address _feeCollector
    ) CCIPReceiver(_router) {
        _linkToken.validateAddress();
        _feeCollector.validateAddress();

        i_linkToken = LinkTokenInterface(_linkToken);
        feeCollector = _feeCollector;

        // Grant default admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
        _grantRole(SENDER_ROLE, msg.sender);

        // Initialize default message type configurations
        _initializeMessageTypeConfigs();
    }

    /**
     * @notice Initialize default configurations for message types
     */
    function _initializeMessageTypeConfigs() internal {
        messageTypeConfigs[MessageType.YIELD_REBALANCE] = MessageTypeConfig({
            gasLimit: 500000,
            enabled: true,
            maxRetries: 3
        });

        messageTypeConfigs[MessageType.LOAN_REQUEST] = MessageTypeConfig({
            gasLimit: 300000,
            enabled: true,
            maxRetries: 2
        });

        messageTypeConfigs[MessageType.LOAN_APPROVAL] = MessageTypeConfig({
            gasLimit: 200000,
            enabled: true,
            maxRetries: 2
        });

        messageTypeConfigs[
            MessageType.COLLATERAL_TRANSFER
        ] = MessageTypeConfig({gasLimit: 300000, enabled: true, maxRetries: 3});

        messageTypeConfigs[
            MessageType.LIQUIDATION_TRIGGER
        ] = MessageTypeConfig({gasLimit: 400000, enabled: true, maxRetries: 1});

        messageTypeConfigs[MessageType.PRICE_UPDATE] = MessageTypeConfig({
            gasLimit: 200000,
            enabled: true,
            maxRetries: 2
        });

        messageTypeConfigs[MessageType.EMERGENCY_STOP] = MessageTypeConfig({
            gasLimit: 150000,
            enabled: true,
            maxRetries: 1
        });

        messageTypeConfigs[MessageType.ADMIN_MESSAGE] = MessageTypeConfig({
            gasLimit: 250000,
            enabled: true,
            maxRetries: 2
        });
    }

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
    )
        external
        payable
        override
        onlyAllowlistedSender
        onlyAllowlistedChain(destinationChain)
        onlyEnabledMessageType(messageType)
        nonReentrant
        whenNotPaused
        returns (bytes32 messageId)
    {
        receiver.validateAddress();

        // Build CCIP message
        Client.EVM2AnyMessage memory message = _buildMessage(
            receiver,
            messageType,
            data,
            token,
            amount
        );

        // Calculate and validate fee
        uint256 fee = IRouterClient(i_ccipRouter).getFee(
            destinationChain,
            message
        );
        uint256 platformFee = ValidationLib.calculatePercentage(fee, feeRate);
        uint256 totalFee = fee + platformFee;

        if (payFeesIn == PayFeesIn.Native) {
            if (msg.value < totalFee) {
                revert InsufficientFee(totalFee, msg.value);
            }

            // Transfer platform fee to collector
            if (platformFee > 0) {
                payable(feeCollector).transfer(platformFee);
            }
        } else {
            // Pay with LINK
            i_linkToken.transferFrom(msg.sender, address(this), totalFee);
            i_linkToken.approve(i_ccipRouter, fee);

            // Transfer platform fee to collector
            if (platformFee > 0) {
                i_linkToken.transfer(feeCollector, platformFee);
            }
        }

        // Handle token transfer if specified
        if (token != address(0) && amount > 0) {
            amount.validateAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).forceApprove(i_ccipRouter, amount);
        }

        // Send message
        if (payFeesIn == PayFeesIn.Native) {
            messageId = IRouterClient(i_ccipRouter).ccipSend{value: fee}(
                destinationChain,
                message
            );
        } else {
            messageId = IRouterClient(i_ccipRouter).ccipSend(
                destinationChain,
                message
            );
        }

        emit MessageSent(
            messageId,
            destinationChain,
            receiver,
            messageType,
            fee,
            payFeesIn
        );

        if (token != address(0) && amount > 0) {
            emit TokensSent(
                messageId,
                destinationChain,
                token,
                amount,
                receiver
            );
        }

        return messageId;
    }

    /**
     * @notice Send a yield rebalance instruction to another chain
     */
    function sendYieldRebalance(
        uint64 destinationChain,
        address yieldOptimizer,
        address token,
        uint256 amount,
        address targetProtocol,
        PayFeesIn payFeesIn
    ) external payable override returns (bytes32 messageId) {
        bytes memory data = abi.encode(token, amount, targetProtocol);

        return
            this.sendMessage(
                destinationChain,
                yieldOptimizer,
                MessageType.YIELD_REBALANCE,
                data,
                address(0),
                0,
                payFeesIn
            );
    }

    /**
     * @notice Send a loan request to another chain
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
    ) external payable override returns (bytes32 messageId) {
        bytes memory data = abi.encode(
            msg.sender,
            collateralToken,
            borrowToken,
            collateralAmount,
            requestedAmount,
            maxRate,
            duration
        );

        return
            this.sendMessage(
                destinationChain,
                lendingContract,
                MessageType.LOAN_REQUEST,
                data,
                collateralToken,
                collateralAmount,
                payFeesIn
            );
    }

    /**
     * @notice Send collateral transfer for cross-chain loan
     */
    function sendCollateralTransfer(
        uint64 destinationChain,
        address lendingContract,
        address token,
        uint256 amount,
        uint256 loanId,
        PayFeesIn payFeesIn
    ) external payable override returns (bytes32 messageId) {
        bytes memory data = abi.encode(loanId, msg.sender);

        return
            this.sendMessage(
                destinationChain,
                lendingContract,
                MessageType.COLLATERAL_TRANSFER,
                data,
                token,
                amount,
                payFeesIn
            );
    }

    /**
     * @notice Get the fee for sending a message to a destination chain
     */
    function getFee(
        uint64 destinationChain,
        MessageType messageType,
        bytes calldata data,
        address token,
        uint256 amount,
        PayFeesIn payFeesIn
    ) external view override returns (uint256 fee) {
        if (!chainConfigs[destinationChain].isSupported) {
            revert ChainNotAllowlisted(destinationChain);
        }

        Client.EVM2AnyMessage memory message = _buildMessage(
            address(0), // placeholder receiver
            messageType,
            data,
            token,
            amount
        );

        fee = IRouterClient(i_ccipRouter).getFee(destinationChain, message);

        // Add platform fee
        uint256 platformFee = ValidationLib.calculatePercentage(fee, feeRate);
        return fee + platformFee;
    }

    /**
     * @notice Check if a chain is supported and allowlisted
     */
    function isSupportedChain(
        uint64 chainSelector
    ) external view override returns (bool) {
        return chainConfigs[chainSelector].isSupported;
    }

    /**
     * @notice Check if a sender is allowlisted
     */
    function isAllowlistedSender(
        address sender
    ) external view override returns (bool) {
        return
            allowlistedSenders[sender] ||
            hasRole(SENDER_ROLE, sender) ||
            hasRole(DEFAULT_ADMIN_ROLE, sender);
    }

    /**
     * @notice Get the last received message for a sender
     */
    function getLastMessage(
        address sender
    ) external view override returns (CrossChainMessage memory) {
        return lastMessages[sender];
    }

    /**
     * @notice Get chain configuration
     */
    function getChainConfig(
        uint64 chainSelector
    ) external view override returns (ChainConfig memory) {
        return chainConfigs[chainSelector];
    }

    /**
     * @notice Get message type configuration
     */
    function getMessageTypeConfig(
        MessageType messageType
    ) external view override returns (MessageTypeConfig memory) {
        return messageTypeConfigs[messageType];
    }

    /**
     * @notice Get retry count for a message
     */
    function getRetryCount(
        bytes32 messageId
    ) external view override returns (uint256) {
        return retryCount[messageId];
    }

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add or update support for a destination chain
     */
    function allowlistDestinationChain(
        uint64 chainSelector,
        address ccipRouter,
        uint256 gasLimit
    ) external override onlyRole(ADMIN_ROLE) {
        ccipRouter.validateAddress();
        if (gasLimit < MIN_GAS_LIMIT || gasLimit > MAX_GAS_LIMIT) {
            revert InvalidGasLimit(gasLimit);
        }

        chainConfigs[chainSelector] = ChainConfig({
            isSupported: true,
            ccipRouter: ccipRouter,
            gasLimit: gasLimit,
            allowlistEnabled: true
        });

        emit ChainAllowlisted(chainSelector, true);
    }

    /**
     * @notice Remove support for a destination chain
     */
    function denylistDestinationChain(
        uint64 chainSelector
    ) external override onlyRole(ADMIN_ROLE) {
        chainConfigs[chainSelector].isSupported = false;
        emit ChainAllowlisted(chainSelector, false);
    }

    /**
     * @notice Allow a sender to send messages through this contract
     */
    function allowlistSender(
        address sender,
        bool allowed
    ) external override onlyRole(ADMIN_ROLE) {
        sender.validateAddress();
        allowlistedSenders[sender] = allowed;
        emit SenderAllowlisted(sender, allowed);
    }

    /**
     * @notice Allow a source chain to send messages to this contract
     */
    function allowlistSourceChain(
        uint64 sourceChainSelector,
        bool allowed
    ) external override onlyRole(ADMIN_ROLE) {
        allowlistedSourceChains[sourceChainSelector] = allowed;
        emit ChainAllowlisted(sourceChainSelector, allowed);
    }

    /**
     * @notice Update message type configuration
     */
    function updateMessageTypeConfig(
        MessageType messageType,
        uint256 gasLimit,
        bool enabled,
        uint256 maxRetries
    ) external override onlyRole(ADMIN_ROLE) {
        if (gasLimit < MIN_GAS_LIMIT || gasLimit > MAX_GAS_LIMIT) {
            revert InvalidGasLimit(gasLimit);
        }

        messageTypeConfigs[messageType] = MessageTypeConfig({
            gasLimit: gasLimit,
            enabled: enabled,
            maxRetries: maxRetries
        });
    }

    /**
     * @notice Set the LINK token address for fee payments
     */
    function setLinkToken(
        address linkToken
    ) external override onlyRole(ADMIN_ROLE) {
        // Note: LINK token is immutable in this implementation
        // This function is kept for interface compatibility
        revert("LINK token is immutable");
    }

    /**
     * @notice Withdraw fees collected from cross-chain operations
     */
    function withdrawFees(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyRole(ADMIN_ROLE) {
        recipient.validateAddress();
        amount.validateAmount();

        if (token == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /**
     * @notice Emergency stop functionality
     */
    function setEmergencyStop(
        bool active
    ) external override onlyRole(EMERGENCY_ROLE) {
        if (active) {
            _pause();
        } else {
            _unpause();
        }
        emit EmergencyStopActivated(active);
    }

    /**
     * @notice Emergency withdraw function for stuck funds
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyRole(EMERGENCY_ROLE) {
        require(paused(), "Emergency stop not active");
        recipient.validateAddress();
        amount.validateAmount();

        if (token == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /**
     * @notice Retry a failed message manually
     */
    function retryFailedMessage(
        bytes32 messageId,
        uint256 newGasLimit
    ) external override onlyRole(ADMIN_ROLE) {
        if (failedMessages[messageId] == 0) {
            revert("Message not failed");
        }

        if (retryCount[messageId] >= 3) {
            revert MaxRetriesExceeded(messageId);
        }

        retryCount[messageId]++;

        // Implementation would retry the message with new gas limit
        // For now, just mark as retried
        delete failedMessages[messageId];
    }

    // ===== CCIP RECEIVER IMPLEMENTATION =====

    /**
     * @notice Handle received CCIP messages
     * @dev Implements defensive programming - separates reception from business logic
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        // Check if source chain is allowlisted
        if (!allowlistedSourceChains[any2EvmMessage.sourceChainSelector]) {
            emit MessageFailed(
                any2EvmMessage.messageId,
                "Source chain not allowlisted"
            );
            return;
        }

        bytes32 messageId = any2EvmMessage.messageId;

        // Prevent duplicate processing
        if (processedMessages[messageId]) {
            revert MessageAlreadyProcessed(messageId);
        }
        processedMessages[messageId] = true;

        // Decode sender and check if allowlisted
        address sender = abi.decode(any2EvmMessage.sender, (address));
        if (!allowlistedSenders[sender]) {
            emit MessageFailed(messageId, "Sender not allowlisted");
            return;
        }

        // Decode message type from first bytes
        (MessageType messageType, bytes memory actualData) = abi.decode(
            any2EvmMessage.data,
            (MessageType, bytes)
        );

        // Check if message type is enabled
        if (!messageTypeConfigs[messageType].enabled) {
            emit MessageFailed(messageId, "Message type disabled");
            return;
        }

        // Store message info
        CrossChainMessage memory message = CrossChainMessage({
            sourceChain: any2EvmMessage.sourceChainSelector,
            destinationChain: uint64(block.chainid),
            sender: sender,
            receiver: address(this),
            data: actualData,
            token: any2EvmMessage.destTokenAmounts.length > 0
                ? any2EvmMessage.destTokenAmounts[0].token
                : address(0),
            amount: any2EvmMessage.destTokenAmounts.length > 0
                ? any2EvmMessage.destTokenAmounts[0].amount
                : 0,
            messageId: messageId,
            timestamp: block.timestamp
        });

        lastMessages[sender] = message;

        // Process message with defensive pattern
        bool success = _processMessage(message, messageType);

        emit MessageReceived(
            messageId,
            message.sourceChain,
            sender,
            messageType,
            success
        );

        if (message.token != address(0) && message.amount > 0) {
            emit TokensReceived(
                messageId,
                message.sourceChain,
                message.token,
                message.amount,
                message.receiver
            );
        }

        if (!success) {
            failedMessages[messageId] = block.timestamp;
        }
    }

    /**
     * @notice Process different types of received messages
     * @dev Uses defensive programming - doesn't revert on failure
     */
    function _processMessage(
        CrossChainMessage memory message,
        MessageType messageType
    ) internal returns (bool success) {
        try this._handleMessage(message, messageType) {
            return true;
        } catch (bytes memory reason) {
            emit MessageFailed(message.messageId, reason);
            return false;
        }
    }

    /**
     * @notice External function to handle messages (allows try-catch)
     */
    function _handleMessage(
        CrossChainMessage memory message,
        MessageType messageType
    ) external {
        if (msg.sender != address(this)) {
            revert OnlySelf();
        }

        if (messageType == MessageType.YIELD_REBALANCE) {
            _handleYieldRebalance(message);
        } else if (messageType == MessageType.LOAN_REQUEST) {
            _handleLoanRequest(message);
        } else if (messageType == MessageType.LOAN_APPROVAL) {
            _handleLoanApproval(message);
        } else if (messageType == MessageType.COLLATERAL_TRANSFER) {
            _handleCollateralTransfer(message);
        } else if (messageType == MessageType.LIQUIDATION_TRIGGER) {
            _handleLiquidationTrigger(message);
        } else if (messageType == MessageType.PRICE_UPDATE) {
            _handlePriceUpdate(message);
        } else if (messageType == MessageType.EMERGENCY_STOP) {
            _handleEmergencyStop(message);
        } else if (messageType == MessageType.ADMIN_MESSAGE) {
            _handleAdminMessage(message);
        }
    }

    // ===== INTERNAL MESSAGE HANDLERS =====

    function _handleYieldRebalance(CrossChainMessage memory message) internal {
        // Implementation would call yield optimizer contract
        // For now, just emit event showing message was received
    }

    function _handleLoanRequest(CrossChainMessage memory message) internal {
        // Implementation would call lending contract
        // For now, just emit event showing message was received
    }

    function _handleLoanApproval(CrossChainMessage memory message) internal {
        // Implementation would call lending contract
        // For now, just emit event showing message was received
    }

    function _handleCollateralTransfer(
        CrossChainMessage memory message
    ) internal {
        // Implementation would call lending contract
        // For now, just emit event showing message was received
    }

    function _handleLiquidationTrigger(
        CrossChainMessage memory message
    ) internal {
        // Implementation would call lending contract
        // For now, just emit event showing message was received
    }

    function _handlePriceUpdate(CrossChainMessage memory message) internal {
        // Implementation would update price oracles
        // For now, just emit event showing message was received
    }

    function _handleEmergencyStop(CrossChainMessage memory message) internal {
        // Implementation would trigger emergency stop mechanisms
        // For now, just emit event showing message was received
    }

    function _handleAdminMessage(CrossChainMessage memory message) internal {
        // Implementation would handle admin-specific messages
        // For now, just emit event showing message was received
    }

    // ===== INTERNAL HELPER FUNCTIONS =====

    function _buildMessage(
        address receiver,
        MessageType messageType,
        bytes calldata data,
        address token,
        uint256 amount
    ) internal view returns (Client.EVM2AnyMessage memory) {
        // Prepare token amounts array
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](
                token != address(0) && amount > 0 ? 1 : 0
            );

        if (token != address(0) && amount > 0) {
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: token,
                amount: amount
            });
        }

        // Encode message type with data
        bytes memory messageData = abi.encode(messageType, data);

        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(receiver),
                data: messageData,
                tokenAmounts: tokenAmounts,
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({
                        gasLimit: messageTypeConfigs[messageType].gasLimit
                    })
                ),
                feeToken: address(0) // Will be set based on PayFeesIn parameter
            });
    }

    // ===== UTILITY FUNCTIONS =====

    /**
     * @notice Set fee rate for platform fees
     */
    function setFeeRate(uint256 _feeRate) external onlyRole(ADMIN_ROLE) {
        require(_feeRate <= 1000, "Fee rate too high"); // Max 10%
        feeRate = _feeRate;
    }

    /**
     * @notice Set fee collector address
     */
    function setFeeCollector(
        address _feeCollector
    ) external onlyRole(ADMIN_ROLE) {
        _feeCollector.validateAddress();
        feeCollector = _feeCollector;
    }

    /**
     * @notice Allow contract to receive native tokens
     */
    receive() external payable {}

    /**
     * @notice Fallback function
     */
    fallback() external payable {}

    /**
     * @notice Supports interface function required by multiple inheritance
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, CCIPReceiver) returns (bool) {
        return
            interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
