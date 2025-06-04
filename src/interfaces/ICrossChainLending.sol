// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ICrossChainLending
 * @notice Interface for cross-chain undercollateralized lending system
 * @dev Enables loans with dynamic rates and cross-chain collateral management
 */
interface ICrossChainLending {
    struct LoanRequest {
        address borrower;
        address collateralToken;
        address borrowToken;
        uint256 collateralAmount;
        uint256 requestedAmount;
        uint256 maxInterestRate; // in basis points per year
        uint256 duration; // in seconds
        uint64 destinationChain; // Chainlink chain selector
        bytes32 creditHash; // Hash of off-chain credit data
        uint256 deadline;
    }

    struct ActiveLoan {
        uint256 loanId;
        address borrower;
        address collateralToken;
        address borrowToken;
        uint256 collateralAmount;
        uint256 borrowAmount;
        uint256 interestRate; // in basis points per year
        uint256 startTime;
        uint256 duration;
        uint256 lastPaymentTime;
        uint256 totalInterestAccrued;
        uint64 sourceChain;
        uint64 destinationChain;
        LoanStatus status;
        uint256 healthFactor; // 10000 = 100% (liquidation threshold)
    }

    enum LoanStatus {
        PENDING,
        ACTIVE,
        REPAID,
        LIQUIDATED,
        DEFAULTED
    }

    /// @notice Emitted when a loan request is submitted
    event LoanRequested(
        uint256 indexed loanId,
        address indexed borrower,
        address collateralToken,
        address borrowToken,
        uint256 collateralAmount,
        uint256 requestedAmount
    );

    /// @notice Emitted when a loan is approved and funded
    event LoanApproved(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 borrowAmount,
        uint256 interestRate,
        uint256 duration
    );

    /// @notice Emitted when a loan payment is made
    event LoanPayment(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 principalAmount,
        uint256 interestAmount,
        uint256 remainingBalance
    );

    /// @notice Emitted when a loan is fully repaid
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 totalAmount);

    /// @notice Emitted when a loan is liquidated
    event LoanLiquidated(
        uint256 indexed loanId,
        address indexed borrower,
        address indexed liquidator,
        uint256 collateralSeized,
        uint256 debtCovered
    );

    /// @notice Emitted when collateral is routed to yield optimizer
    event CollateralRouted(
        uint256 indexed loanId,
        address indexed token,
        uint256 amount,
        address yieldOptimizer
    );

    /**
     * @notice Submit a loan request with collateral
     * @param request The loan request parameters
     * @return loanId The unique identifier for the loan request
     */
    function requestLoan(LoanRequest calldata request) external returns (uint256 loanId);

    /**
     * @notice Approve a loan request (AI agent function)
     * @param loanId The loan request ID
     * @param approvedAmount The approved loan amount
     * @param interestRate The approved interest rate (in basis points per year)
     * @param creditScore The computed credit score (0-1000)
     */
    function approveLoan(
        uint256 loanId,
        uint256 approvedAmount,
        uint256 interestRate,
        uint256 creditScore
    ) external;

    /**
     * @notice Make a payment towards a loan
     * @param loanId The loan ID
     * @param amount The payment amount
     * @return principalPaid Amount applied to principal
     * @return interestPaid Amount applied to interest
     */
    function makePayment(uint256 loanId, uint256 amount) 
        external returns (uint256 principalPaid, uint256 interestPaid);

    /**
     * @notice Repay a loan in full
     * @param loanId The loan ID
     * @return totalAmount Total amount paid including principal and interest
     */
    function repayLoan(uint256 loanId) external returns (uint256 totalAmount);

    /**
     * @notice Liquidate an undercollateralized loan
     * @param loanId The loan ID
     * @param maxCollateralSeized Maximum collateral to seize
     * @return collateralSeized Amount of collateral seized
     * @return debtCovered Amount of debt covered
     */
    function liquidateLoan(uint256 loanId, uint256 maxCollateralSeized) 
        external returns (uint256 collateralSeized, uint256 debtCovered);

    /**
     * @notice Route idle collateral to yield optimizer
     * @param loanId The loan ID
     * @param amount Amount of collateral to route
     * @param yieldOptimizer Address of the yield optimizer contract
     */
    function routeCollateralToYield(uint256 loanId, uint256 amount, address yieldOptimizer) external;

    /**
     * @notice Withdraw collateral from yield optimizer back to loan
     * @param loanId The loan ID
     * @param amount Amount to withdraw
     * @param yieldOptimizer Address of the yield optimizer contract
     */
    function withdrawCollateralFromYield(uint256 loanId, uint256 amount, address yieldOptimizer) external;

    /**
     * @notice Get loan details
     * @param loanId The loan ID
     * @return loan The complete loan information
     */
    function getLoan(uint256 loanId) external view returns (ActiveLoan memory loan);

    /**
     * @notice Calculate current health factor for a loan
     * @param loanId The loan ID
     * @return healthFactor Current health factor (10000 = 100%)
     */
    function calculateHealthFactor(uint256 loanId) external view returns (uint256 healthFactor);

    /**
     * @notice Get the current outstanding balance for a loan
     * @param loanId The loan ID
     * @return principal Outstanding principal amount
     * @return interest Accrued interest amount
     */
    function getOutstandingBalance(uint256 loanId) 
        external view returns (uint256 principal, uint256 interest);

    /**
     * @notice Check if a loan is eligible for liquidation
     * @param loanId The loan ID
     * @return eligible Whether the loan can be liquidated
     * @return currentHealthFactor Current health factor
     */
    function isLiquidationEligible(uint256 loanId) 
        external view returns (bool eligible, uint256 currentHealthFactor);

    /**
     * @notice Get all active loans for a borrower
     * @param borrower The borrower address
     * @return loanIds Array of active loan IDs
     */
    function getBorrowerLoans(address borrower) external view returns (uint256[] memory loanIds);

    /**
     * @notice Get loans that need liquidation monitoring
     * @param healthFactorThreshold Threshold below which loans should be monitored
     * @return loanIds Array of loan IDs that need monitoring
     */
    function getLoansForMonitoring(uint256 healthFactorThreshold) 
        external view returns (uint256[] memory loanIds);

    /**
     * @notice Calculate dynamic interest rate based on risk factors
     * @param collateralToken The collateral token address
     * @param borrowToken The borrow token address
     * @param ltvRatio Loan-to-value ratio (in basis points)
     * @param creditScore Borrower credit score (0-1000)
     * @param duration Loan duration in seconds
     * @return interestRate Calculated interest rate in basis points per year
     */
    function calculateDynamicRate(
        address collateralToken,
        address borrowToken,
        uint256 ltvRatio,
        uint256 creditScore,
        uint256 duration
    ) external view returns (uint256 interestRate);
} 