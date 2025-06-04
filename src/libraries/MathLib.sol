// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MathLib
 * @notice Library for mathematical operations used in DeFi calculations
 * @dev Provides safe mathematical functions for yield and lending calculations
 */
library MathLib {
    /// @notice Thrown when attempting to divide by zero
    error DivisionByZero();
    
    /// @notice Thrown when calculation would result in overflow
    error CalculationOverflow();
    
    /// @notice Thrown when square root calculation fails
    error InvalidSquareRoot();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant BPS_MAX = 10000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /**
     * @notice Calculate compound interest
     * @param principal Principal amount
     * @param rate Annual interest rate in basis points
     * @param time Time period in seconds
     * @return interest Compound interest amount
     */
    function calculateCompoundInterest(
        uint256 principal,
        uint256 rate,
        uint256 time
    ) internal pure returns (uint256 interest) {
        if (principal == 0 || rate == 0 || time == 0) return 0;
        
        // Convert rate to per-second basis
        uint256 ratePerSecond = rate * WAD / (BPS_MAX * SECONDS_PER_YEAR);
        
        // Calculate (1 + r)^t using approximation for small rates
        uint256 compoundFactor = WAD + (ratePerSecond * time / WAD);
        
        // For longer periods, use more accurate calculation
        if (time > 30 days) {
            compoundFactor = _compound(WAD + ratePerSecond, time);
        }
        
        return principal * (compoundFactor - WAD) / WAD;
    }

    /**
     * @notice Calculate weighted average of values
     * @param values Array of values
     * @param weights Array of weights (in basis points)
     * @return average Weighted average value
     */
    function calculateWeightedAverage(
        uint256[] memory values,
        uint256[] memory weights
    ) internal pure returns (uint256 average) {
        if (values.length != weights.length || values.length == 0) {
            revert CalculationOverflow();
        }
        
        uint256 totalValue = 0;
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < values.length; i++) {
            totalValue += values[i] * weights[i];
            totalWeight += weights[i];
        }
        
        if (totalWeight == 0) revert DivisionByZero();
        
        return totalValue / totalWeight;
    }

    /**
     * @notice Calculate health factor for a loan
     * @param collateralValue Value of collateral in USD
     * @param debtValue Value of debt in USD
     * @param liquidationThreshold Liquidation threshold in basis points
     * @return healthFactor Health factor (10000 = 100%)
     */
    function calculateHealthFactor(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 liquidationThreshold
    ) internal pure returns (uint256 healthFactor) {
        if (debtValue == 0) return type(uint256).max;
        
        uint256 maxDebt = collateralValue * liquidationThreshold / BPS_MAX;
        return maxDebt * BPS_MAX / debtValue;
    }

    /**
     * @notice Calculate loan-to-value ratio
     * @param loanAmount Loan amount
     * @param collateralValue Collateral value
     * @return ltv LTV ratio in basis points
     */
    function calculateLTV(
        uint256 loanAmount,
        uint256 collateralValue
    ) internal pure returns (uint256 ltv) {
        if (collateralValue == 0) revert DivisionByZero();
        return loanAmount * BPS_MAX / collateralValue;
    }

    /**
     * @notice Calculate annual percentage yield from two values
     * @param oldValue Previous value
     * @param newValue Current value
     * @param timeElapsed Time elapsed in seconds
     * @return apy Annual percentage yield in basis points
     */
    function calculateAPY(
        uint256 oldValue,
        uint256 newValue,
        uint256 timeElapsed
    ) internal pure returns (uint256 apy) {
        if (oldValue == 0 || timeElapsed == 0) return 0;
        if (newValue <= oldValue) return 0;
        
        uint256 growth = newValue * WAD / oldValue;
        uint256 annualizedGrowth = _compound(growth, SECONDS_PER_YEAR / timeElapsed);
        
        return (annualizedGrowth - WAD) * BPS_MAX / WAD;
    }

    /**
     * @notice Calculate optimal allocation using simplified Markowitz model
     * @param expectedReturns Array of expected returns (in basis points)
     * @param risks Array of risk scores (0-10000)
     * @param correlations Array of correlation coefficients (0-10000)
     * @return allocations Optimal allocation percentages (in basis points)
     */
    function calculateOptimalAllocation(
        uint256[] memory expectedReturns,
        uint256[] memory risks,
        uint256[] memory correlations
    ) internal pure returns (uint256[] memory allocations) {
        uint256 n = expectedReturns.length;
        if (n == 0 || n != risks.length) revert CalculationOverflow();
        
        allocations = new uint256[](n);
        
        // Simple risk-adjusted allocation
        uint256 totalScore = 0;
        uint256[] memory scores = new uint256[](n);
        
        for (uint256 i = 0; i < n; i++) {
            // Score = return / risk (with minimum risk of 1)
            uint256 risk = risks[i] > 0 ? risks[i] : 1;
            scores[i] = expectedReturns[i] * BPS_MAX / risk;
            totalScore += scores[i];
        }
        
        // Normalize allocations to sum to 100%
        if (totalScore == 0) {
            // Equal allocation if no clear winner
            uint256 equalAllocation = BPS_MAX / n;
            for (uint256 i = 0; i < n; i++) {
                allocations[i] = equalAllocation;
            }
        } else {
            for (uint256 i = 0; i < n; i++) {
                allocations[i] = scores[i] * BPS_MAX / totalScore;
            }
        }
        
        return allocations;
    }

    /**
     * @notice Calculate liquidation bonus for a loan
     * @param debtValue Value of debt being liquidated
     * @param healthFactor Current health factor
     * @param baseBonusBps Base liquidation bonus in basis points
     * @return bonus Liquidation bonus amount
     */
    function calculateLiquidationBonus(
        uint256 debtValue,
        uint256 healthFactor,
        uint256 baseBonusBps
    ) internal pure returns (uint256 bonus) {
        // Higher bonus for lower health factors
        uint256 bonusMultiplier = BPS_MAX;
        
        if (healthFactor < 5000) { // < 50%
            bonusMultiplier = 15000; // 150%
        } else if (healthFactor < 7500) { // < 75%
            bonusMultiplier = 12500; // 125%
        } else if (healthFactor < 9000) { // < 90%
            bonusMultiplier = 11000; // 110%
        }
        
        return debtValue * baseBonusBps * bonusMultiplier / (BPS_MAX * BPS_MAX);
    }

    /**
     * @notice Calculate price impact for large trades
     * @param tradeSize Size of the trade
     * @param liquidityPool Available liquidity in the pool
     * @param impactFactor Impact factor (higher = more impact)
     * @return impact Price impact in basis points
     */
    function calculatePriceImpact(
        uint256 tradeSize,
        uint256 liquidityPool,
        uint256 impactFactor
    ) internal pure returns (uint256 impact) {
        if (liquidityPool == 0) return BPS_MAX; // Maximum impact
        
        uint256 ratio = tradeSize * BPS_MAX / liquidityPool;
        
        // Quadratic price impact: impact = ratio^2 * factor
        return ratio * ratio * impactFactor / (BPS_MAX * BPS_MAX);
    }

    /**
     * @notice Internal function to calculate compound growth
     * @param base Base value (in WAD)
     * @param exponent Exponent value
     * @return result Compound result (in WAD)
     */
    function _compound(uint256 base, uint256 exponent) private pure returns (uint256 result) {
        if (exponent == 0) return WAD;
        if (base == WAD) return WAD;
        
        result = WAD;
        uint256 baseN = base;
        
        // Binary exponentiation
        while (exponent > 0) {
            if (exponent % 2 == 1) {
                result = result * baseN / WAD;
            }
            baseN = baseN * baseN / WAD;
            exponent /= 2;
        }
        
        return result;
    }

    /**
     * @notice Calculate square root using Babylonian method
     * @param x Value to calculate square root for
     * @return result Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        result = x;
        
        while (z < result) {
            result = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Calculate minimum of two values
     * @param a First value
     * @param b Second value
     * @return result Minimum value
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256 result) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculate maximum of two values
     * @param a First value
     * @param b Second value
     * @return result Maximum value
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256 result) {
        return a > b ? a : b;
    }
} 