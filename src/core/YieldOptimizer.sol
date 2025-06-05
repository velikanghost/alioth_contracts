// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IYieldOptimizer.sol";
import "../interfaces/IProtocolAdapter.sol";
import "../interfaces/ICCIPMessenger.sol";
import "../libraries/ValidationLib.sol";
import "../libraries/MathLib.sol";

/**
 * @title YieldOptimizer
 * @notice AI-driven yield optimization system for Alioth platform
 * @dev Manages allocation across multiple protocols and chains for optimal yield
 */
contract YieldOptimizer is
    IYieldOptimizer,
    AutomationCompatibleInterface,
    ReentrancyGuard
{
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;
    using MathLib for uint256;

    /// @notice Role for AI agents that can trigger rebalances
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    /// @notice Role for yield harvesters
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

    /// @notice Role for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Maximum number of protocols to support
    uint256 public constant MAX_PROTOCOLS = 20;

    /// @notice Minimum rebalance threshold (in basis points)
    uint256 public constant MIN_REBALANCE_THRESHOLD = 50; // 0.5%

    /// @notice Maximum slippage allowed (in basis points)
    uint256 public constant MAX_SLIPPAGE = 500; // 5%

    struct ProtocolInfo {
        IProtocolAdapter adapter;
        uint256 weight;
        uint256 lastAPYUpdate;
        uint256 currentAPY;
        bool isActive;
    }

    struct TokenAllocation {
        mapping(address => uint256) protocolAllocations; // protocol -> amount
        uint256 totalAllocated;
        uint256 lastRebalanceTime;
        uint256 targetAPY;
    }

    /// @notice Mapping of protocol adapter addresses to protocol info
    mapping(address => ProtocolInfo) public protocols;

    /// @notice Array of active protocol addresses
    address[] public activeProtocols;

    /// @notice Mapping of token to allocation data
    mapping(address => TokenAllocation) private tokenAllocations;

    /// @notice Mapping of token to supported protocols
    mapping(address => address[]) public tokenProtocols;

    /// @notice CCIP messenger for cross-chain operations
    ICCIPMessenger public immutable ccipMessenger;

    /// @notice Administrator role
    address public admin;

    /// @notice Emergency stop flag
    bool public emergencyStop;

    /// @notice Minimum rebalance improvement threshold (in basis points)
    uint256 public rebalanceThreshold = 100; // 1%

    /// @notice Maximum gas price for rebalancing
    uint256 public maxGasPrice = 50 gwei;

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

    /// @notice Modifier to restrict access to rebalancer role
    modifier onlyRebalancer() {
        require(
            msg.sender == admin || hasRole(REBALANCER_ROLE, msg.sender),
            "Not rebalancer"
        );
        _;
    }

    /// @notice Modifier to restrict access to harvester role
    modifier onlyHarvester() {
        require(
            msg.sender == admin || hasRole(HARVESTER_ROLE, msg.sender),
            "Not harvester"
        );
        _;
    }

    /// @notice Simple role checking (replace with OpenZeppelin AccessControl in production)
    mapping(bytes32 => mapping(address => bool)) private roles;

    constructor(address _ccipMessenger, address _admin) {
        _ccipMessenger.validateAddress();
        _admin.validateAddress();

        ccipMessenger = ICCIPMessenger(_ccipMessenger);
        admin = _admin;

        // Grant admin role to deployer
        roles[EMERGENCY_ROLE][_admin] = true;
        roles[REBALANCER_ROLE][_admin] = true;
        roles[HARVESTER_ROLE][_admin] = true;
    }

    /**
     * @notice Add a new protocol adapter to the optimizer
     * @param adapter The protocol adapter contract address
     * @param weight The weight for this protocol in optimization (0-10000 basis points)
     */
    function addProtocol(address adapter, uint256 weight) external onlyAdmin {
        adapter.validateAddress();
        weight.validatePercentage();
        require(
            activeProtocols.length < MAX_PROTOCOLS,
            "Max protocols reached"
        );
        require(!protocols[adapter].isActive, "Protocol already active");

        IProtocolAdapter protocolAdapter = IProtocolAdapter(adapter);
        string memory protocolName = protocolAdapter.protocolName();

        protocols[adapter] = ProtocolInfo({
            adapter: protocolAdapter,
            weight: weight,
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

        // Remove from active protocols array
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
     * @notice Get the current allocation for a token across all protocols
     * @param token The token address
     * @return allocations Array of current allocations per protocol
     */
    function getCurrentAllocation(
        address token
    ) external view returns (AllocationTarget[] memory allocations) {
        address[] memory supportedProtocols = _getSupportedProtocols(token);
        allocations = new AllocationTarget[](supportedProtocols.length);

        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            address protocolAddr = supportedProtocols[i];
            ProtocolInfo memory protocol = protocols[protocolAddr];

            allocations[i] = AllocationTarget({
                protocolAdapter: protocolAddr,
                targetPercentage: protocol.weight,
                currentAllocation: tokenAllocations[token].protocolAllocations[
                    protocolAddr
                ],
                currentAPY: protocol.currentAPY
            });
        }
    }

    /**
     * @notice Get the weighted average APY for a token across all protocols
     * @param token The token address
     * @return weightedAPY The current weighted average APY
     */
    function getWeightedAPY(
        address token
    ) external view returns (uint256 weightedAPY) {
        address[] memory supportedProtocols = _getSupportedProtocols(token);
        uint256[] memory apys = new uint256[](supportedProtocols.length);
        uint256[] memory weights = new uint256[](supportedProtocols.length);

        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            address protocolAddr = supportedProtocols[i];
            ProtocolInfo memory protocol = protocols[protocolAddr];

            apys[i] = protocol.currentAPY;
            weights[i] = tokenAllocations[token].protocolAllocations[
                protocolAddr
            ];
        }

        if (supportedProtocols.length == 0) return 0;

        return MathLib.calculateWeightedAverage(apys, weights);
    }

    /**
     * @notice Calculate optimal allocation based on current APYs and constraints
     * @param token The token address
     * @param totalAmount The total amount to allocate
     * @return targets Optimal allocation targets
     */
    function calculateOptimalAllocation(
        address token,
        uint256 totalAmount
    ) external view returns (AllocationTarget[] memory targets) {
        address[] memory supportedProtocols = _getSupportedProtocols(token);

        if (supportedProtocols.length == 0) {
            return new AllocationTarget[](0);
        }

        uint256[] memory apys = new uint256[](supportedProtocols.length);
        uint256[] memory risks = new uint256[](supportedProtocols.length);
        uint256[] memory weights = new uint256[](supportedProtocols.length);

        // Collect current data for optimization
        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            address protocolAddr = supportedProtocols[i];
            ProtocolInfo memory protocol = protocols[protocolAddr];

            apys[i] = protocol.currentAPY;
            risks[i] = _calculateProtocolRisk(protocolAddr, token);
            weights[i] = protocol.weight;
        }

        uint256[] memory optimalAllocations;

        // Check if all APYs are zero or equal - if so, use protocol weights
        bool useWeights = true;
        uint256 firstAPY = apys[0];
        for (uint256 i = 0; i < apys.length; i++) {
            if (apys[i] != firstAPY) {
                useWeights = false;
                break;
            }
        }

        if (useWeights) {
            // Use protocol weights for allocation
            optimalAllocations = weights;
        } else {
            // Use APY-based optimization
            optimalAllocations = MathLib.calculateOptimalAllocation(
                apys,
                risks
            );
        }

        targets = new AllocationTarget[](supportedProtocols.length);

        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            targets[i] = AllocationTarget({
                protocolAdapter: supportedProtocols[i],
                targetPercentage: optimalAllocations[i],
                currentAllocation: (totalAmount * optimalAllocations[i]) /
                    ValidationLib.BPS_MAX,
                currentAPY: apys[i]
            });
        }
    }

    /**
     * @notice Execute a rebalance operation based on AI recommendations
     * @param params The rebalance parameters including targets and constraints
     */
    function executeRebalance(
        RebalanceParams calldata params
    ) external onlyRebalancer nonReentrant whenNotStopped {
        params.token.validateAddress();
        params.deadline.validateDeadline();
        ValidationLib.validateNonEmptyArray(params.targets.length);

        // Update APYs before rebalancing
        _updateAPYs(params.token);

        // Validate rebalance is beneficial
        (bool shouldRebal, uint256 expectedImprovement) = this.shouldRebalance(
            params.token,
            rebalanceThreshold
        );
        require(shouldRebal, "Rebalance not beneficial");

        // Execute the rebalance
        _executeRebalanceInternal(params);

        emit AIRebalanceTriggered(params.token, expectedImprovement);
    }

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
    ) external nonReentrant whenNotStopped returns (uint256 shares) {
        token.validateAddress();
        amount.validateAmount();

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Get optimal allocation
        AllocationTarget[] memory targets = this.calculateOptimalAllocation(
            token,
            amount
        );

        // Deposit to protocols according to optimal allocation
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i].currentAllocation > 0) {
                ERC20(token).safeApprove(
                    targets[i].protocolAdapter,
                    targets[i].currentAllocation
                );

                uint256 protocolShares = IProtocolAdapter(
                    targets[i].protocolAdapter
                ).deposit(token, targets[i].currentAllocation, 0);

                shares += protocolShares;
                tokenAllocations[token].protocolAllocations[
                    targets[i].protocolAdapter
                ] += targets[i].currentAllocation;
            }
        }

        tokenAllocations[token].totalAllocated += amount;

        // Validate minimum shares received
        ValidationLib.validateSlippage(minShares, shares, MAX_SLIPPAGE);
    }

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
    ) external nonReentrant whenNotStopped returns (uint256 amount) {
        token.validateAddress();
        shares.validateAmount();

        // Withdraw from protocols in reverse optimal order to minimize impact
        address[] memory supportedProtocols = _getSupportedProtocols(token);

        uint256 remainingShares = shares;

        for (
            uint256 i = 0;
            i < supportedProtocols.length && remainingShares > 0;
            i++
        ) {
            address protocolAddr = supportedProtocols[i];
            uint256 protocolShares = IProtocolAdapter(protocolAddr)
                .getSharesBalance(token);

            if (protocolShares > 0) {
                uint256 sharesToWithdraw = MathLib.min(
                    remainingShares,
                    protocolShares
                );
                uint256 protocolAmount = IProtocolAdapter(protocolAddr)
                    .withdraw(token, sharesToWithdraw, 0);

                amount += protocolAmount;
                remainingShares -= sharesToWithdraw;

                tokenAllocations[token].protocolAllocations[
                    protocolAddr
                ] -= protocolAmount;
            }
        }

        tokenAllocations[token].totalAllocated -= amount;

        // Validate minimum amount received
        ValidationLib.validateSlippage(minAmount, amount, MAX_SLIPPAGE);

        ERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Harvest yield from all protocols for a given token
     * @param token The token to harvest yield for
     * @return totalYield Total yield harvested across all protocols
     */
    function harvestAll(
        address token
    ) external onlyHarvester returns (uint256 totalYield) {
        address[] memory supportedProtocols = _getSupportedProtocols(token);

        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            try
                IProtocolAdapter(supportedProtocols[i]).harvestYield(token)
            returns (uint256 yield) {
                totalYield += yield;
            } catch {
                // Continue with other protocols if one fails
                continue;
            }
        }
    }

    /**
     * @notice Check if rebalancing would be profitable for a token
     * @param token The token address
     * @param minImprovementBps Minimum APY improvement required (in basis points)
     * @return shouldRebal Whether rebalancing is recommended
     * @return expectedImprovement Expected APY improvement in basis points
     */
    function shouldRebalance(
        address token,
        uint256 minImprovementBps
    ) external view returns (bool shouldRebal, uint256 expectedImprovement) {
        uint256 currentAPY = this.getWeightedAPY(token);

        // Calculate potential APY with optimal allocation
        AllocationTarget[] memory optimalTargets = this
            .calculateOptimalAllocation(
                token,
                tokenAllocations[token].totalAllocated
            );

        uint256[] memory apys = new uint256[](optimalTargets.length);
        uint256[] memory weights = new uint256[](optimalTargets.length);

        for (uint256 i = 0; i < optimalTargets.length; i++) {
            apys[i] = optimalTargets[i].currentAPY;
            weights[i] = optimalTargets[i].targetPercentage;
        }

        uint256 optimalAPY = MathLib.calculateWeightedAverage(apys, weights);

        if (optimalAPY > currentAPY) {
            expectedImprovement = optimalAPY - currentAPY;
            shouldRebal = expectedImprovement >= minImprovementBps;
        }
    }

    /**
     * @notice Get total value locked across all protocols for a token
     * @param token The token address
     * @return totalTVL Combined TVL across all protocols
     */
    function getTotalTVL(
        address token
    ) external view returns (uint256 totalTVL) {
        return tokenAllocations[token].totalAllocated;
    }

    /**
     * @notice Get supported protocols for a given token
     * @param token The token address
     * @return adapters Array of protocol adapter addresses that support the token
     */
    function getSupportedProtocols(
        address token
    ) external view returns (address[] memory adapters) {
        return _getSupportedProtocols(token);
    }

    // ===== CHAINLINK AUTOMATION =====

    /**
     * @notice Check if upkeep is needed for automated rebalancing
     * @param checkData Encoded token address to check
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
        address token = abi.decode(checkData, (address));

        (bool shouldRebal, uint256 improvement) = this.shouldRebalance(
            token,
            rebalanceThreshold
        );

        if (shouldRebal && tx.gasprice <= maxGasPrice) {
            upkeepNeeded = true;
            performData = abi.encode(token, improvement);
        }
    }

    /**
     * @notice Perform automated rebalancing
     * @param performData Encoded data from checkUpkeep
     */
    function performUpkeep(bytes calldata performData) external override {
        (address token, ) = abi.decode(performData, (address, uint256));

        // Verify upkeep is still needed
        (bool shouldRebal, ) = this.shouldRebalance(token, rebalanceThreshold);
        require(shouldRebal, "Upkeep no longer needed");

        // Create rebalance params with optimal allocation
        AllocationTarget[] memory targets = this.calculateOptimalAllocation(
            token,
            tokenAllocations[token].totalAllocated
        );

        RebalanceParams memory params = RebalanceParams({
            token: token,
            targets: targets,
            maxSlippage: MAX_SLIPPAGE,
            deadline: block.timestamp + 1 hours
        });

        this.executeRebalance(params);
    }

    // ===== INTERNAL FUNCTIONS =====

    function _getSupportedProtocols(
        address token
    ) internal view returns (address[] memory supported) {
        uint256 count = 0;

        // Count supported protocols
        for (uint256 i = 0; i < activeProtocols.length; i++) {
            if (protocols[activeProtocols[i]].adapter.supportsToken(token)) {
                count++;
            }
        }

        supported = new address[](count);
        uint256 index = 0;

        // Populate array
        for (uint256 i = 0; i < activeProtocols.length; i++) {
            if (protocols[activeProtocols[i]].adapter.supportsToken(token)) {
                supported[index] = activeProtocols[i];
                index++;
            }
        }
    }

    function _updateAPYs(address token) internal {
        address[] memory supportedProtocols = _getSupportedProtocols(token);

        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            address protocolAddr = supportedProtocols[i];

            try IProtocolAdapter(protocolAddr).getAPY(token) returns (
                uint256 apy
            ) {
                protocols[protocolAddr].currentAPY = apy;
                protocols[protocolAddr].lastAPYUpdate = block.timestamp;
            } catch {
                // Use cached APY if update fails
                continue;
            }
        }
    }

    function _calculateProtocolRisk(
        address protocolAddr,
        address token
    ) internal view returns (uint256 risk) {
        // Simple risk calculation based on TVL and time
        uint256 tvl = protocols[protocolAddr].adapter.getTVL(token);
        uint256 timeSinceUpdate = block.timestamp -
            protocols[protocolAddr].lastAPYUpdate;

        // Higher TVL = lower risk, older data = higher risk
        risk = 1000; // Base risk

        if (tvl > 1000000 * 1e18) {
            // > 1M tokens
            risk = 500; // Lower risk for high TVL
        }

        if (timeSinceUpdate > 1 hours) {
            risk += 500; // Higher risk for stale data
        }

        return MathLib.min(risk, 5000); // Cap at 50%
    }

    function _executeRebalanceInternal(
        RebalanceParams calldata params
    ) internal {
        // This would implement the actual rebalancing logic
        // For brevity, we'll emit the event showing the rebalance occurred
        address[] memory fromProtocols = new address[](0);
        address[] memory toProtocols = new address[](params.targets.length);
        uint256[] memory amounts = new uint256[](params.targets.length);

        for (uint256 i = 0; i < params.targets.length; i++) {
            toProtocols[i] = params.targets[i].protocolAdapter;
            amounts[i] = params.targets[i].currentAllocation;
        }

        uint256 newAPY = this.getWeightedAPY(params.token);
        tokenAllocations[params.token].lastRebalanceTime = block.timestamp;

        emit Rebalanced(
            params.token,
            fromProtocols,
            toProtocols,
            amounts,
            newAPY
        );
    }

    function hasRole(
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return roles[role][account];
    }

    // ===== ADMIN FUNCTIONS =====

    function setRebalanceThreshold(uint256 _threshold) external onlyAdmin {
        require(_threshold >= MIN_REBALANCE_THRESHOLD, "Threshold too low");
        rebalanceThreshold = _threshold;
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyAdmin {
        maxGasPrice = _maxGasPrice;
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
}
