// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/CrossTokenOperationsLib.sol";

/**
 * @title IAIIntegration
 * @notice Interface for AI Integration functionality
 * @dev Defines the required functions for cross-token yield optimization
 */
interface IAIIntegration {
    /// @notice Cross-token rebalance parameters
    struct CrossTokenRebalanceParams {
        address[] fromTokens;
        address[] toTokens;
        uint256[] amounts;
        uint256[] minOutputAmounts;
        uint256 maxSlippage;
        uint256 deadline;
        bytes routeData;
        bytes32 operationHash;
    }

    /// @notice Market analysis data structure
    struct MarketAnalysis {
        address[] tokens;
        uint256[] pricesUSD;
        uint256[] expectedYields;
        uint256[] volatilityScores;
        uint256[] riskScores;
        uint256 timestamp;
    }

    /// @notice Swap validation result
    struct SwapValidation {
        bool isValidSwap;
        uint256 slippagePercent;
        uint256 expectedPrice;
        uint256 actualPrice;
        uint256 timestamp;
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

    event AIBackendAuthorized(address indexed backend, address indexed admin);
    event AIOperationExecuted(
        address indexed backend,
        bytes32 indexed operationHash
    );

    /// @notice AI Authorization functions
    function authorizeAIBackend(address aiBackend) external;

    function revokeAIBackend(address aiBackend) external;

    function validateAISignature(
        address aiBackend,
        bytes calldata signature,
        bytes32 operationHash,
        uint256 deadline
    ) external view returns (bool isValid);

    /// @notice Enhanced YieldOptimizer functions
    function batchDepositFromAI(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address beneficiary,
        uint256[] calldata minShares
    ) external returns (uint256[] memory totalShares);

    function validateSwapRates(
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 expectedAmountOut
    ) external view returns (bool isValid);

    function rebalanceAcrossTokens(
        CrossTokenRebalanceParams calldata params
    ) external;

    /// @notice Enhanced ChainlinkFeedManager functions
    function getMarketAnalysis(
        address[] calldata tokens
    ) external view returns (MarketAnalysis memory analysis);

    function validateSwapExecution(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (SwapValidation memory validation);

    /// @notice Cross-token operations
    function calculateOptimalCrossTokenAllocation(
        address inputToken,
        uint256 inputAmount,
        address[] memory availableTokens,
        CrossTokenOperationsLib.TokenMetrics[] memory tokenMetrics
    )
        external
        pure
        returns (
            CrossTokenOperationsLib.CrossTokenAllocation memory allocation
        );

    function validateCrossTokenOperation(
        CrossTokenOperationsLib.CrossTokenAllocation memory allocation,
        uint256 maxSlippage,
        uint256 minYieldImprovement
    ) external pure returns (bool isValid);
}
