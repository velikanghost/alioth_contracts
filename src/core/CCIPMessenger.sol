// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/utils/ReentrancyGuard.sol";
import "../interfaces/ICCIPMessenger.sol";
import "../libraries/ValidationLib.sol";

/**
 * @title CCIPMessenger
 * @notice Chainlink CCIP cross-chain messaging for Alioth platform
 * @dev Handles secure cross-chain communication and token transfers
 */
contract CCIPMessenger is ICCIPMessenger, CCIPReceiver, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    /// @notice Role for authorized message senders
    bytes32 public constant SENDER_ROLE = keccak256("SENDER_ROLE");
    
    /// @notice Role for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Maximum gas limit for cross-chain messages
    uint256 public constant MAX_GAS_LIMIT = 2000000;
    
    /// @notice Minimum gas limit for cross-chain messages
    uint256 public constant MIN_GAS_LIMIT = 200000;

    /// @notice Mapping of supported destination chains
    mapping(uint64 => bool) public supportedChains;
    
    /// @notice Mapping of message type to gas limits
    mapping(MessageType => uint256) public gasLimits;
    
    /// @notice Mapping of sender to last message received
    mapping(address => CrossChainMessage) public lastMessages;
    
    /// @notice Mapping to track message IDs for deduplication
    mapping(bytes32 => bool) public processedMessages;
    
    /// @notice Administrator address
    address public admin;
    
    /// @notice Emergency stop flag
    bool public emergencyStop;
    
    /// @notice Fee collector address
    address public feeCollector;
    
    /// @notice Fee percentage in basis points
    uint256 public feeRate = 100; // 1%

    /// @notice Simple role checking (replace with OpenZeppelin AccessControl in production)
    mapping(bytes32 => mapping(address => bool)) private roles;

    /// @notice Modifier to restrict access to admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    /// @notice Modifier to check if emergency stop is not active
    modifier whenNotStopped() {
        require(!emergencyStop, "Emergency stopped");
        _;
    }

    /// @notice Modifier to restrict access to authorized senders
    modifier onlySender() {
        require(msg.sender == admin || hasRole(SENDER_ROLE, msg.sender), "Not authorized sender");
        _;
    }

    constructor(
        address _router,
        address _admin,
        address _feeCollector
    ) CCIPReceiver(_router) {
        _admin.validateAddress();
        _feeCollector.validateAddress();
        
        admin = _admin;
        feeCollector = _feeCollector;
        
        // Grant admin roles
        roles[EMERGENCY_ROLE][_admin] = true;
        roles[SENDER_ROLE][_admin] = true;
        
        // Set default gas limits
        gasLimits[MessageType.YIELD_REBALANCE] = 500000;
        gasLimits[MessageType.LOAN_REQUEST] = 300000;
        gasLimits[MessageType.LOAN_APPROVAL] = 200000;
        gasLimits[MessageType.COLLATERAL_TRANSFER] = 300000;
        gasLimits[MessageType.LIQUIDATION_TRIGGER] = 400000;
        gasLimits[MessageType.PRICE_UPDATE] = 200000;
    }

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
    ) external payable onlySender nonReentrant whenNotStopped returns (bytes32 messageId) {
        receiver.validateAddress();
        require(supportedChains[destinationChain], "Unsupported destination chain");
        
        // Build CCIP message
        Client.EVM2AnyMessage memory message = _buildMessage(
            receiver,
            messageType,
            data,
            token,
            amount
        );
        
        // Calculate fee
        uint256 fee = i_router.getFee(destinationChain, message);
        require(msg.value >= fee, "Insufficient fee");
        
        // Collect platform fee
        uint256 platformFee = ValidationLib.calculatePercentage(fee, feeRate);
        if (platformFee > 0 && msg.value > fee + platformFee) {
            payable(feeCollector).transfer(platformFee);
        }
        
        // Handle token transfer if specified
        if (token != address(0) && amount > 0) {
            amount.validateAmount();
            ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            ERC20(token).safeApprove(address(i_router), amount);
        }
        
        // Send message
        messageId = i_router.ccipSend{value: fee}(destinationChain, message);
        
        emit MessageSent(messageId, destinationChain, receiver, messageType, fee);
        
        if (token != address(0) && amount > 0) {
            emit TokensSent(messageId, destinationChain, token, amount, receiver);
        }
        
        return messageId;
    }

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
    ) external payable onlySender returns (bytes32 messageId) {
        bytes memory data = abi.encode(token, amount, targetProtocol);
        
        return sendMessage(
            destinationChain,
            yieldOptimizer,
            MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0
        );
    }

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
    ) external payable onlySender returns (bytes32 messageId) {
        bytes memory data = abi.encode(
            msg.sender, // borrower
            collateralToken,
            borrowToken,
            collateralAmount,
            requestedAmount,
            maxRate,
            duration
        );
        
        return sendMessage(
            destinationChain,
            lendingContract,
            MessageType.LOAN_REQUEST,
            data,
            collateralToken,
            collateralAmount
        );
    }

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
    ) external payable onlySender returns (bytes32 messageId) {
        bytes memory data = abi.encode(loanId, msg.sender);
        
        return sendMessage(
            destinationChain,
            lendingContract,
            MessageType.COLLATERAL_TRANSFER,
            data,
            token,
            amount
        );
    }

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
    ) external payable onlySender returns (bytes32 messageId) {
        bytes memory data = abi.encode(loanId, maxCollateralSeized, msg.sender);
        
        return sendMessage(
            destinationChain,
            lendingContract,
            MessageType.LIQUIDATION_TRIGGER,
            data,
            address(0),
            0
        );
    }

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
    ) external view returns (uint256 fee) {
        require(supportedChains[destinationChain], "Unsupported destination chain");
        
        Client.EVM2AnyMessage memory message = _buildMessage(
            address(0), // placeholder receiver
            messageType,
            data,
            token,
            amount
        );
        
        fee = i_router.getFee(destinationChain, message);
        
        // Add platform fee
        uint256 platformFee = ValidationLib.calculatePercentage(fee, feeRate);
        return fee + platformFee;
    }

    /**
     * @notice Check if a chain is supported for cross-chain operations
     * @param chainSelector Chainlink chain selector
     * @return supported Whether the chain is supported
     */
    function isSupportedChain(uint64 chainSelector) external view returns (bool supported) {
        return supportedChains[chainSelector];
    }

    /**
     * @notice Get the last received message for a sender
     * @param sender Address of the sender
     * @return message The last message received from the sender
     */
    function getLastMessage(address sender) external view returns (CrossChainMessage memory message) {
        return lastMessages[sender];
    }

    /**
     * @notice Add support for a new destination chain
     * @param chainSelector Chainlink chain selector
     * @param routerAddress CCIP router address for the chain (unused in current implementation)
     */
    function addSupportedChain(uint64 chainSelector, address routerAddress) external onlyAdmin {
        supportedChains[chainSelector] = true;
    }

    /**
     * @notice Remove support for a destination chain
     * @param chainSelector Chainlink chain selector to remove
     */
    function removeSupportedChain(uint64 chainSelector) external onlyAdmin {
        supportedChains[chainSelector] = false;
    }

    /**
     * @notice Update the gas limit for a specific message type
     * @param messageType Type of message
     * @param gasLimit New gas limit
     */
    function updateGasLimit(MessageType messageType, uint256 gasLimit) external onlyAdmin {
        require(gasLimit >= MIN_GAS_LIMIT && gasLimit <= MAX_GAS_LIMIT, "Invalid gas limit");
        gasLimits[messageType] = gasLimit;
    }

    /**
     * @notice Withdraw fees collected from cross-chain operations
     * @param token Token to withdraw (address(0) for native)
     * @param amount Amount to withdraw
     * @param recipient Address to receive the funds
     */
    function withdrawFees(address token, uint256 amount, address recipient) external onlyAdmin {
        recipient.validateAddress();
        amount.validateAmount();
        
        if (token == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            ERC20(token).safeTransfer(recipient, amount);
        }
    }

    // ===== CCIP RECEIVER IMPLEMENTATION =====

    /**
     * @notice Handle received CCIP messages
     * @param any2EvmMessage The received CCIP message
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // Prevent reentrancy and emergency stop check
        if (emergencyStop) return;
        
        bytes32 messageId = any2EvmMessage.messageId;
        
        // Prevent duplicate processing
        if (processedMessages[messageId]) return;
        processedMessages[messageId] = true;
        
        // Decode message type from first bytes
        MessageType messageType = abi.decode(any2EvmMessage.data[:32], (MessageType));
        
        // Store message info
        CrossChainMessage memory message = CrossChainMessage({
            sourceChain: any2EvmMessage.sourceChainSelector,
            destinationChain: uint64(block.chainid),
            sender: abi.decode(any2EvmMessage.sender, (address)),
            receiver: address(this),
            data: any2EvmMessage.data,
            token: any2EvmMessage.destTokenAmounts.length > 0 ? 
                   any2EvmMessage.destTokenAmounts[0].token : address(0),
            amount: any2EvmMessage.destTokenAmounts.length > 0 ? 
                    any2EvmMessage.destTokenAmounts[0].amount : 0,
            messageId: messageId,
            timestamp: block.timestamp
        });
        
        address sender = abi.decode(any2EvmMessage.sender, (address));
        lastMessages[sender] = message;
        
        bool success = _processMessage(message, messageType);
        
        emit MessageReceived(messageId, message.sourceChain, sender, messageType, success);
        
        if (message.token != address(0) && message.amount > 0) {
            emit TokensReceived(messageId, message.sourceChain, message.token, message.amount, message.receiver);
        }
    }

    /**
     * @notice Process different types of received messages
     * @param message The received message
     * @param messageType Type of the message
     * @return success Whether message processing was successful
     */
    function _processMessage(
        CrossChainMessage memory message,
        MessageType messageType
    ) internal returns (bool success) {
        try this._handleMessage(message, messageType) {
            return true;
        } catch {
            // Log failed message processing
            return false;
        }
    }

    /**
     * @notice External function to handle messages (allows try-catch)
     * @param message The received message
     * @param messageType Type of the message
     */
    function _handleMessage(
        CrossChainMessage memory message,
        MessageType messageType
    ) external {
        require(msg.sender == address(this), "Internal only");
        
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

    function _handleCollateralTransfer(CrossChainMessage memory message) internal {
        // Implementation would call lending contract
        // For now, just emit event showing message was received
    }

    function _handleLiquidationTrigger(CrossChainMessage memory message) internal {
        // Implementation would call lending contract
        // For now, just emit event showing message was received
    }

    function _handlePriceUpdate(CrossChainMessage memory message) internal {
        // Implementation would update price oracles
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
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](
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
        
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: messageData,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({
                    gasLimit: gasLimits[messageType],
                    strict: false
                })
            ),
            feeToken: address(0) // Use native token for fees
        });
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return roles[role][account];
    }

    // ===== ADMIN FUNCTIONS =====

    function setFeeRate(uint256 _feeRate) external onlyAdmin {
        require(_feeRate <= 1000, "Fee rate too high"); // Max 10%
        feeRate = _feeRate;
    }

    function setFeeCollector(address _feeCollector) external onlyAdmin {
        _feeCollector.validateAddress();
        feeCollector = _feeCollector;
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        roles[role][account] = false;
    }

    function toggleEmergencyStop() external {
        require(hasRole(EMERGENCY_ROLE, msg.sender), "Not emergency role");
        emergencyStop = !emergencyStop;
    }

    // ===== EMERGENCY FUNCTIONS =====

    /**
     * @notice Emergency withdraw function for stuck funds
     * @param token Token to withdraw (address(0) for native)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external {
        require(hasRole(EMERGENCY_ROLE, msg.sender), "Not emergency role");
        require(emergencyStop, "Emergency stop not active");
        
        if (token == address(0)) {
            payable(admin).transfer(amount);
        } else {
            ERC20(token).safeTransfer(admin, amount);
        }
    }

    // Allow contract to receive native tokens
    receive() external payable {}
} 