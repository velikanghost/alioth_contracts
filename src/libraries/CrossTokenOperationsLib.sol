// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CrossTokenOperationsLib
 * @notice Mathematical operations for cross-token yield optimization
 * @dev Implements algorithms for optimal allocation across different tokens and protocols
 */
library CrossTokenOperationsLib {
    /// @notice Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10000;

    /// @notice Minimum allocation percentage (1%)
    uint256 public constant MIN_ALLOCATION_BPS = 100;

    /// @notice Maximum number of tokens in a single operation
    uint256 public constant MAX_TOKENS_PER_OPERATION = 10;

    /// @notice Precision multiplier for calculations
    uint256 public constant PRECISION = 1e18;

    struct CrossTokenAllocation {
        address[] targetTokens;
        uint256[] percentages; // in basis points
        uint256[] expectedYields; // in basis points (APY)
        uint256[] riskScores; // 0-10000 (higher = more risky)
        uint256 totalExpectedAPY; // weighted average APY
        uint256 riskAdjustedReturn; // Sharpe ratio * PRECISION
    }

    struct TokenMetrics {
        address token;
        uint256 priceUSD; // price in USD with 8 decimals
        uint256 currentAPY; // in basis points
        uint256 volatility; // in basis points (annualized)
        uint256 liquidityDepth; // in USD with 8 decimals
        uint256 marketCap; // in USD with 8 decimals
        uint256 protocolCount; // number of protocols supporting this token
    }

    struct OptimizationParams {
        uint256 riskTolerance; // 0-10000 (higher = more risk tolerance)
        uint256 diversificationWeight; // 0-10000 (weight of diversification in optimization)
        uint256 yieldWeight; // 0-10000 (weight of yield in optimization)
        uint256 liquidityWeight; // 0-10000 (weight of liquidity in optimization)
        uint256 maxSingleTokenAllocation; // maximum percentage for single token (in BPS)
    }

    /// @notice Custom errors
    error InvalidTokenCount();
    error InvalidAllocation();
    error ExcessiveRisk();
    error InsufficientLiquidity();

    /**
     * @notice Calculate optimal cross-token allocation
     * @param inputToken The token being deposited by user
     * @param inputAmount Amount being deposited
     * @param availableTokens Tokens available for yield farming
     * @param tokenMetrics Metrics for each available token
     * @return allocation Optimal allocation across tokens
     */
    function calculateOptimalCrossTokenAllocation(
        address inputToken,
        uint256 inputAmount,
        address[] memory availableTokens,
        TokenMetrics[] memory tokenMetrics
    ) internal pure returns (CrossTokenAllocation memory allocation) {
        if (
            availableTokens.length == 0 ||
            availableTokens.length > MAX_TOKENS_PER_OPERATION
        ) {
            revert InvalidTokenCount();
        }

        // Calculate optimal weights
        uint256[] memory weights = _calculateOptimalWeights(tokenMetrics);

        // Build allocation result
        allocation.targetTokens = availableTokens;
        allocation.percentages = weights;
        allocation.expectedYields = _extractYields(tokenMetrics);
        allocation.riskScores = _calculateRiskScores(tokenMetrics);
        allocation.totalExpectedAPY = _calculateWeightedAPY(
            allocation.expectedYields,
            weights
        );
        allocation.riskAdjustedReturn = _calculateRiskAdjustedReturn(
            allocation
        );

        return allocation;
    }

    /**
     * @notice Validate cross-token operation parameters
     * @param allocation Proposed allocation
     * @param maxSlippage Maximum allowed slippage in basis points
     * @param minYieldImprovement Minimum yield improvement required in basis points
     * @return isValid Whether the operation should proceed
     */
    function validateCrossTokenOperation(
        CrossTokenAllocation memory allocation,
        uint256 maxSlippage,
        uint256 minYieldImprovement
    ) internal pure returns (bool isValid) {
        // Check allocation validity
        if (!_isValidAllocation(allocation)) {
            return false;
        }

        // Check if yield improvement meets minimum threshold
        if (allocation.totalExpectedAPY < minYieldImprovement) {
            return false;
        }

        // Check risk tolerance
        if (_calculatePortfolioRisk(allocation) > 8000) {
            // 80% max risk
            return false;
        }

        return true;
    }

    /**
     * @notice Calculate optimal weights using simplified optimization
     * @param tokenMetrics Token metrics array
     * @return weights Optimal weights in basis points
     */
    function _calculateOptimalWeights(
        TokenMetrics[] memory tokenMetrics
    ) private pure returns (uint256[] memory weights) {
        uint256 tokenCount = tokenMetrics.length;
        weights = new uint256[](tokenCount);

        uint256[] memory scores = new uint256[](tokenCount);
        uint256 totalScore = 0;

        for (uint256 i = 0; i < tokenCount; i++) {
            // Simple scoring: yield/risk ratio
            uint256 riskScore = _calculateTokenRisk(tokenMetrics[i]);
            if (riskScore == 0) riskScore = 1; // Avoid division by zero

            scores[i] = (tokenMetrics[i].currentAPY * PRECISION) / riskScore;
            totalScore += scores[i];
        }

        // Distribute weights proportionally
        for (uint256 i = 0; i < tokenCount; i++) {
            if (totalScore > 0) {
                weights[i] = (scores[i] * MAX_BPS) / totalScore;

                // Apply minimum allocation constraint
                if (weights[i] < MIN_ALLOCATION_BPS && weights[i] > 0) {
                    weights[i] = MIN_ALLOCATION_BPS;
                }
            }
        }

        // Normalize weights
        _normalizeWeights(weights);

        return weights;
    }

    /**
     * @notice Extract yields from token metrics
     * @param tokenMetrics Token metrics array
     * @return yields Array of yields
     */
    function _extractYields(
        TokenMetrics[] memory tokenMetrics
    ) private pure returns (uint256[] memory yields) {
        yields = new uint256[](tokenMetrics.length);
        for (uint256 i = 0; i < tokenMetrics.length; i++) {
            yields[i] = tokenMetrics[i].currentAPY;
        }
        return yields;
    }

    /**
     * @notice Calculate risk scores for tokens
     * @param tokenMetrics Token metrics array
     * @return riskScores Array of risk scores
     */
    function _calculateRiskScores(
        TokenMetrics[] memory tokenMetrics
    ) private pure returns (uint256[] memory riskScores) {
        riskScores = new uint256[](tokenMetrics.length);
        for (uint256 i = 0; i < tokenMetrics.length; i++) {
            riskScores[i] = _calculateTokenRisk(tokenMetrics[i]);
        }
        return riskScores;
    }

    /**
     * @notice Calculate token risk score
     * @param metrics Token metrics
     * @return riskScore Risk score (0-10000)
     */
    function _calculateTokenRisk(
        TokenMetrics memory metrics
    ) private pure returns (uint256 riskScore) {
        // Base risk is volatility
        uint256 baseRisk = metrics.volatility;

        // Liquidity risk
        uint256 liquidityRisk = metrics.liquidityDepth < 100000 * 1e8
            ? 1000
            : 0; // 10% penalty if liquidity < $100k

        // Market cap risk
        uint256 marketCapRisk = metrics.marketCap < 1000000 * 1e8 ? 500 : 0; // 5% penalty if market cap < $1M

        riskScore = baseRisk + liquidityRisk + marketCapRisk;

        // Cap at maximum risk
        if (riskScore > MAX_BPS) {
            riskScore = MAX_BPS;
        }

        return riskScore;
    }

    /**
     * @notice Calculate weighted average APY
     * @param expectedReturns Expected returns array
     * @param weights Weights array
     * @return weightedAPY Weighted average APY
     */
    function _calculateWeightedAPY(
        uint256[] memory expectedReturns,
        uint256[] memory weights
    ) private pure returns (uint256 weightedAPY) {
        uint256 totalWeightedReturn = 0;

        for (uint256 i = 0; i < expectedReturns.length; i++) {
            totalWeightedReturn += (expectedReturns[i] * weights[i]) / MAX_BPS;
        }

        return totalWeightedReturn;
    }

    /**
     * @notice Calculate risk-adjusted return for allocation
     * @param allocation Token allocation
     * @return riskAdjustedReturn Risk-adjusted return
     */
    function _calculateRiskAdjustedReturn(
        CrossTokenAllocation memory allocation
    ) private pure returns (uint256 riskAdjustedReturn) {
        uint256 portfolioRisk = _calculatePortfolioRisk(allocation);
        if (portfolioRisk == 0) portfolioRisk = 1; // Avoid division by zero

        uint256 riskFreeRate = 300; // 3%
        uint256 excessReturn = allocation.totalExpectedAPY > riskFreeRate
            ? allocation.totalExpectedAPY - riskFreeRate
            : 0;

        riskAdjustedReturn = (excessReturn * PRECISION) / portfolioRisk;

        return riskAdjustedReturn;
    }

    /**
     * @notice Check if allocation is valid
     * @param allocation Token allocation
     * @return isValid Whether allocation is valid
     */
    function _isValidAllocation(
        CrossTokenAllocation memory allocation
    ) private pure returns (bool isValid) {
        if (allocation.targetTokens.length == 0) return false;
        if (allocation.targetTokens.length != allocation.percentages.length)
            return false;

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < allocation.percentages.length; i++) {
            totalPercentage += allocation.percentages[i];
        }

        // Allow for small rounding errors (±1%)
        return totalPercentage >= 9900 && totalPercentage <= 10100;
    }

    /**
     * @notice Calculate portfolio risk
     * @param allocation Token allocation
     * @return portfolioRisk Portfolio risk score
     */
    function _calculatePortfolioRisk(
        CrossTokenAllocation memory allocation
    ) private pure returns (uint256 portfolioRisk) {
        uint256 weightedRisk = 0;

        for (uint256 i = 0; i < allocation.riskScores.length; i++) {
            weightedRisk +=
                (allocation.riskScores[i] * allocation.percentages[i]) /
                MAX_BPS;
        }

        return weightedRisk;
    }

    /**
     * @notice Normalize weights to sum to MAX_BPS
     * @param weights Weights array to normalize
     */
    function _normalizeWeights(uint256[] memory weights) private pure {
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }

        if (totalWeight > 0 && totalWeight != MAX_BPS) {
            for (uint256 i = 0; i < weights.length; i++) {
                weights[i] = (weights[i] * MAX_BPS) / totalWeight;
            }
        }
    }
}
