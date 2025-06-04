// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ValidationLib
 * @notice Library for common validation functions used across Alioth contracts
 * @dev Provides reusable validation logic with custom errors for gas efficiency
 */
library ValidationLib {
    /// @notice Thrown when an address parameter is the zero address
    error ZeroAddress();
    
    /// @notice Thrown when an amount parameter is zero
    error ZeroAmount();
    
    /// @notice Thrown when a percentage parameter exceeds 100%
    error InvalidPercentage();
    
    /// @notice Thrown when a deadline has passed
    error DeadlineExpired();
    
    /// @notice Thrown when slippage tolerance is exceeded
    error SlippageExceeded();
    
    /// @notice Thrown when an array parameter is empty
    error EmptyArray();
    
    /// @notice Thrown when array lengths don't match
    error ArrayLengthMismatch();
    
    /// @notice Thrown when a value is outside the allowed range
    error ValueOutOfRange();
    
    /// @notice Thrown when a token is not supported
    error UnsupportedToken();
    
    /// @notice Thrown when insufficient balance for operation
    error InsufficientBalance();

    uint256 internal constant BPS_MAX = 10000; // 100% in basis points
    uint256 internal constant PERCENTAGE_MAX = 100;

    /**
     * @notice Validates that an address is not the zero address
     * @param addr The address to validate
     */
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Validates that an amount is greater than zero
     * @param amount The amount to validate
     */
    function validateAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /**
     * @notice Validates that a percentage is within valid range (0-100%)
     * @param percentage The percentage to validate (in basis points)
     */
    function validatePercentage(uint256 percentage) internal pure {
        if (percentage > BPS_MAX) revert InvalidPercentage();
    }

    /**
     * @notice Validates that a deadline has not passed
     * @param deadline The deadline timestamp
     */
    function validateDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert DeadlineExpired();
    }

    /**
     * @notice Validates slippage tolerance
     * @param expectedAmount The expected amount
     * @param actualAmount The actual amount received
     * @param maxSlippageBps Maximum allowed slippage in basis points
     */
    function validateSlippage(
        uint256 expectedAmount,
        uint256 actualAmount,
        uint256 maxSlippageBps
    ) internal pure {
        if (expectedAmount == 0) return;
        
        uint256 minAcceptable = expectedAmount * (BPS_MAX - maxSlippageBps) / BPS_MAX;
        if (actualAmount < minAcceptable) revert SlippageExceeded();
    }

    /**
     * @notice Validates that an array is not empty
     * @param arrayLength The length of the array
     */
    function validateNonEmptyArray(uint256 arrayLength) internal pure {
        if (arrayLength == 0) revert EmptyArray();
    }

    /**
     * @notice Validates that two arrays have matching lengths
     * @param length1 Length of first array
     * @param length2 Length of second array
     */
    function validateArrayLengths(uint256 length1, uint256 length2) internal pure {
        if (length1 != length2) revert ArrayLengthMismatch();
    }

    /**
     * @notice Validates that a value is within a specified range
     * @param value The value to validate
     * @param min Minimum allowed value (inclusive)
     * @param max Maximum allowed value (inclusive)
     */
    function validateRange(uint256 value, uint256 min, uint256 max) internal pure {
        if (value < min || value > max) revert ValueOutOfRange();
    }

    /**
     * @notice Validates that sufficient balance exists for an operation
     * @param available Available balance
     * @param required Required amount
     */
    function validateBalance(uint256 available, uint256 required) internal pure {
        if (available < required) revert InsufficientBalance();
    }

    /**
     * @notice Validates multiple addresses in an array
     * @param addresses Array of addresses to validate
     */
    function validateAddresses(address[] memory addresses) internal pure {
        validateNonEmptyArray(addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            validateAddress(addresses[i]);
        }
    }

    /**
     * @notice Validates multiple amounts in an array
     * @param amounts Array of amounts to validate
     */
    function validateAmounts(uint256[] memory amounts) internal pure {
        validateNonEmptyArray(amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            validateAmount(amounts[i]);
        }
    }

    /**
     * @notice Calculate percentage of an amount
     * @param amount Base amount
     * @param percentageBps Percentage in basis points
     * @return result The calculated percentage amount
     */
    function calculatePercentage(uint256 amount, uint256 percentageBps) 
        internal pure returns (uint256 result) {
        validatePercentage(percentageBps);
        return amount * percentageBps / BPS_MAX;
    }

    /**
     * @notice Calculate the percentage difference between two values
     * @param oldValue Previous value
     * @param newValue New value
     * @return percentageDiff Percentage difference in basis points
     */
    function calculatePercentageDiff(uint256 oldValue, uint256 newValue) 
        internal pure returns (uint256 percentageDiff) {
        if (oldValue == 0) return 0;
        
        if (newValue > oldValue) {
            return (newValue - oldValue) * BPS_MAX / oldValue;
        } else {
            return (oldValue - newValue) * BPS_MAX / oldValue;
        }
    }

    /**
     * @notice Check if two values are within a percentage tolerance
     * @param value1 First value
     * @param value2 Second value
     * @param toleranceBps Tolerance in basis points
     * @return withinTolerance Whether values are within tolerance
     */
    function isWithinTolerance(
        uint256 value1, 
        uint256 value2, 
        uint256 toleranceBps
    ) internal pure returns (bool withinTolerance) {
        uint256 diff = calculatePercentageDiff(value1, value2);
        return diff <= toleranceBps;
    }
} 