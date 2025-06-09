// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/ChainlinkFeedManager.sol";
import "../libraries/CrossTokenOperationsLib.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title EnhancedChainlinkFeedManager
 * @notice Enhanced Chainlink feed management with AI-specific functionality for cross-token analysis
 * @dev Extends ChainlinkFeedManager with market analysis and swap validation capabilities
 */
contract EnhancedChainlinkFeedManager is ChainlinkFeedManager {
    using CrossTokenOperationsLib for *;

    /// @notice Maximum age for price data (1 hour)
    uint256 public constant MAX_PRICE_AGE = 3600;

    /// @notice Maximum allowed slippage for swap validation (5%)
    uint256 public constant MAX_SWAP_SLIPPAGE = 500;

    /// @notice Precision for percentage calculations
    uint256 public constant PERCENTAGE_PRECISION = 10000;

    struct MarketAnalysis {
        address[] tokens;
        uint256[] pricesUSD;
        uint256[] expectedYields;
        uint256[] volatilityScores;
        uint256[] riskScores;
        uint256 timestamp;
    }

    struct YieldComparison {
        address[] tokens;
        uint256[] currentAPYs;
        uint256[] projectedAPYs;
        uint256[] riskAdjustedReturns;
        uint256 recommendedAllocation;
        uint256 timestamp;
    }

    struct SwapValidation {
        bool isValidSwap;
        uint256 slippagePercent;
        uint256 expectedPrice;
        uint256 actualPrice;
        uint256 timestamp;
    }

    /// @notice Mapping to store yield projections
    mapping(address => uint256) public projectedAPYs;

    /// @notice Events
    event SwapValidationPerformed(
        address indexed inputToken,
        address indexed outputToken,
        bool isValid
    );
    event ProjectedAPYUpdated(address indexed token, uint256 newAPY);

    constructor(address admin) ChainlinkFeedManager(admin) {}

    /**
     * @notice Get comprehensive market analysis for AI decision making
     * @param tokens Array of tokens to analyze
     * @return analysis Complete market analysis data
     */
    function getMarketAnalysis(
        address[] calldata tokens
    ) external view returns (MarketAnalysis memory analysis) {
        require(tokens.length > 0, "No tokens provided");

        analysis.tokens = tokens;
        analysis.pricesUSD = new uint256[](tokens.length);
        analysis.expectedYields = new uint256[](tokens.length);
        analysis.volatilityScores = new uint256[](tokens.length);
        analysis.riskScores = new uint256[](tokens.length);
        analysis.timestamp = block.timestamp;

        for (uint256 i = 0; i < tokens.length; i++) {
            analysis.pricesUSD[i] = _getTokenPrice(tokens[i]);
            analysis.expectedYields[i] = projectedAPYs[tokens[i]] > 0
                ? projectedAPYs[tokens[i]]
                : _estimateTokenAPY(tokens[i]);
            analysis.volatilityScores[i] = _calculateVolatilityScore(tokens[i]);
            analysis.riskScores[i] = _calculateRiskScore(tokens[i]);
        }

        return analysis;
    }

    /**
     * @notice Validate swap execution against Chainlink prices
     * @param inputToken Input token address
     * @param outputToken Output token address
     * @param inputAmount Input amount
     * @param outputAmount Output amount
     * @return validation Swap validation result
     */
    function validateSwapExecution(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (SwapValidation memory validation) {
        require(inputToken != outputToken, "Same token swap");
        require(inputAmount > 0, "Invalid input amount");
        require(outputAmount > 0, "Invalid output amount");

        uint256 inputPrice = _getTokenPrice(inputToken);
        uint256 outputPrice = _getTokenPrice(outputToken);

        require(inputPrice > 0 && outputPrice > 0, "Invalid price data");

        uint256 expectedOutput = (inputAmount * inputPrice) / outputPrice;

        uint256 slippagePercent;
        if (expectedOutput > outputAmount) {
            slippagePercent =
                ((expectedOutput - outputAmount) * PERCENTAGE_PRECISION) /
                expectedOutput;
        } else {
            slippagePercent = 0;
        }

        bool isValid = slippagePercent <= MAX_SWAP_SLIPPAGE;

        validation = SwapValidation({
            isValidSwap: isValid,
            slippagePercent: slippagePercent,
            expectedPrice: (inputPrice * PERCENTAGE_PRECISION) / outputPrice,
            actualPrice: (inputAmount * PERCENTAGE_PRECISION) / outputAmount,
            timestamp: block.timestamp
        });

        return validation;
    }

    /**
     * @notice Compare yields across different tokens
     * @param tokens Tokens to compare
     * @param amounts Amounts for each token
     * @return comparison Comprehensive yield comparison
     */
    function compareTokenYields(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external view returns (YieldComparison memory comparison) {
        require(tokens.length == amounts.length, "Array length mismatch");
        require(tokens.length > 0, "No tokens provided");

        comparison.tokens = tokens;
        comparison.currentAPYs = new uint256[](tokens.length);
        comparison.projectedAPYs = new uint256[](tokens.length);
        comparison.riskAdjustedReturns = new uint256[](tokens.length);
        comparison.timestamp = block.timestamp;

        uint256 bestScore = 0;
        uint256 bestIndex = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            comparison.currentAPYs[i] = _estimateTokenAPY(tokens[i]);
            comparison.projectedAPYs[i] = projectedAPYs[tokens[i]] > 0
                ? projectedAPYs[tokens[i]]
                : comparison.currentAPYs[i];

            uint256 riskScore = _calculateRiskScore(tokens[i]);
            comparison.riskAdjustedReturns[i] = riskScore > 0
                ? (comparison.projectedAPYs[i] * PERCENTAGE_PRECISION) /
                    riskScore
                : 0;

            if (comparison.riskAdjustedReturns[i] > bestScore) {
                bestScore = comparison.riskAdjustedReturns[i];
                bestIndex = i;
            }
        }

        comparison.recommendedAllocation = bestIndex;
        return comparison;
    }

    /**
     * @notice Update projected APY for a token
     * @param token Token address
     * @param newAPY New projected APY in basis points
     */
    function updateProjectedAPY(
        address token,
        uint256 newAPY
    ) external onlyRole(FEED_MANAGER_ROLE) {
        require(isSupportedToken[token], "Token not supported");
        require(newAPY <= 10000, "APY too high");

        projectedAPYs[token] = newAPY;
        emit ProjectedAPYUpdated(token, newAPY);
    }

    /**
     * @notice Get token price from Chainlink feeds
     * @param token Token address
     * @return price Token price in USD (8 decimals)
     */
    function _getTokenPrice(
        address token
    ) internal view returns (uint256 price) {
        if (!isSupportedToken[token]) {
            return 0;
        }

        DynamicAllocationLib.ChainlinkFeeds memory feeds = tokenFeeds[token];

        try feeds.priceFeed.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (block.timestamp - updatedAt > MAX_PRICE_AGE) {
                return 0;
            }

            if (answer <= 0) {
                return 0;
            }

            return uint256(answer);
        } catch {
            return 0;
        }
    }

    /**
     * @notice Estimate token APY based on available data
     * @param token Token address
     * @return apy Estimated APY in basis points
     */
    function _estimateTokenAPY(
        address token
    ) internal view returns (uint256 apy) {
        if (!isSupportedToken[token]) {
            return 0;
        }

        DynamicAllocationLib.ChainlinkFeeds memory feeds = tokenFeeds[token];

        if (address(feeds.rateFeed) != address(0)) {
            try feeds.rateFeed.latestRoundData() returns (
                uint80,
                int256 answer,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                if (answer > 0 && block.timestamp - updatedAt < MAX_PRICE_AGE) {
                    return uint256(answer);
                }
            } catch {
                // Continue to fallback
            }
        }

        return 500; // 5% default APY
    }

    /**
     * @notice Calculate volatility score for a token
     * @param token Token address
     * @return volatilityScore Volatility score (0-10000)
     */
    function _calculateVolatilityScore(
        address token
    ) internal view returns (uint256 volatilityScore) {
        if (!isSupportedToken[token]) {
            return 5000; // Medium volatility default
        }

        DynamicAllocationLib.ChainlinkFeeds memory feeds = tokenFeeds[token];

        if (address(feeds.volatilityFeed) != address(0)) {
            try feeds.volatilityFeed.latestRoundData() returns (
                uint80,
                int256 answer,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                if (answer > 0 && block.timestamp - updatedAt < MAX_PRICE_AGE) {
                    return uint256(answer);
                }
            } catch {
                // Continue to fallback
            }
        }

        return 3000; // 30% volatility default
    }

    /**
     * @notice Calculate risk score for a token
     * @param token Token address
     * @return riskScore Risk score (0-10000)
     */
    function _calculateRiskScore(
        address token
    ) internal view returns (uint256 riskScore) {
        uint256 volatility = _calculateVolatilityScore(token);
        uint256 liquidityRisk = 500; // 5% base liquidity risk
        uint256 protocolRisk = 300; // 3% base protocol risk

        riskScore = volatility + liquidityRisk + protocolRisk;

        if (riskScore > PERCENTAGE_PRECISION) {
            riskScore = PERCENTAGE_PRECISION;
        }

        return riskScore;
    }
}
