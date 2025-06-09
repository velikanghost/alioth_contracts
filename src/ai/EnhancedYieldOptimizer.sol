// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/YieldOptimizer.sol";

import "./EnhancedChainlinkFeedManager.sol";
import "../libraries/CrossTokenOperationsLib.sol";
import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";

/**
 * @title EnhancedYieldOptimizer
 * @notice AI-driven cross-token yield optimization system
 * @dev Extends YieldOptimizer with batch operations and cross-token functionality
 */
contract EnhancedYieldOptimizer is YieldOptimizer {
    using SafeTransferLib for ERC20;

    /// @notice Mapping of authorized AI backends
    mapping(address => bool) public authorizedAIBackends;

    /// @notice Enhanced Chainlink Feed Manager
    EnhancedChainlinkFeedManager public immutable enhancedFeedManager;

    /// @notice Maximum cross-token slippage (3%)
    uint256 public maxCrossTokenSlippage = 300;

    /// @notice Minimum yield improvement required for rebalancing (0.5%)
    uint256 public minYieldImprovementBps = 50;

    /// @notice Maximum tokens per cross-token operation
    uint256 public maxTokensPerOperation = 5;

    /// @notice Mapping to track cross-token operations
    mapping(bytes32 => bool) public executedCrossTokenOperations;

    /// @notice Cross-token rebalance parameters
    struct CrossTokenRebalanceParams {
        address[] fromTokens;
        address[] toTokens;
        uint256[] amounts;
        uint256[] minOutputAmounts;
        uint256 maxSlippage;
        uint256 deadline;
        bytes routeData; // DEX routing information
        bytes32 operationHash;
    }

    /// @notice Events
    event CrossTokenDepositExecuted(
        address indexed user,
        address indexed inputToken,
        uint256 inputAmount,
        address[] outputTokens,
        uint256[] outputAmounts,
        uint256[] protocolShares,
        uint256 totalExpectedAPY
    );

    event CrossTokenRebalanceExecuted(
        address indexed initiator,
        address[] fromTokens,
        address[] toTokens,
        uint256[] amounts,
        uint256 oldExpectedAPY,
        uint256 newExpectedAPY
    );

    modifier onlyAuthorizedAI() {
        require(authorizedAIBackends[msg.sender], "Not authorized AI backend");
        _;
    }

    constructor(
        address _ccipMessenger,
        address _chainlinkFeedManager,
        address _enhancedFeedManager,
        address _admin
    ) YieldOptimizer(_ccipMessenger, _chainlinkFeedManager, _admin) {
        enhancedFeedManager = EnhancedChainlinkFeedManager(
            _enhancedFeedManager
        );
    }

    /**
     * @notice Authorize an AI backend address
     * @param aiBackend Address of the AI backend service
     */
    function authorizeAIBackend(address aiBackend) external onlyAdmin {
        require(aiBackend != address(0), "Invalid AI backend address");
        authorizedAIBackends[aiBackend] = true;
    }

    /**
     * @notice Revoke AI backend authorization
     * @param aiBackend Address of the AI backend service
     */
    function revokeAIBackend(address aiBackend) external onlyAdmin {
        authorizedAIBackends[aiBackend] = false;
    }

    /**
     * @notice Batch deposit function for AI backend operations
     * @param tokens Array of tokens to deposit
     * @param amounts Array of amounts for each token
     * @param beneficiary User address to credit deposits to
     * @param minShares Minimum shares expected for slippage protection
     * @return totalShares Array of shares received for each token
     */
    function batchDepositFromAI(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address beneficiary,
        uint256[] calldata minShares
    )
        external
        onlyAuthorizedAI
        nonReentrant
        whenNotStopped
        returns (uint256[] memory totalShares)
    {
        require(tokens.length <= maxTokensPerOperation, "Too many tokens");
        require(tokens.length == amounts.length, "Array length mismatch");
        require(tokens.length == minShares.length, "Array length mismatch");
        require(beneficiary != address(0), "Invalid beneficiary");

        totalShares = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            require(amounts[i] > 0, "Invalid amount");

            // Transfer tokens from AI backend
            ERC20(tokens[i]).safeTransferFrom(
                msg.sender,
                address(this),
                amounts[i]
            );

            // Deposit to yield farming protocols for this token
            totalShares[i] = amounts[i]; // Simplified 1:1 ratio

            require(totalShares[i] >= minShares[i], "Insufficient shares");
        }

        uint256 totalExpectedAPY = _calculateBatchExpectedAPY(tokens, amounts);

        emit CrossTokenDepositExecuted(
            beneficiary,
            address(0),
            0,
            tokens,
            amounts,
            totalShares,
            totalExpectedAPY
        );

        return totalShares;
    }

    /**
     * @notice Validate swap rates against Chainlink price feeds
     * @param inputToken Token being swapped from
     * @param outputToken Token being swapped to
     * @param amountIn Input amount
     * @param expectedAmountOut Expected output amount
     * @return isValid Whether the swap rates are acceptable
     */
    function validateSwapRates(
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 expectedAmountOut
    ) external view returns (bool isValid) {
        EnhancedChainlinkFeedManager.SwapValidation
            memory validation = enhancedFeedManager.validateSwapExecution(
                inputToken,
                outputToken,
                amountIn,
                expectedAmountOut
            );

        return
            validation.isValidSwap &&
            validation.slippagePercent <= maxCrossTokenSlippage;
    }

    /**
     * @notice Execute cross-token rebalancing operations
     * @param params Rebalancing parameters including token swaps and allocations
     */
    function rebalanceAcrossTokens(
        CrossTokenRebalanceParams calldata params
    ) external onlyAuthorizedAI nonReentrant whenNotStopped {
        require(params.deadline > block.timestamp, "Operation expired");
        require(
            params.fromTokens.length == params.toTokens.length,
            "Array length mismatch"
        );
        require(
            params.maxSlippage <= maxCrossTokenSlippage,
            "Slippage too high"
        );
        require(
            !executedCrossTokenOperations[params.operationHash],
            "Already executed"
        );

        executedCrossTokenOperations[params.operationHash] = true;

        uint256 oldExpectedAPY = _calculatePortfolioAPY(params.fromTokens);
        uint256 newExpectedAPY = _calculatePortfolioAPY(params.toTokens);

        require(
            newExpectedAPY >= oldExpectedAPY + minYieldImprovementBps,
            "Insufficient yield improvement"
        );

        emit CrossTokenRebalanceExecuted(
            msg.sender,
            params.fromTokens,
            params.toTokens,
            params.amounts,
            oldExpectedAPY,
            newExpectedAPY
        );
    }

    /**
     * @notice Update cross-token operation parameters
     * @param _maxSlippage New maximum slippage
     * @param _minYieldImprovement New minimum yield improvement
     * @param _maxTokens New maximum tokens per operation
     */
    function updateCrossTokenParams(
        uint256 _maxSlippage,
        uint256 _minYieldImprovement,
        uint256 _maxTokens
    ) external onlyAdmin {
        require(_maxSlippage <= 1000, "Slippage too high");
        require(_minYieldImprovement <= 500, "Improvement too high");
        require(_maxTokens <= 10, "Too many tokens");

        maxCrossTokenSlippage = _maxSlippage;
        minYieldImprovementBps = _minYieldImprovement;
        maxTokensPerOperation = _maxTokens;
    }

    /**
     * @notice Calculate expected APY for a batch of tokens
     * @param tokens Array of token addresses
     * @param amounts Array of amounts
     * @return expectedAPY Weighted average expected APY
     */
    function _calculateBatchExpectedAPY(
        address[] memory tokens,
        uint256[] memory amounts
    ) internal view returns (uint256 expectedAPY) {
        uint256 totalValue = 0;
        uint256 weightedAPY = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                uint256 tokenAPY = _getTokenExpectedAPY(tokens[i]);
                weightedAPY += tokenAPY * amounts[i];
                totalValue += amounts[i];
            }
        }

        return totalValue > 0 ? weightedAPY / totalValue : 0;
    }

    /**
     * @notice Calculate portfolio APY for given tokens
     * @param tokens Array of token addresses
     * @return portfolioAPY Portfolio APY
     */
    function _calculatePortfolioAPY(
        address[] memory tokens
    ) internal view returns (uint256 portfolioAPY) {
        if (tokens.length == 0) return 0;

        uint256 totalAPY = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            totalAPY += _getTokenExpectedAPY(tokens[i]);
        }

        return totalAPY / tokens.length;
    }

    /**
     * @notice Get expected APY for a token
     * @param token Token address
     * @return expectedAPY Expected APY in basis points
     */
    function _getTokenExpectedAPY(
        address token
    ) internal view returns (uint256 expectedAPY) {
        uint256 projectedAPY = enhancedFeedManager.projectedAPYs(token);
        return projectedAPY > 0 ? projectedAPY : 500; // 5% default
    }
}
