// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "./ChainlinkFeedManager.sol";
import "../interfaces/IProtocolAdapter.sol";
import "../interfaces/ICCIPMessenger.sol";
import "../libraries/ValidationLib.sol";
import "../libraries/MathLib.sol";

/**
 * @title AliothYieldOptimizer
 * @notice AI-driven yield optimization system with Chainlink integration
 */
contract AliothYieldOptimizer is
    AutomationCompatibleInterface,
    ReentrancyGuard
{
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;
    using MathLib for uint256;

    /// @notice Role for AI agents that can trigger operations
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    /// @notice Role for yield harvesters
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

    /// @notice Role for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Role for authorized vaults that can call deposit functions
    bytes32 public constant AUTHORIZED_VAULT_ROLE =
        keccak256("AUTHORIZED_VAULT_ROLE");

    /// @notice Maximum number of protocols to support
    uint256 public constant MAX_PROTOCOLS = 20;

    /// @notice Maximum slippage allowed (in basis points)
    uint256 public constant MAX_SLIPPAGE = 500; // 5%

    struct ProtocolInfo {
        IProtocolAdapter adapter;
        uint256 lastAPYUpdate;
        uint256 currentAPY;
        bool isActive;
    }

    /// @notice Mapping of protocol adapter addresses to protocol info
    mapping(address => ProtocolInfo) public protocols;

    /// @notice Array of active protocol addresses
    address[] public activeProtocols;

    /// @notice Mapping of token to supported protocols
    mapping(address => address[]) public tokenProtocols;

    /// @notice Protocol enumeration
    enum Protocol {
        AAVE,
        COMPOUND,
        YEARN
    }

    /// @notice Optimization status
    enum OptimizationStatus {
        ACTIVE,
        PAUSED,
        WITHDRAWN
    }

    struct SingleOptimization {
        address user;
        address token;
        uint256 amount;
        Protocol protocol;
        uint256 shares;
        uint256 timestamp;
        uint256 lastRebalance;
        uint256 automationId;
        uint256 rebalanceCount;
        OptimizationStatus status;
    }

    /// @notice Mapping of optimization ID to optimization data
    mapping(uint256 => SingleOptimization) public optimizations;

    /// @notice Counter for generating optimization IDs
    uint256 public nextOptimizationId = 1;

    /// @notice Mapping of authorized AI backends
    mapping(address => bool) public authorizedAIBackends;

    /// @notice Enhanced Chainlink Feed Manager
    ChainlinkFeedManager public immutable feedManager;

    /// @notice CCIP messenger for cross-chain operations
    ICCIPMessenger public immutable ccipMessenger;

    /// @notice Administrator role
    address public admin;

    /// @notice Emergency stop flag
    bool public emergencyStop;

    /// @notice Rebalance interval (15 minutes)
    uint256 public REBALANCE_INTERVAL = 900;

    /// @notice Minimum yield improvement for rebalancing (1%)
    uint256 public REBALANCE_THRESHOLD = 100;

    /// @notice Simple role checking (to with OpenZeppelin AccessControl)
    mapping(bytes32 => mapping(address => bool)) private roles;

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

    modifier onlyAuthorizedAI() {
        require(authorizedAIBackends[msg.sender], "Not authorized AI backend");
        _;
    }

    modifier onlyAuthorizedVault() {
        require(
            hasRole(AUTHORIZED_VAULT_ROLE, msg.sender),
            "Not authorized vault"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier whenNotStopped() {
        require(!emergencyStop, "Emergency stopped");
        _;
    }

    modifier onlyRebalancer() {
        require(
            msg.sender == admin || hasRole(REBALANCER_ROLE, msg.sender),
            "Not rebalancer"
        );
        _;
    }

    constructor(
        address _ccipMessenger,
        address _enhancedFeedManager,
        address _admin
    ) {
        _ccipMessenger.validateAddress();
        _enhancedFeedManager.validateAddress();
        _admin.validateAddress();

        ccipMessenger = ICCIPMessenger(_ccipMessenger);
        feedManager = ChainlinkFeedManager(_enhancedFeedManager);
        admin = _admin;

        // Grant admin role to deployer
        roles[EMERGENCY_ROLE][_admin] = true;
        roles[REBALANCER_ROLE][_admin] = true;
        roles[HARVESTER_ROLE][_admin] = true;
    }

    /**
     * @notice Add a new protocol adapter to the optimizer
     * @param adapter The protocol adapter contract address
     */
    function addProtocol(address adapter) external onlyAdmin {
        adapter.validateAddress();
        require(
            activeProtocols.length < MAX_PROTOCOLS,
            "Max protocols reached"
        );
        require(!protocols[adapter].isActive, "Protocol already active");

        IProtocolAdapter protocolAdapter = IProtocolAdapter(adapter);
        string memory protocolName = protocolAdapter.protocolName();

        protocols[adapter] = ProtocolInfo({
            adapter: protocolAdapter,
            lastAPYUpdate: block.timestamp,
            currentAPY: 0,
            isActive: true
        });

        activeProtocols.push(adapter);

        emit ProtocolAdded(adapter, protocolName);
    }

    /**
     * @notice Remove a protocol adapter from the optimizer
     * @param adapter The protocol adapter contract address
     */
    function removeProtocol(address adapter) external onlyAdmin {
        require(protocols[adapter].isActive, "Protocol not active");

        for (uint256 i = 0; i < activeProtocols.length; i++) {
            if (activeProtocols[i] == adapter) {
                activeProtocols[i] = activeProtocols[
                    activeProtocols.length - 1
                ];
                activeProtocols.pop();
                break;
            }
        }

        string memory protocolName = protocols[adapter].adapter.protocolName();
        protocols[adapter].isActive = false;

        emit ProtocolRemoved(adapter, protocolName);
    }

    /**
     * @notice Simple role checking helper
     * @param role Role to check
     * @param account Account to check role for
     * @return hasRoleResult Whether account has role
     */
    function hasRole(
        bytes32 role,
        address account
    ) public view returns (bool hasRoleResult) {
        return roles[role][account];
    }

    /**
     * @notice Authorize a vault contract
     * @param vault Address of the vault contract
     */
    function authorizeVault(address vault) external onlyAdmin {
        require(vault != address(0), "Invalid vault address");
        roles[AUTHORIZED_VAULT_ROLE][vault] = true;
        emit VaultAuthorized(vault);
    }

    /**
     * @notice Revoke vault authorization
     * @param vault Address of the vault contract
     */
    function revokeVault(address vault) external onlyAdmin {
        roles[AUTHORIZED_VAULT_ROLE][vault] = false;
        emit VaultRevoked(vault);
    }

    /**
     * @notice Authorize an AI backend service
     * @param aiBackend Address of the AI backend service
     */
    function authorizeAIBackend(address aiBackend) external onlyAdmin {
        require(aiBackend != address(0), "Invalid AI backend address");
        authorizedAIBackends[aiBackend] = true;
        emit AIAgentAuthorized(aiBackend);
    }

    /**
     * @notice Revoke AI backend authorization
     * @param aiBackend Address of the AI backend service
     */
    function revokeAIBackend(address aiBackend) external onlyAdmin {
        authorizedAIBackends[aiBackend] = false;
        emit AIAgentRevoked(aiBackend);
    }

    /**
     * @notice Core function called by authorized vaults for deposits
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
    )
        external
        onlyAuthorizedVault
        nonReentrant
        whenNotStopped
        returns (uint256 optimizationId)
    {
        require(amount > 0, "Invalid amount");
        require(beneficiary != address(0), "Invalid beneficiary");

        require(
            feedManager.validateTokenPrice(token, amount),
            "Chainlink price validation failed"
        );

        Protocol protocolEnum = _stringToProtocol(protocol);

        uint256 currentAPY = feedManager.getProtocolAPY(
            uint8(protocolEnum),
            token
        );
        require(currentAPY > 0, "Invalid protocol APY");

        // Vault has already transferred tokens to this contract
        // No need for safeTransferFrom here
        require(
            ERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient token balance"
        );

        uint256 shares = _executeProtocolDeposit(token, amount, protocolEnum);

        optimizationId = _generateOptimizationId();
        uint256 automationId = _registerForAutomation(optimizationId);

        optimizations[optimizationId] = SingleOptimization(
            beneficiary,
            token,
            amount,
            protocolEnum,
            shares,
            block.timestamp,
            block.timestamp,
            automationId,
            0,
            OptimizationStatus.ACTIVE
        );

        emit OptimizationExecuted(
            optimizationId,
            beneficiary,
            token,
            amount,
            protocol,
            automationId
        );

        return optimizationId;
    }

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
    ) external view returns (bool isValid) {
        if (!feedManager.validateTokenPrice(token, amount)) {
            return false;
        }

        Protocol protocolEnum = _stringToProtocol(protocol);
        uint256 currentAPY = feedManager.getProtocolAPY(
            uint8(protocolEnum),
            token
        );

        return currentAPY > 0;
    }

    /**
     * @notice Chainlink Automation checkUpkeep function
     * @param checkData Encoded optimization ID to check
     * @return upkeepNeeded Whether upkeep is needed
     * @return performData Data to pass to performUpkeep
     */
    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 optimizationId = abi.decode(checkData, (uint256));
        SingleOptimization memory opt = optimizations[optimizationId];

        if (
            opt.status == OptimizationStatus.ACTIVE &&
            block.timestamp >= opt.lastRebalance + REBALANCE_INTERVAL
        ) {
            // Check if better protocol available using Chainlink feeds
            uint256 currentAPY = feedManager.getProtocolAPY(
                uint8(opt.protocol),
                opt.token
            );
            uint256 bestAPY = feedManager.getBestProtocolAPY(opt.token);

            if (bestAPY > currentAPY + REBALANCE_THRESHOLD) {
                upkeepNeeded = true;
                performData = abi.encode(optimizationId, bestAPY);
            }
        }
    }

    /**
     * @notice Chainlink Automation performUpkeep function
     * @param performData Data from checkUpkeep containing optimization ID and expected yield
     */
    function performUpkeep(bytes calldata performData) external override {
        (uint256 optimizationId, uint256 expectedYield) = abi.decode(
            performData,
            (uint256, uint256)
        );

        SingleOptimization storage opt = optimizations[optimizationId];
        require(
            opt.status == OptimizationStatus.ACTIVE,
            "Optimization not active"
        );

        require(
            feedManager.validateTokenPrice(opt.token, opt.amount),
            "Chainlink price validation failed for rebalancing"
        );

        // Execute rebalancing to better protocol
        _executeProtocolRebalancing(optimizationId, expectedYield);

        // Update state
        opt.lastRebalance = block.timestamp;
        opt.rebalanceCount++;

        emit AutomatedRebalanceExecuted(
            optimizationId,
            expectedYield,
            block.timestamp
        );
    }

    /**
     * @notice Execute protocol deposit using real adapters
     * @param token Token to deposit
     * @param amount Amount to deposit
     * @param protocol Target protocol
     * @return shares Shares received
     */
    function _executeProtocolDeposit(
        address token,
        uint256 amount,
        Protocol protocol
    ) internal returns (uint256 shares) {
        address protocolAdapter = _getProtocolAdapter(protocol);
        require(protocolAdapter != address(0), "Protocol adapter not found");
        require(protocols[protocolAdapter].isActive, "Protocol not active");

        ERC20(token).safeApprove(protocolAdapter, amount);

        shares = IProtocolAdapter(protocolAdapter).deposit(token, amount, 0);

        return shares;
    }

    /**
     * @notice Get protocol adapter address from enum
     * @param protocol Protocol enum
     * @return adapterAddress Protocol adapter address
     */
    function _getProtocolAdapter(
        Protocol protocol
    ) internal view returns (address adapterAddress) {
        for (uint256 i = 0; i < activeProtocols.length; i++) {
            string memory protocolName = protocols[activeProtocols[i]]
                .adapter
                .protocolName();

            if (
                protocol == Protocol.AAVE &&
                _compareStrings(protocolName, "Aave")
            ) {
                return activeProtocols[i];
            } else if (
                protocol == Protocol.COMPOUND &&
                _compareStrings(protocolName, "Compound")
            ) {
                return activeProtocols[i];
            } else if (
                protocol == Protocol.YEARN &&
                _compareStrings(protocolName, "Yearn")
            ) {
                return activeProtocols[i];
            }
        }
        return address(0);
    }

    /**
     * @notice Compare strings helper
     * @param a First string
     * @param b Second string
     * @return isEqual Whether strings are equal
     */
    function _compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool isEqual) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @notice Convert protocol string to enum
     * @param protocolName Protocol string ("aave", "compound", "yearn")
     * @return protocol Protocol enum
     */
    function _stringToProtocol(
        string memory protocolName
    ) internal pure returns (Protocol protocol) {
        bytes32 nameHash = keccak256(bytes(protocolName));

        if (nameHash == keccak256(bytes("aave"))) {
            return Protocol.AAVE;
        } else if (nameHash == keccak256(bytes("compound"))) {
            return Protocol.COMPOUND;
        } else if (nameHash == keccak256(bytes("yearn"))) {
            return Protocol.YEARN;
        } else {
            revert("Unsupported protocol");
        }
    }

    /**
     * @notice Generate optimization ID
     * @return optimizationId Generated ID
     */
    function _generateOptimizationId()
        internal
        returns (uint256 optimizationId)
    {
        optimizationId = nextOptimizationId;
        nextOptimizationId++;
        return optimizationId;
    }

    /**
     * @notice Register for Chainlink automation
     * @param optimizationId Optimization ID
     * @return automationId Automation ID
     */
    function _registerForAutomation(
        uint256 optimizationId
    )
        internal
        pure
        returns (
            // Protocol protocol,
            // address token,
            // uint256 amount
            uint256 automationId
        )
    {
        // simple automation ID
        // In production, this would register with Chainlink Automation Registry
        automationId = optimizationId + 1000000;
        return automationId;
    }

    /**
     * @notice Execute protocol rebalancing
     * @param optimizationId Optimization ID
     * @param expectedYield Expected yield
     */
    function _executeProtocolRebalancing(
        uint256 optimizationId,
        uint256 expectedYield
    ) internal view {
        // simple implementation
        // In production, this would move funds between protocols
        SingleOptimization storage opt = optimizations[optimizationId];

        // Find better protocol
        uint256 bestAPY = feedManager.getBestProtocolAPY(opt.token);
        if (bestAPY > expectedYield) {
            // Would execute rebalancing here
            // For now, just update the stored data
        }
    }

    /**
     * @notice Update rebalance parameters
     * @param _rebalanceInterval New rebalance interval in seconds
     * @param _rebalanceThreshold New rebalance threshold in basis points
     */
    function updateRebalanceParams(
        uint256 _rebalanceInterval,
        uint256 _rebalanceThreshold
    ) external onlyAdmin {
        require(_rebalanceInterval >= 300, "Interval too short"); // Min 5 minutes
        require(_rebalanceThreshold <= 1000, "Threshold too high"); // Max 10%

        REBALANCE_INTERVAL = _rebalanceInterval;
        REBALANCE_THRESHOLD = _rebalanceThreshold;

        emit RebalanceParamsUpdated(_rebalanceInterval, _rebalanceThreshold);
    }

    /**
     * @notice Emergency stop toggle
     */
    function setEmergencyStop(bool _emergencyStop) external onlyAdmin {
        emergencyStop = _emergencyStop;
    }

    /**
     * @notice Calculate expected APY for a token
     * @param token Token address
     * @return expectedAPY Expected APY in basis points
     */
    function _getTokenExpectedAPY(
        address token
    ) internal view returns (uint256 expectedAPY) {
        uint256 projectedAPY = feedManager.projectedAPYs(token);
        return projectedAPY > 0 ? projectedAPY : 500; // 5% default
    }

    /**
     * @notice Convert protocol enumeration to string
     * @param protocol Protocol enumeration
     * @return protocolString Protocol string representation
     */
    function protocolToString(
        Protocol protocol
    ) internal pure returns (string memory protocolString) {
        if (protocol == Protocol.AAVE) {
            return "AAVE";
        } else if (protocol == Protocol.COMPOUND) {
            return "COMPOUND";
        } else if (protocol == Protocol.YEARN) {
            return "YEARN";
        } else {
            revert("Invalid protocol");
        }
    }

    /**
     * @notice Automated rebalance function
     * @param optimizationId ID of the optimization to rebalance
     * @param expectedYield Expected yield for the rebalance
     * @param timestamp Timestamp of the rebalance
     */
    function automatedRebalance(
        uint256 optimizationId,
        uint256 expectedYield,
        uint256 timestamp
    ) external onlyAuthorizedAI {
        SingleOptimization storage optimization = optimizations[optimizationId];
        require(
            optimization.status == OptimizationStatus.ACTIVE,
            "Optimization not active"
        );
        require(
            block.timestamp - optimization.lastRebalance >= REBALANCE_INTERVAL,
            "Rebalance interval not met"
        );

        address[] memory tokens = new address[](1);
        tokens[0] = optimization.token;
        uint256 oldExpectedAPY = _getTokenExpectedAPY(optimization.token);
        uint256 newExpectedAPY = expectedYield;

        require(
            newExpectedAPY >= oldExpectedAPY + REBALANCE_THRESHOLD,
            "Insufficient yield improvement"
        );

        optimization.lastRebalance = block.timestamp;
        optimization.rebalanceCount++;

        emit AutomatedRebalanceExecuted(
            optimizationId,
            expectedYield,
            timestamp
        );
    }

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
    )
        external
        onlyAuthorizedVault
        nonReentrant
        whenNotStopped
        returns (uint256 withdrawnAmount)
    {
        require(amount > 0, "Invalid amount");
        require(beneficiary != address(0), "Invalid beneficiary");

        require(
            feedManager.validateTokenPrice(token, amount),
            "Chainlink price validation failed"
        );

        Protocol protocolEnum = _stringToProtocol(protocol);
        address protocolAdapter = _getProtocolAdapter(protocolEnum);
        require(protocolAdapter != address(0), "Protocol adapter not found");
        require(protocols[protocolAdapter].isActive, "Protocol not active");

        // Execute withdrawal through protocol adapter
        withdrawnAmount = IProtocolAdapter(protocolAdapter).withdraw(
            token,
            amount,
            0 // minAmount set to 0 as slippage is checked at vault level
        );

        // Transfer withdrawn tokens to beneficiary
        ERC20(token).safeTransfer(beneficiary, withdrawnAmount);

        return withdrawnAmount;
    }
}
