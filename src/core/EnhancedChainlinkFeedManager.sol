// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../libraries/DynamicAllocationLib.sol";
import "../libraries/CrossTokenOperationsLib.sol";

/**
 * @title EnhancedChainlinkFeedManager
 * @notice Enhanced Chainlink feed management
 */
contract EnhancedChainlinkFeedManager is AccessControl {
    using CrossTokenOperationsLib for *;

    bytes32 public constant FEED_MANAGER_ROLE = keccak256("FEED_MANAGER_ROLE");

    /// @notice Mapping from token address to its Chainlink feeds
    mapping(address => DynamicAllocationLib.ChainlinkFeeds) public tokenFeeds;

    /// @notice Array of supported tokens
    address[] public supportedTokens;

    mapping(address => bool) public isSupportedToken;

    event FeedsUpdated(
        address indexed token,
        address priceFeed,
        address rateFeed,
        address volatilityFeed
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

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

    /// @notice Enhanced events
    event SwapValidationPerformed(
        address indexed inputToken,
        address indexed outputToken,
        bool isValid
    );
    event ProjectedAPYUpdated(address indexed token, uint256 newAPY);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEED_MANAGER_ROLE, admin);
    }

    /**
     * @notice Add or update Chainlink feeds for a token
     * @param token Token address
     * @param priceFeed Price feed address (required)
     * @param rateFeed Rate/APY feed address (optional)
     * @param volatilityFeed Volatility feed address (optional)
     */
    function setTokenFeeds(
        address token,
        address priceFeed,
        address rateFeed,
        address volatilityFeed
    ) public onlyRole(FEED_MANAGER_ROLE) {
        require(token != address(0), "Invalid token address");
        require(priceFeed != address(0), "Price feed required");

        if (!isSupportedToken[token]) {
            supportedTokens.push(token);
            isSupportedToken[token] = true;
            emit TokenAdded(token);
        }

        tokenFeeds[token] = DynamicAllocationLib.ChainlinkFeeds({
            priceFeed: AggregatorV3Interface(priceFeed),
            rateFeed: AggregatorV3Interface(rateFeed),
            volatilityFeed: AggregatorV3Interface(volatilityFeed)
        });

        emit FeedsUpdated(token, priceFeed, rateFeed, volatilityFeed);
    }

    /**
     * @notice Remove a token and its feeds
     * @param token Token address to remove
     */
    function removeToken(address token) external onlyRole(FEED_MANAGER_ROLE) {
        require(isSupportedToken[token], "Token not supported");

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
                supportedTokens.pop();
                break;
            }
        }

        delete tokenFeeds[token];
        isSupportedToken[token] = false;

        emit TokenRemoved(token);
    }

    /**
     * @notice Get Chainlink feeds for a token
     * @param token Token address
     * @return feeds ChainlinkFeeds struct containing all feed addresses
     */
    function getTokenFeeds(
        address token
    ) external view returns (DynamicAllocationLib.ChainlinkFeeds memory feeds) {
        require(isSupportedToken[token], "Token not supported");
        return tokenFeeds[token];
    }

    /**
     * @notice Get all supported tokens
     * @return tokens Array of supported token addresses
     */
    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens)
    {
        return supportedTokens;
    }

    /**
     * @notice Get number of supported tokens
     * @return count Number of supported tokens
     */
    function getSupportedTokensCount() external view returns (uint256 count) {
        return supportedTokens.length;
    }

    /**
     * @notice Check if token has all required feeds
     * @param token Token address
     * @return hasPrice True if token has price feed
     * @return hasRate True if token has rate feed
     * @return hasVolatility True if token has volatility feed
     */
    function checkFeedAvailability(
        address token
    ) external view returns (bool hasPrice, bool hasRate, bool hasVolatility) {
        if (!isSupportedToken[token]) {
            return (false, false, false);
        }

        DynamicAllocationLib.ChainlinkFeeds memory feeds = tokenFeeds[token];
        hasPrice = address(feeds.priceFeed) != address(0);
        hasRate = address(feeds.rateFeed) != address(0);
        hasVolatility = address(feeds.volatilityFeed) != address(0);
    }

    /**
     * @notice Batch set feeds for multiple tokens
     * @param tokens Array of token addresses
     * @param priceFeeds Array of price feed addresses
     * @param rateFeeds Array of rate feed addresses
     * @param volatilityFeeds Array of volatility feed addresses
     */
    function batchSetTokenFeeds(
        address[] calldata tokens,
        address[] calldata priceFeeds,
        address[] calldata rateFeeds,
        address[] calldata volatilityFeeds
    ) external onlyRole(FEED_MANAGER_ROLE) {
        require(
            tokens.length == priceFeeds.length &&
                tokens.length == rateFeeds.length &&
                tokens.length == volatilityFeeds.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            setTokenFeeds(
                tokens[i],
                priceFeeds[i],
                rateFeeds[i],
                volatilityFeeds[i]
            );
        }
    }

    /**
     * @notice Emergency function to update a single feed
     * @param token Token address
     * @param feedType Feed type (0=price, 1=rate, 2=volatility)
     * @param newFeed New feed address
     */
    function emergencyUpdateFeed(
        address token,
        uint8 feedType,
        address newFeed
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isSupportedToken[token], "Token not supported");
        require(feedType <= 2, "Invalid feed type");

        DynamicAllocationLib.ChainlinkFeeds storage feeds = tokenFeeds[token];

        if (feedType == 0) {
            require(newFeed != address(0), "Price feed cannot be zero");
            feeds.priceFeed = AggregatorV3Interface(newFeed);
        } else if (feedType == 1) {
            feeds.rateFeed = AggregatorV3Interface(newFeed);
        } else {
            feeds.volatilityFeed = AggregatorV3Interface(newFeed);
        }

        emit FeedsUpdated(
            token,
            address(feeds.priceFeed),
            address(feeds.rateFeed),
            address(feeds.volatilityFeed)
        );
    }

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
     * @notice Validate token price with Chainlink feeds
     * @param token Token address to validate
     * @param amount Amount to validate
     * @return isValid Whether price validation passed
     */
    function validateTokenPrice(
        address token,
        uint256 amount
    ) external view returns (bool isValid) {
        require(isSupportedToken[token], "Token not supported");
        require(amount > 0, "Invalid amount");

        uint256 price = _getTokenPrice(token);
        return price > 0;
    }

    /**
     * @notice Get protocol APY for a specific token
     * @param protocol Protocol enumeration
     * @param token Token address
     * @return apy Protocol APY in basis points
     */
    function getProtocolAPY(
        uint8 protocol,
        address token
    ) external view returns (uint256 apy) {
        require(isSupportedToken[token], "Token not supported");

        if (protocol == 0) {
            return _getAaveAPY(token);
        } else if (protocol == 1) {
            return _getCompoundAPY(token);
        } else {
            revert("Invalid protocol");
        }
    }

    /**
     * @notice Get best protocol APY for a token
     * @param token Token address
     * @return bestAPY Best available APY across all protocols
     */
    function getBestProtocolAPY(
        address token
    ) external view returns (uint256 bestAPY) {
        require(isSupportedToken[token], "Token not supported");

        uint256 aaveAPY = _getAaveAPY(token);
        uint256 compoundAPY = _getCompoundAPY(token);

        bestAPY = aaveAPY;
        if (compoundAPY > bestAPY) bestAPY = compoundAPY;

        return bestAPY;
    }

    /**
     * @notice Validate current market prices for token
     * @param tokens Array of token addresses to validate
     * @return isValid Whether all prices are valid and fresh
     */
    function validateCurrentPrices(
        address[] calldata tokens
    ) external returns (bool isValid) {
        isValid = true;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isSupportedToken[tokens[i]]) {
                isValid = false;
                break;
            }

            uint256 price = _getTokenPrice(tokens[i]);
            if (price == 0) {
                isValid = false;
                break;
            }
        }

        if (isValid) {
            emit SwapValidationPerformed(address(0), address(0), true);
        }

        return isValid;
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

    /**
     * @notice Get estimated Aave APY for a token
     * @param token Token address
     * @return apy Estimated Aave APY in basis points
     */
    function _getAaveAPY(address token) internal view returns (uint256 apy) {
        // For MVP, return mock APYs based on token type
        uint256 baseAPY = projectedAPYs[token] > 0 ? projectedAPYs[token] : 500; // 5% base
        return baseAPY + 100; // Aave premium: +1%
    }

    /**
     * @notice Get estimated Compound APY for a token
     * @param token Token address
     * @return apy Estimated Compound APY in basis points
     */
    function _getCompoundAPY(
        address token
    ) internal view returns (uint256 apy) {
        // For MVP, return mock APYs based on token type
        uint256 baseAPY = projectedAPYs[token] > 0 ? projectedAPYs[token] : 500; // 5% base
        return baseAPY + 50; // Compound premium: +0.5%
    }
}
