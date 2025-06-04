// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/ICrossChainLending.sol";
import "../interfaces/IYieldOptimizer.sol";
import "../interfaces/ICCIPMessenger.sol";
import "../libraries/ValidationLib.sol";
import "../libraries/MathLib.sol";

/**
 * @title CrossChainLending
 * @notice Cross-chain undercollateralized lending system for Alioth platform
 * @dev Enables loans with dynamic rates and cross-chain collateral management
 */
contract CrossChainLending is ICrossChainLending, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;
    using MathLib for uint256;

    /// @notice Role for AI agents that can approve loans
    bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");
    
    /// @notice Role for liquidators
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    
    /// @notice Role for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Maximum LTV ratio allowed (in basis points)
    uint256 public constant MAX_LTV = 7000; // 70%
    
    /// @notice Minimum health factor before liquidation (in basis points)
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80%
    
    /// @notice Base liquidation bonus (in basis points)
    uint256 public constant LIQUIDATION_BONUS = 500; // 5%
    
    /// @notice Maximum interest rate (in basis points per year)
    uint256 public constant MAX_INTEREST_RATE = 5000; // 50%
    
    /// @notice Minimum loan duration
    uint256 public constant MIN_LOAN_DURATION = 7 days;
    
    /// @notice Maximum loan duration
    uint256 public constant MAX_LOAN_DURATION = 365 days;

    struct PriceOracle {
        AggregatorV3Interface oracle;
        uint256 heartbeat; // Maximum staleness in seconds
        uint8 decimals;
    }

    /// @notice Counter for loan IDs
    uint256 public nextLoanId = 1;
    
    /// @notice Mapping of loan ID to loan data
    mapping(uint256 => ActiveLoan) public loans;
    
    /// @notice Mapping of borrower to their loan IDs
    mapping(address => uint256[]) public borrowerLoans;
    
    /// @notice Mapping of token to price oracle
    mapping(address => PriceOracle) public priceOracles;
    
    /// @notice Supported collateral tokens
    mapping(address => bool) public supportedCollateral;
    
    /// @notice Supported borrow tokens
    mapping(address => bool) public supportedBorrowTokens;
    
    /// @notice CCIP messenger for cross-chain operations
    ICCIPMessenger public immutable ccipMessenger;
    
    /// @notice Yield optimizer for collateral routing
    IYieldOptimizer public yieldOptimizer;
    
    /// @notice Administrator
    address public admin;
    
    /// @notice Emergency stop flag
    bool public emergencyStop;
    
    /// @notice Base interest rate (in basis points per year)
    uint256 public baseInterestRate = 500; // 5%
    
    /// @notice Risk multiplier for interest calculation
    uint256 public riskMultiplier = 200; // 2x
    
    /// @notice Fee collector address
    address public feeCollector;
    
    /// @notice Platform fee rate (in basis points)
    uint256 public platformFeeRate = 100; // 1%

    /// @notice Simple role checking (replace with OpenZeppelin AccessControl in production)
    mapping(bytes32 => mapping(address => bool)) private roles;

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

    /// @notice Modifier to restrict access to underwriter role
    modifier onlyUnderwriter() {
        require(msg.sender == admin || hasRole(UNDERWRITER_ROLE, msg.sender), "Not underwriter");
        _;
    }

    /// @notice Modifier to restrict access to liquidator role
    modifier onlyLiquidator() {
        require(msg.sender == admin || hasRole(LIQUIDATOR_ROLE, msg.sender), "Not liquidator");
        _;
    }

    constructor(
        address _ccipMessenger,
        address _yieldOptimizer,
        address _admin,
        address _feeCollector
    ) {
        _ccipMessenger.validateAddress();
        _yieldOptimizer.validateAddress();
        _admin.validateAddress();
        _feeCollector.validateAddress();
        
        ccipMessenger = ICCIPMessenger(_ccipMessenger);
        yieldOptimizer = IYieldOptimizer(_yieldOptimizer);
        admin = _admin;
        feeCollector = _feeCollector;
        
        // Grant admin roles
        roles[EMERGENCY_ROLE][_admin] = true;
        roles[UNDERWRITER_ROLE][_admin] = true;
        roles[LIQUIDATOR_ROLE][_admin] = true;
    }

    /**
     * @notice Submit a loan request with collateral
     * @param request The loan request parameters
     * @return loanId The unique identifier for the loan request
     */
    function requestLoan(LoanRequest calldata request) 
        external nonReentrant whenNotStopped returns (uint256 loanId) {
        // Validate request parameters
        request.borrower.validateAddress();
        request.collateralToken.validateAddress();
        request.borrowToken.validateAddress();
        request.collateralAmount.validateAmount();
        request.requestedAmount.validateAmount();
        request.deadline.validateDeadline();
        
        require(supportedCollateral[request.collateralToken], "Collateral not supported");
        require(supportedBorrowTokens[request.borrowToken], "Borrow token not supported");
        require(request.duration >= MIN_LOAN_DURATION, "Duration too short");
        require(request.duration <= MAX_LOAN_DURATION, "Duration too long");
        require(request.maxInterestRate <= MAX_INTEREST_RATE, "Max rate too high");
        
        // Calculate LTV ratio
        uint256 collateralValue = _getTokenValue(request.collateralToken, request.collateralAmount);
        uint256 ltvRatio = MathLib.calculateLTV(request.requestedAmount, collateralValue);
        require(ltvRatio <= MAX_LTV, "LTV too high");
        
        // Transfer collateral from borrower
        ERC20(request.collateralToken).safeTransferFrom(
            request.borrower, 
            address(this), 
            request.collateralAmount
        );
        
        loanId = nextLoanId++;
        
        // Create loan with PENDING status
        loans[loanId] = ActiveLoan({
            loanId: loanId,
            borrower: request.borrower,
            collateralToken: request.collateralToken,
            borrowToken: request.borrowToken,
            collateralAmount: request.collateralAmount,
            borrowAmount: 0, // Set when approved
            interestRate: 0, // Set when approved
            startTime: 0, // Set when approved
            duration: request.duration,
            lastPaymentTime: 0,
            totalInterestAccrued: 0,
            sourceChain: uint64(block.chainid),
            destinationChain: request.destinationChain,
            status: LoanStatus.PENDING,
            healthFactor: LIQUIDATION_THRESHOLD
        });
        
        borrowerLoans[request.borrower].push(loanId);
        
        emit LoanRequested(
            loanId,
            request.borrower,
            request.collateralToken,
            request.borrowToken,
            request.collateralAmount,
            request.requestedAmount
        );
    }

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
    ) external onlyUnderwriter nonReentrant {
        approvedAmount.validateAmount();
        require(interestRate <= MAX_INTEREST_RATE, "Interest rate too high");
        require(creditScore <= 1000, "Invalid credit score");
        
        ActiveLoan storage loan = loans[loanId];
        require(loan.status == LoanStatus.PENDING, "Loan not pending");
        
        // Validate approved amount doesn't exceed LTV limits
        uint256 collateralValue = _getTokenValue(loan.collateralToken, loan.collateralAmount);
        uint256 ltvRatio = MathLib.calculateLTV(approvedAmount, collateralValue);
        require(ltvRatio <= MAX_LTV, "Approved amount exceeds LTV");
        
        // Update loan details
        loan.borrowAmount = approvedAmount;
        loan.interestRate = interestRate;
        loan.startTime = block.timestamp;
        loan.lastPaymentTime = block.timestamp;
        loan.status = LoanStatus.ACTIVE;
        loan.healthFactor = _calculateHealthFactorInternal(loanId);
        
        // Transfer approved amount to borrower
        ERC20(loan.borrowToken).safeTransfer(loan.borrower, approvedAmount);
        
        // Route collateral to yield optimizer
        if (address(yieldOptimizer) != address(0)) {
            _routeCollateralToYield(loanId, loan.collateralAmount);
        }
        
        emit LoanApproved(loanId, loan.borrower, approvedAmount, interestRate, loan.duration);
    }

    /**
     * @notice Make a payment towards a loan
     * @param loanId The loan ID
     * @param amount The payment amount
     * @return principalPaid Amount applied to principal
     * @return interestPaid Amount applied to interest
     */
    function makePayment(uint256 loanId, uint256 amount) 
        external nonReentrant returns (uint256 principalPaid, uint256 interestPaid) {
        amount.validateAmount();
        
        ActiveLoan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        
        // Calculate outstanding amounts
        (uint256 principal, uint256 interest) = getOutstandingBalance(loanId);
        uint256 totalOwed = principal + interest;
        
        require(amount <= totalOwed, "Payment exceeds debt");
        
        // Transfer payment from borrower
        ERC20(loan.borrowToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Apply payment to interest first, then principal
        if (amount >= interest) {
            interestPaid = interest;
            principalPaid = amount - interest;
            
            // Reset accrued interest
            loan.totalInterestAccrued = 0;
            loan.lastPaymentTime = block.timestamp;
            
            // Reduce principal
            loan.borrowAmount -= principalPaid;
        } else {
            interestPaid = amount;
            principalPaid = 0;
            
            // Partial interest payment
            loan.totalInterestAccrued -= amount;
        }
        
        // Collect platform fee
        uint256 platformFee = ValidationLib.calculatePercentage(interestPaid, platformFeeRate);
        if (platformFee > 0) {
            ERC20(loan.borrowToken).safeTransfer(feeCollector, platformFee);
        }
        
        // Update health factor
        loan.healthFactor = _calculateHealthFactorInternal(loanId);
        
        uint256 remainingBalance = loan.borrowAmount + _calculateAccruedInterest(loanId);
        
        emit LoanPayment(loanId, loan.borrower, principalPaid, interestPaid, remainingBalance);
    }

    /**
     * @notice Repay a loan in full
     * @param loanId The loan ID
     * @return totalAmount Total amount paid including principal and interest
     */
    function repayLoan(uint256 loanId) external nonReentrant returns (uint256 totalAmount) {
        ActiveLoan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        
        // Calculate total amount owed
        (uint256 principal, uint256 interest) = getOutstandingBalance(loanId);
        totalAmount = principal + interest;
        
        // Transfer payment from borrower
        ERC20(loan.borrowToken).safeTransferFrom(msg.sender, address(this), totalAmount);
        
        // Collect platform fee
        uint256 platformFee = ValidationLib.calculatePercentage(interest, platformFeeRate);
        if (platformFee > 0) {
            ERC20(loan.borrowToken).safeTransfer(feeCollector, platformFee);
        }
        
        // Mark loan as repaid
        loan.status = LoanStatus.REPAID;
        loan.borrowAmount = 0;
        loan.totalInterestAccrued = 0;
        
        // Withdraw collateral from yield optimizer
        if (address(yieldOptimizer) != address(0)) {
            _withdrawCollateralFromYield(loanId, loan.collateralAmount);
        }
        
        // Return collateral to borrower
        ERC20(loan.collateralToken).safeTransfer(loan.borrower, loan.collateralAmount);
        
        emit LoanRepaid(loanId, loan.borrower, totalAmount);
    }

    /**
     * @notice Liquidate an undercollateralized loan
     * @param loanId The loan ID
     * @param maxCollateralSeized Maximum collateral to seize
     * @return collateralSeized Amount of collateral seized
     * @return debtCovered Amount of debt covered
     */
    function liquidateLoan(uint256 loanId, uint256 maxCollateralSeized) 
        external onlyLiquidator nonReentrant returns (uint256 collateralSeized, uint256 debtCovered) {
        maxCollateralSeized.validateAmount();
        
        ActiveLoan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        
        // Check if loan is eligible for liquidation
        (bool eligible, uint256 currentHealthFactor) = isLiquidationEligible(loanId);
        require(eligible, "Loan not eligible for liquidation");
        
        // Calculate debt amount
        (uint256 principal, uint256 interest) = getOutstandingBalance(loanId);
        uint256 totalDebt = principal + interest;
        
        // Calculate liquidation bonus
        uint256 bonus = MathLib.calculateLiquidationBonus(
            totalDebt, 
            currentHealthFactor, 
            LIQUIDATION_BONUS
        );
        
        // Calculate collateral value needed to cover debt + bonus
        uint256 collateralValue = _getTokenValue(loan.collateralToken, loan.collateralAmount);
        uint256 debtValue = _getTokenValue(loan.borrowToken, totalDebt);
        uint256 requiredCollateralValue = debtValue + bonus;
        
        // Determine how much collateral to seize
        if (requiredCollateralValue >= collateralValue) {
            // Seize all collateral
            collateralSeized = loan.collateralAmount;
            debtCovered = totalDebt;
        } else {
            // Partial liquidation
            collateralSeized = MathLib.min(
                maxCollateralSeized,
                requiredCollateralValue * loan.collateralAmount / collateralValue
            );
            
            uint256 collateralValueSeized = _getTokenValue(loan.collateralToken, collateralSeized);
            debtCovered = (collateralValueSeized - bonus) * totalDebt / debtValue;
        }
        
        // Update loan state
        loan.collateralAmount -= collateralSeized;
        loan.borrowAmount -= debtCovered;
        
        if (loan.borrowAmount == 0 || loan.collateralAmount == 0) {
            loan.status = LoanStatus.LIQUIDATED;
        }
        
        // Withdraw collateral from yield optimizer
        if (address(yieldOptimizer) != address(0) && collateralSeized > 0) {
            _withdrawCollateralFromYield(loanId, collateralSeized);
        }
        
        // Transfer collateral to liquidator
        ERC20(loan.collateralToken).safeTransfer(msg.sender, collateralSeized);
        
        // Liquidator pays debt amount
        ERC20(loan.borrowToken).safeTransferFrom(msg.sender, address(this), debtCovered);
        
        emit LoanLiquidated(loanId, loan.borrower, msg.sender, collateralSeized, debtCovered);
    }

    /**
     * @notice Route idle collateral to yield optimizer
     * @param loanId The loan ID
     * @param amount Amount of collateral to route
     * @param _yieldOptimizer Address of the yield optimizer contract
     */
    function routeCollateralToYield(uint256 loanId, uint256 amount, address _yieldOptimizer) 
        external onlyAdmin {
        amount.validateAmount();
        _yieldOptimizer.validateAddress();
        
        ActiveLoan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        require(amount <= loan.collateralAmount, "Insufficient collateral");
        
        ERC20(loan.collateralToken).safeApprove(_yieldOptimizer, amount);
        IYieldOptimizer(_yieldOptimizer).deposit(loan.collateralToken, amount, 0);
        
        emit CollateralRouted(loanId, loan.collateralToken, amount, _yieldOptimizer);
    }

    /**
     * @notice Withdraw collateral from yield optimizer back to loan
     * @param loanId The loan ID
     * @param amount Amount to withdraw
     * @param _yieldOptimizer Address of the yield optimizer contract
     */
    function withdrawCollateralFromYield(uint256 loanId, uint256 amount, address _yieldOptimizer) 
        external onlyAdmin {
        amount.validateAmount();
        _yieldOptimizer.validateAddress();
        
        ActiveLoan memory loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        
        // This would withdraw from the yield optimizer
        // Implementation depends on the yield optimizer interface
        
        emit CollateralRouted(loanId, loan.collateralToken, amount, address(0));
    }

    /**
     * @notice Get loan details
     * @param loanId The loan ID
     * @return loan The complete loan information
     */
    function getLoan(uint256 loanId) external view returns (ActiveLoan memory loan) {
        return loans[loanId];
    }

    /**
     * @notice Calculate current health factor for a loan
     * @param loanId The loan ID
     * @return healthFactor Current health factor (10000 = 100%)
     */
    function calculateHealthFactor(uint256 loanId) external view returns (uint256 healthFactor) {
        return _calculateHealthFactorInternal(loanId);
    }

    /**
     * @notice Get the current outstanding balance for a loan
     * @param loanId The loan ID
     * @return principal Outstanding principal amount
     * @return interest Accrued interest amount
     */
    function getOutstandingBalance(uint256 loanId) 
        public view returns (uint256 principal, uint256 interest) {
        ActiveLoan memory loan = loans[loanId];
        
        if (loan.status != LoanStatus.ACTIVE) {
            return (0, 0);
        }
        
        principal = loan.borrowAmount;
        interest = loan.totalInterestAccrued + _calculateAccruedInterest(loanId);
    }

    /**
     * @notice Check if a loan is eligible for liquidation
     * @param loanId The loan ID
     * @return eligible Whether the loan can be liquidated
     * @return currentHealthFactor Current health factor
     */
    function isLiquidationEligible(uint256 loanId) 
        public view returns (bool eligible, uint256 currentHealthFactor) {
        currentHealthFactor = _calculateHealthFactorInternal(loanId);
        eligible = currentHealthFactor < LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Get all active loans for a borrower
     * @param borrower The borrower address
     * @return loanIds Array of active loan IDs
     */
    function getBorrowerLoans(address borrower) external view returns (uint256[] memory loanIds) {
        return borrowerLoans[borrower];
    }

    /**
     * @notice Get loans that need liquidation monitoring
     * @param healthFactorThreshold Threshold below which loans should be monitored
     * @return loanIds Array of loan IDs that need monitoring
     */
    function getLoansForMonitoring(uint256 healthFactorThreshold) 
        external view returns (uint256[] memory loanIds) {
        // This would iterate through active loans and find those below threshold
        // For gas efficiency, this should be implemented with pagination in production
        uint256[] memory tempIds = new uint256[](nextLoanId);
        uint256 count = 0;
        
        for (uint256 i = 1; i < nextLoanId; i++) {
            if (loans[i].status == LoanStatus.ACTIVE) {
                uint256 healthFactor = _calculateHealthFactorInternal(i);
                if (healthFactor < healthFactorThreshold) {
                    tempIds[count] = i;
                    count++;
                }
            }
        }
        
        loanIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            loanIds[i] = tempIds[i];
        }
    }

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
    ) external view returns (uint256 interestRate) {
        // Base rate
        interestRate = baseInterestRate;
        
        // LTV risk adjustment
        if (ltvRatio > 5000) { // > 50%
            interestRate += (ltvRatio - 5000) * riskMultiplier / 1000;
        }
        
        // Credit score adjustment (lower score = higher rate)
        if (creditScore < 800) {
            interestRate += (800 - creditScore) * 10; // 10 bps per credit point below 800
        }
        
        // Duration adjustment (longer = higher rate)
        if (duration > 90 days) {
            interestRate += ((duration - 90 days) * 100) / (365 days); // +1% per year
        }
        
        // Token pair risk (simplified)
        // In production, this would consider volatility correlation
        interestRate += 100; // Base token risk
        
        // Cap at maximum rate
        if (interestRate > MAX_INTEREST_RATE) {
            interestRate = MAX_INTEREST_RATE;
        }
    }

    // ===== INTERNAL FUNCTIONS =====

    function _calculateHealthFactorInternal(uint256 loanId) internal view returns (uint256) {
        ActiveLoan memory loan = loans[loanId];
        
        if (loan.status != LoanStatus.ACTIVE || loan.borrowAmount == 0) {
            return type(uint256).max;
        }
        
        uint256 collateralValue = _getTokenValue(loan.collateralToken, loan.collateralAmount);
        (uint256 principal, uint256 interest) = getOutstandingBalance(loanId);
        uint256 debtValue = _getTokenValue(loan.borrowToken, principal + interest);
        
        return MathLib.calculateHealthFactor(collateralValue, debtValue, LIQUIDATION_THRESHOLD);
    }

    function _calculateAccruedInterest(uint256 loanId) internal view returns (uint256) {
        ActiveLoan memory loan = loans[loanId];
        
        if (loan.status != LoanStatus.ACTIVE || loan.borrowAmount == 0) {
            return 0;
        }
        
        uint256 timeElapsed = block.timestamp - loan.lastPaymentTime;
        
        return MathLib.calculateCompoundInterest(
            loan.borrowAmount,
            loan.interestRate,
            timeElapsed
        );
    }

    function _getTokenValue(address token, uint256 amount) internal view returns (uint256) {
        PriceOracle memory oracle = priceOracles[token];
        require(address(oracle.oracle) != address(0), "No price oracle");
        
        (, int256 price, , uint256 updatedAt, ) = oracle.oracle.latestRoundData();
        require(price > 0, "Invalid price");
        require(block.timestamp - updatedAt <= oracle.heartbeat, "Stale price");
        
        // Normalize to 18 decimals
        uint256 normalizedPrice;
        if (oracle.decimals < 18) {
            normalizedPrice = uint256(price) * (10 ** (18 - oracle.decimals));
        } else {
            normalizedPrice = uint256(price) / (10 ** (oracle.decimals - 18));
        }
        
        return amount * normalizedPrice / 1e18;
    }

    function _routeCollateralToYield(uint256 loanId, uint256 amount) internal {
        ActiveLoan memory loan = loans[loanId];
        
        ERC20(loan.collateralToken).safeApprove(address(yieldOptimizer), amount);
        yieldOptimizer.deposit(loan.collateralToken, amount, 0);
        
        emit CollateralRouted(loanId, loan.collateralToken, amount, address(yieldOptimizer));
    }

    function _withdrawCollateralFromYield(uint256 loanId, uint256 amount) internal {
        ActiveLoan memory loan = loans[loanId];
        
        // Calculate shares needed (simplified)
        uint256 shares = amount; // This would need proper calculation
        yieldOptimizer.withdraw(loan.collateralToken, shares, amount);
        
        emit CollateralRouted(loanId, loan.collateralToken, amount, address(0));
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return roles[role][account];
    }

    // ===== ADMIN FUNCTIONS =====

    function addSupportedToken(address token, bool isCollateral, bool isBorrowToken) external onlyAdmin {
        token.validateAddress();
        
        if (isCollateral) {
            supportedCollateral[token] = true;
        }
        
        if (isBorrowToken) {
            supportedBorrowTokens[token] = true;
        }
    }

    function setPriceOracle(
        address token, 
        address oracle, 
        uint256 heartbeat,
        uint8 decimals
    ) external onlyAdmin {
        token.validateAddress();
        oracle.validateAddress();
        
        priceOracles[token] = PriceOracle({
            oracle: AggregatorV3Interface(oracle),
            heartbeat: heartbeat,
            decimals: decimals
        });
    }

    function setYieldOptimizer(address _yieldOptimizer) external onlyAdmin {
        _yieldOptimizer.validateAddress();
        yieldOptimizer = IYieldOptimizer(_yieldOptimizer);
    }

    function setBaseInterestRate(uint256 _rate) external onlyAdmin {
        require(_rate <= MAX_INTEREST_RATE, "Rate too high");
        baseInterestRate = _rate;
    }

    function setPlatformFeeRate(uint256 _rate) external onlyAdmin {
        require(_rate <= 1000, "Fee too high"); // Max 10%
        platformFeeRate = _rate;
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