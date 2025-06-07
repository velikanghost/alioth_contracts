// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IProtocolAdapter.sol";
import "./MathLib.sol";
import "./ValidationLib.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DynamicAllocationLib
 * @notice Library for Chainlink data feed-driven dynamic allocation across DeFi protocols
 * @dev Uses Chainlink price feeds and rate feeds to determine optimal allocation weights
 */
library DynamicAllocationLib {
    using MathLib for uint256;
    using ValidationLib for uint256;

    /// @notice Maximum allocation to any single protocol (safety limit)
    uint256 public constant MAX_SINGLE_PROTOCOL_ALLOCATION = 6000; // 60%

    /// @notice Minimum APY difference to justify reallocation
    uint256 public constant MIN_APY_DIFFERENCE = 50; // 0.5%

    /// @notice Risk-adjusted return penalty multiplier
    uint256 public constant RISK_PENALTY_MULTIPLIER = 2;

    /// @notice Maximum age for price/rate data (1 hour)
    uint256 public constant MAX_DATA_AGE = 3600;

    /// @notice Minimum protocols to diversify across
    uint256 public constant MIN_DIVERSIFICATION_PROTOCOLS = 2;

    struct ChainlinkFeeds {
        AggregatorV3Interface priceFeed; // Price feed for the token
        AggregatorV3Interface rateFeed; // APY/rate feed for DeFi rates
        AggregatorV3Interface volatilityFeed; // Volatility feed (optional)
    }

    struct ProtocolMetrics {
        address adapter;
        uint256 currentAPY;
        uint256 chainlinkAPY; // APY from Chainlink rate feeds
        uint256 riskScore;
        uint256 healthScore;
        uint256 liquidityDepth;
        uint256 utilizationRate;
        uint256 maxAllocation;
        bool isOperational;
        uint256 priceUSD; // Current price from Chainlink
        uint256 volatilityScore; // Volatility from Chainlink
        uint256 marketCapWeight; // Weight based on market cap/TVL
    }

    struct AllocationStrategy {
        uint256 riskTolerance; // 0-10000 (0 = risk averse, 10000 = risk seeking)
        uint256 liquidityPreference; // 0-10000 (0 = don't care, 10000 = high liquidity required)
        uint256 diversificationTarget; // 0-10000 (0 = concentrate, 10000 = diversify)
        uint256 apyWeight; // 0-10000 (how much to weight APY vs other factors)
        bool useChainlinkRates; // Whether to use Chainlink rate feeds over protocol rates
    }

    /**
     * @notice Calculate optimal allocation using Chainlink data feeds
     * @param protocols Array of protocol adapters to consider
     * @param token Token address for allocation
     * @param totalAmount Total amount to allocate
     * @param strategy Allocation strategy parameters
     * @param chainlinkFeeds Chainlink feed addresses for the token
     * @return allocations Array of allocation amounts per protocol
     * @return totalAllocated Total amount allocated (should equal totalAmount)
     */
    function calculateOptimalAllocation(
        address[] memory protocols,
        address token,
        uint256 totalAmount,
        AllocationStrategy memory strategy,
        ChainlinkFeeds memory chainlinkFeeds
    )
        internal
        view
        returns (uint256[] memory allocations, uint256 totalAllocated)
    {
        require(protocols.length > 0, "No protocols available");
        require(totalAmount > 0, "Amount must be positive");

        // Get market data from Chainlink feeds
        (
            uint256 tokenPriceUSD,
            uint256 marketAPY,
            uint256 volatilityScore
        ) = _getChainlinkMarketData(chainlinkFeeds);

        // Gather metrics for all protocols with Chainlink data
        ProtocolMetrics[] memory metrics = _gatherProtocolMetricsWithChainlink(
            protocols,
            token,
            tokenPriceUSD,
            marketAPY,
            volatilityScore,
            strategy.useChainlinkRates
        );

        // Filter out non-operational protocols
        ProtocolMetrics[]
            memory operationalMetrics = _filterOperationalProtocols(metrics);

        if (operationalMetrics.length == 0) {
            // No operational protocols - return empty allocation
            return (new uint256[](protocols.length), 0);
        }

        // Calculate Chainlink-enhanced allocation scores
        uint256[] memory chainlinkScores = _calculateChainlinkBasedScores(
            operationalMetrics,
            strategy
        );

        // Apply market-based diversification
        uint256[]
            memory marketBasedAllocations = _applyMarketBasedDiversification(
                chainlinkScores,
                operationalMetrics,
                totalAmount,
                strategy
            );

        // Map back to original protocol order
        allocations = _mapToOriginalOrder(
            protocols,
            operationalMetrics,
            marketBasedAllocations
        );

        // Calculate total allocated
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocated += allocations[i];
        }
    }

    /**
     * @notice Get market-aware conservative allocation strategy
     * @return strategy Conservative strategy using Chainlink data
     */
    function getChainlinkConservativeStrategy()
        internal
        pure
        returns (AllocationStrategy memory strategy)
    {
        return
            AllocationStrategy({
                riskTolerance: 3000, // 30% - Conservative
                liquidityPreference: 7000, // 70% - High liquidity preference
                diversificationTarget: 8000, // 80% - High diversification
                apyWeight: 6000, // 60% - Moderate APY focus
                useChainlinkRates: true // Use Chainlink rate feeds
            });
    }

    /**
     * @notice Get market-aware aggressive allocation strategy
     * @return strategy Aggressive strategy using Chainlink data
     */
    function getChainlinkAggressiveStrategy()
        internal
        pure
        returns (AllocationStrategy memory strategy)
    {
        return
            AllocationStrategy({
                riskTolerance: 8000, // 80% - High risk tolerance
                liquidityPreference: 3000, // 30% - Lower liquidity requirement
                diversificationTarget: 4000, // 40% - Allow concentration
                apyWeight: 9000, // 90% - Heavy APY focus
                useChainlinkRates: true // Use Chainlink rate feeds
            });
    }

    /**
     * @notice Get market-aware balanced allocation strategy
     * @return strategy Balanced strategy using Chainlink data
     */
    function getChainlinkBalancedStrategy()
        internal
        pure
        returns (AllocationStrategy memory strategy)
    {
        return
            AllocationStrategy({
                riskTolerance: 5000, // 50% - Moderate risk
                liquidityPreference: 5000, // 50% - Moderate liquidity
                diversificationTarget: 6000, // 60% - Good diversification
                apyWeight: 7000, // 70% - APY focused but not extreme
                useChainlinkRates: true // Use Chainlink rate feeds
            });
    }

    // ===== CHAINLINK INTEGRATION FUNCTIONS =====

    /**
     * @notice Get market data from Chainlink feeds
     * @param feeds Chainlink feed interfaces
     * @return priceUSD Token price in USD (8 decimals)
     * @return marketAPY Market APY from rate feeds (basis points)
     * @return volatilityScore Volatility score (basis points)
     */
    function _getChainlinkMarketData(
        ChainlinkFeeds memory feeds
    )
        internal
        view
        returns (uint256 priceUSD, uint256 marketAPY, uint256 volatilityScore)
    {
        // Get price data
        if (address(feeds.priceFeed) != address(0)) {
            try feeds.priceFeed.latestRoundData() returns (
                uint80 /* roundId */,
                int256 price,
                uint256 /* startedAt */,
                uint256 updatedAt,
                uint80 /* answeredInRound */
            ) {
                require(
                    block.timestamp - updatedAt <= MAX_DATA_AGE,
                    "Price data too old"
                );
                require(price > 0, "Invalid price data");
                priceUSD = uint256(price);
            } catch {
                priceUSD = 0; // Handle gracefully
            }
        }

        // Get rate/APY data
        if (address(feeds.rateFeed) != address(0)) {
            try feeds.rateFeed.latestRoundData() returns (
                uint80 /* roundId */,
                int256 rate,
                uint256 /* startedAt */,
                uint256 updatedAt,
                uint80 /* answeredInRound */
            ) {
                require(
                    block.timestamp - updatedAt <= MAX_DATA_AGE,
                    "Rate data too old"
                );
                require(rate >= 0, "Invalid rate data");
                marketAPY = uint256(rate);
            } catch {
                marketAPY = 0; // Handle gracefully
            }
        }

        // Get volatility data (optional)
        if (address(feeds.volatilityFeed) != address(0)) {
            try feeds.volatilityFeed.latestRoundData() returns (
                uint80 /* roundId */,
                int256 volatility,
                uint256 /* startedAt */,
                uint256 updatedAt,
                uint80 /* answeredInRound */
            ) {
                require(
                    block.timestamp - updatedAt <= MAX_DATA_AGE,
                    "Volatility data too old"
                );
                require(volatility >= 0, "Invalid volatility data");
                volatilityScore = uint256(volatility);
            } catch {
                volatilityScore = 2000; // Default 20% volatility
            }
        } else {
            volatilityScore = 2000; // Default 20% volatility
        }
    }

    function _gatherProtocolMetricsWithChainlink(
        address[] memory protocols,
        address token,
        uint256 tokenPriceUSD,
        uint256 marketAPY,
        uint256 volatilityScore,
        bool useChainlinkRates
    ) internal view returns (ProtocolMetrics[] memory metrics) {
        metrics = new ProtocolMetrics[](protocols.length);

        for (uint256 i = 0; i < protocols.length; i++) {
            IProtocolAdapter adapter = IProtocolAdapter(protocols[i]);

            // Skip if protocol doesn't support token
            if (!adapter.supportsToken(token)) {
                continue;
            }

            (bool isOperational, ) = adapter.getOperationalStatus(token);
            (
                uint256 healthScore,
                uint256 liquidityDepth,
                uint256 utilizationRate
            ) = adapter.getHealthMetrics(token);

            uint256 protocolAPY = adapter.getAPY(token);
            uint256 finalAPY = useChainlinkRates && marketAPY > 0
                ? marketAPY
                : protocolAPY;

            // Calculate market cap weight based on TVL and price
            uint256 tvl = adapter.getTVL(token);
            uint256 marketCapWeight = _calculateMarketCapWeight(
                tvl,
                tokenPriceUSD
            );

            metrics[i] = ProtocolMetrics({
                adapter: protocols[i],
                currentAPY: protocolAPY,
                chainlinkAPY: marketAPY,
                riskScore: adapter.getRiskScore(token),
                healthScore: healthScore,
                liquidityDepth: liquidityDepth,
                utilizationRate: utilizationRate,
                maxAllocation: adapter.getMaxRecommendedAllocation(token),
                isOperational: isOperational,
                priceUSD: tokenPriceUSD,
                volatilityScore: volatilityScore,
                marketCapWeight: marketCapWeight
            });
        }
    }

    function _calculateChainlinkBasedScores(
        ProtocolMetrics[] memory metrics,
        AllocationStrategy memory strategy
    ) internal pure returns (uint256[] memory scores) {
        scores = new uint256[](metrics.length);

        for (uint256 i = 0; i < metrics.length; i++) {
            ProtocolMetrics memory metric = metrics[i];

            // Use higher of protocol APY or Chainlink APY
            uint256 bestAPY = metric.chainlinkAPY > metric.currentAPY
                ? metric.chainlinkAPY
                : metric.currentAPY;

            // Base score from best available APY
            uint256 apyScore = (bestAPY * strategy.apyWeight) / 10000;

            // Volatility-adjusted risk penalty
            uint256 volatilityPenalty = (metric.volatilityScore *
                (10000 - strategy.riskTolerance)) / 100000000;

            // Market cap weight bonus (larger protocols get bonus)
            uint256 marketCapBonus = (metric.marketCapWeight * 300) / 10000; // Max 30bp

            // Health and liquidity bonuses
            uint256 healthBonus = (metric.healthScore * 200) / 10000; // Max 20bp
            uint256 liquidityBonus = metric.liquidityDepth > 1000000e18
                ? (strategy.liquidityPreference * 100) / 10000 // Max 10bp
                : 0;

            // Price data reliability bonus
            uint256 priceBonus = metric.priceUSD > 0 ? 50 : 0; // 5bp for reliable price

            // Calculate final score
            scores[i] =
                apyScore +
                marketCapBonus +
                healthBonus +
                liquidityBonus +
                priceBonus;

            // Apply penalties
            uint256 totalPenalty = volatilityPenalty;
            if (scores[i] > totalPenalty) {
                scores[i] -= totalPenalty;
            } else {
                scores[i] = 0;
            }
        }
    }

    function _applyMarketBasedDiversification(
        uint256[] memory scores,
        ProtocolMetrics[] memory metrics,
        uint256 totalAmount,
        AllocationStrategy memory strategy
    ) internal pure returns (uint256[] memory allocations) {
        allocations = new uint256[](scores.length);

        if (scores.length == 0) return allocations;

        // Calculate total score
        uint256 totalScore = 0;
        for (uint256 i = 0; i < scores.length; i++) {
            totalScore += scores[i];
        }

        if (totalScore == 0) {
            // Equal allocation if no clear winner
            uint256 equalAmount = totalAmount / scores.length;
            for (uint256 i = 0; i < scores.length; i++) {
                allocations[i] = equalAmount;
            }
            return allocations;
        }

        // Calculate market-aware proportional allocations
        for (uint256 i = 0; i < scores.length; i++) {
            uint256 proportionalAllocation = (totalAmount * scores[i]) /
                totalScore;

            // Apply maximum allocation limits
            uint256 maxAllowed = MathLib.min(
                (totalAmount * MAX_SINGLE_PROTOCOL_ALLOCATION) / 10000,
                (totalAmount * metrics[i].maxAllocation) / 10000
            );

            allocations[i] = MathLib.min(proportionalAllocation, maxAllowed);
        }

        // Ensure minimum diversification across top protocols
        if (
            strategy.diversificationTarget > 6000 &&
            scores.length >= MIN_DIVERSIFICATION_PROTOCOLS
        ) {
            allocations = _enforceMinimumDiversification(
                allocations,
                totalAmount,
                strategy
            );
        }

        return allocations;
    }

    function _calculateMarketCapWeight(
        uint256 tvl,
        uint256 priceUSD
    ) internal pure returns (uint256 weight) {
        if (tvl == 0 || priceUSD == 0) return 0;

        // Calculate market value and normalize to 0-10000 scale
        uint256 marketValue = (tvl * priceUSD) / 1e8; // Adjust for price decimals

        // Simple logarithmic scaling for market cap weight
        if (marketValue > 1000000000e18) {
            // >$1B
            weight = 10000;
        } else if (marketValue > 100000000e18) {
            // >$100M
            weight = 8000;
        } else if (marketValue > 10000000e18) {
            // >$10M
            weight = 6000;
        } else if (marketValue > 1000000e18) {
            // >$1M
            weight = 4000;
        } else {
            weight = 2000;
        }
    }

    function _enforceMinimumDiversification(
        uint256[] memory allocations,
        uint256 totalAmount,
        AllocationStrategy memory strategy
    ) internal pure returns (uint256[] memory diversified) {
        diversified = new uint256[](allocations.length);

        // Find top performing allocations
        uint256[] memory sortedIndices = _getSortedIndicesByAllocation(
            allocations
        );

        // Ensure minimum allocation to top protocols
        uint256 minAllocationPerTop = (totalAmount * 1500) / 10000; // 15% minimum each
        uint256 remainingAmount = totalAmount;

        // Allocate minimum to top 2-3 protocols
        uint256 topProtocolsToEnsure = MathLib.min(3, sortedIndices.length);
        for (
            uint256 i = 0;
            i < topProtocolsToEnsure && remainingAmount > minAllocationPerTop;
            i++
        ) {
            uint256 idx = sortedIndices[i];
            diversified[idx] = MathLib.max(
                allocations[idx],
                minAllocationPerTop
            );
            remainingAmount -= diversified[idx];
        }

        // Distribute remaining proportionally
        uint256 totalOriginalRemaining = 0;
        for (uint256 i = topProtocolsToEnsure; i < sortedIndices.length; i++) {
            totalOriginalRemaining += allocations[sortedIndices[i]];
        }

        if (totalOriginalRemaining > 0) {
            for (
                uint256 i = topProtocolsToEnsure;
                i < sortedIndices.length;
                i++
            ) {
                uint256 idx = sortedIndices[i];
                diversified[idx] =
                    (allocations[idx] * remainingAmount) /
                    totalOriginalRemaining;
            }
        }

        return diversified;
    }

    function _getSortedIndicesByAllocation(
        uint256[] memory allocations
    ) internal pure returns (uint256[] memory sortedIndices) {
        sortedIndices = new uint256[](allocations.length);

        // Initialize indices
        for (uint256 i = 0; i < allocations.length; i++) {
            sortedIndices[i] = i;
        }

        // Simple bubble sort by allocation amount (descending)
        for (uint256 i = 0; i < allocations.length; i++) {
            for (uint256 j = i + 1; j < allocations.length; j++) {
                if (
                    allocations[sortedIndices[i]] <
                    allocations[sortedIndices[j]]
                ) {
                    uint256 temp = sortedIndices[i];
                    sortedIndices[i] = sortedIndices[j];
                    sortedIndices[j] = temp;
                }
            }
        }
    }

    // Keep existing helper functions
    function _filterOperationalProtocols(
        ProtocolMetrics[] memory metrics
    ) internal pure returns (ProtocolMetrics[] memory filtered) {
        // Count operational protocols
        uint256 operationalCount = 0;
        for (uint256 i = 0; i < metrics.length; i++) {
            if (metrics[i].isOperational && metrics[i].adapter != address(0)) {
                operationalCount++;
            }
        }

        // Create filtered array
        filtered = new ProtocolMetrics[](operationalCount);
        uint256 index = 0;
        for (uint256 i = 0; i < metrics.length; i++) {
            if (metrics[i].isOperational && metrics[i].adapter != address(0)) {
                filtered[index] = metrics[i];
                index++;
            }
        }
    }

    function _mapToOriginalOrder(
        address[] memory originalProtocols,
        ProtocolMetrics[] memory operationalMetrics,
        uint256[] memory operationalAllocations
    ) internal pure returns (uint256[] memory mappedAllocations) {
        mappedAllocations = new uint256[](originalProtocols.length);

        for (uint256 i = 0; i < originalProtocols.length; i++) {
            // Find this protocol in operational metrics
            for (uint256 j = 0; j < operationalMetrics.length; j++) {
                if (operationalMetrics[j].adapter == originalProtocols[i]) {
                    mappedAllocations[i] = operationalAllocations[j];
                    break;
                }
            }
        }
    }
}
