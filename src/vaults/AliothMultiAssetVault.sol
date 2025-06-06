// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IYieldOptimizer.sol";
import "../libraries/ValidationLib.sol";

/**
 * @title AliothMultiAssetVault
 * @notice Multi-asset vault that manages positions across multiple tokens and protocols
 * @dev Single contract that handles unlimited tokens through the YieldOptimizer
 */
contract AliothMultiAssetVault is ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    /// @notice The YieldOptimizer contract that manages cross-protocol allocation
    IYieldOptimizer public immutable yieldOptimizer;

    /// @notice User position data for each token
    struct UserPosition {
        uint256 shares; // User's share amount
        uint256 lastDepositTime; // Last deposit timestamp
        uint256 totalDeposited; // Total amount ever deposited
        uint256 totalWithdrawn; // Total amount ever withdrawn
    }

    /// @notice Token configuration and metadata
    struct TokenInfo {
        bool isSupported; // Whether token is supported
        uint256 totalShares; // Total shares for this token
        uint256 totalDeposits; // Total deposits ever made
        uint256 totalWithdrawals; // Total withdrawals ever made
        uint256 minDeposit; // Minimum deposit amount
        uint256 maxDeposit; // Maximum deposit amount (0 = no limit)
        string symbol; // Cached symbol for display
    }

    /// @notice Mapping: token => user => position
    mapping(address => mapping(address => UserPosition)) public positions;

    /// @notice Mapping: token => token info
    mapping(address => TokenInfo) public tokenInfo;

    /// @notice Array of all supported tokens
    address[] public supportedTokens;

    /// @notice Mapping: token => index in supportedTokens array
    mapping(address => uint256) private tokenIndex;

    /// @notice Fee charged on deposits (in basis points)
    uint256 public depositFee = 0; // 0% initially

    /// @notice Fee charged on withdrawals (in basis points)
    uint256 public withdrawalFee = 0; // 0% initially

    /// @notice Maximum fees that can be charged (safety limit)
    uint256 public constant MAX_FEE = 500; // 5%

    /// @notice Address that receives fees
    address public feeRecipient;

    /// @notice Minimum shares to prevent dust attacks
    uint256 public constant MIN_SHARES = 1000;

    // ===== EVENTS =====

    event TokenDeposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event TokenWithdraw(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);
    event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event YieldHarvested(address indexed token, uint256 amount);

    constructor(address _yieldOptimizer, address _owner) Ownable(_owner) {
        _yieldOptimizer.validateAddress();
        _owner.validateAddress();

        yieldOptimizer = IYieldOptimizer(_yieldOptimizer);
        feeRecipient = _owner;
    }

    // ===== CORE VAULT FUNCTIONS =====

    /**
     * @notice Deposit tokens and receive shares in the optimized yield strategies
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares expected (slippage protection)
     * @return shares The number of shares received
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external nonReentrant returns (uint256 shares) {
        token.validateAddress();
        amount.validateAmount();
        require(tokenInfo[token].isSupported, "Token not supported");
        require(amount >= tokenInfo[token].minDeposit, "Below minimum deposit");

        TokenInfo storage info = tokenInfo[token];
        if (info.maxDeposit > 0) {
            require(amount <= info.maxDeposit, "Exceeds maximum deposit");
        }

        // Calculate deposit fee
        uint256 fee = (amount * depositFee) / 10000;
        uint256 netAmount = amount - fee;

        // Transfer tokens from user
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Send fee to recipient if applicable
        if (fee > 0) {
            ERC20(token).safeTransfer(feeRecipient, fee);
        }

        // Calculate shares based on current vault value
        shares = _calculateDepositShares(token, netAmount);
        require(shares >= minShares, "Insufficient shares received");
        require(shares >= MIN_SHARES, "Shares below minimum");

        // Approve and deposit to YieldOptimizer
        ERC20(token).safeApprove(address(yieldOptimizer), netAmount);
        uint256 optimizerShares = yieldOptimizer.deposit(token, netAmount, 0);

        // Update user position
        UserPosition storage position = positions[token][msg.sender];
        position.shares += shares;
        position.lastDepositTime = block.timestamp;
        position.totalDeposited += amount;

        // Update token info
        info.totalShares += shares;
        info.totalDeposits += amount;

        emit TokenDeposit(msg.sender, token, amount, shares, block.timestamp);
    }

    /**
     * @notice Withdraw tokens by burning shares
     * @param token The token to withdraw
     * @param shares The number of shares to burn
     * @param minAmount Minimum amount expected (slippage protection)
     * @return amount The amount of tokens received
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount
    ) external nonReentrant returns (uint256 amount) {
        token.validateAddress();
        shares.validateAmount();
        require(tokenInfo[token].isSupported, "Token not supported");

        UserPosition storage position = positions[token][msg.sender];
        require(position.shares >= shares, "Insufficient shares");

        // Calculate amount to receive based on current vault value
        uint256 grossAmount = _calculateWithdrawAmount(token, shares);
        require(grossAmount >= minAmount, "Insufficient amount received");

        // Calculate withdrawal fee
        uint256 fee = (grossAmount * withdrawalFee) / 10000;
        uint256 netAmount = grossAmount - fee;

        // Withdraw from YieldOptimizer
        uint256 receivedAmount = yieldOptimizer.withdraw(
            token,
            shares,
            grossAmount
        );

        // Update user position
        position.shares -= shares;
        position.totalWithdrawn += receivedAmount;

        // Update token info
        TokenInfo storage info = tokenInfo[token];
        info.totalShares -= shares;
        info.totalWithdrawals += receivedAmount;

        // Send fee to recipient if applicable
        if (fee > 0 && receivedAmount >= fee) {
            ERC20(token).safeTransfer(feeRecipient, fee);
            receivedAmount -= fee;
        }

        // Transfer tokens to user
        ERC20(token).safeTransfer(msg.sender, receivedAmount);

        emit TokenWithdraw(
            msg.sender,
            token,
            receivedAmount,
            shares,
            block.timestamp
        );

        // Return the actual amount received by the user
        return receivedAmount;
    }

    /**
     * @notice Harvest yield for a specific token
     * @param token The token to harvest yield for
     * @return totalYield Total yield harvested
     */
    function harvestYield(
        address token
    ) external onlyOwner returns (uint256 totalYield) {
        require(tokenInfo[token].isSupported, "Token not supported");

        totalYield = yieldOptimizer.harvestAll(token);
        emit YieldHarvested(token, totalYield);
    }

    /**
     * @notice Harvest yield for all supported tokens
     * @return totalYields Array of yields harvested per token
     */
    function harvestAllTokens()
        external
        onlyOwner
        returns (uint256[] memory totalYields)
    {
        totalYields = new uint256[](supportedTokens.length);

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            totalYields[i] = yieldOptimizer.harvestAll(token);
            emit YieldHarvested(token, totalYields[i]);
        }
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @notice Get user's position for a specific token
     * @param user The user address
     * @param token The token address
     * @return shares User's shares
     * @return value Current value in underlying token
     * @return apy Current APY for the token
     */
    function getUserPosition(
        address user,
        address token
    ) external view returns (uint256 shares, uint256 value, uint256 apy) {
        UserPosition memory position = positions[token][user];
        shares = position.shares;

        if (shares > 0 && tokenInfo[token].totalShares > 0) {
            uint256 totalValue = yieldOptimizer.getTotalTVL(token);
            value = (shares * totalValue) / tokenInfo[token].totalShares;
        }

        apy = yieldOptimizer.getWeightedAPY(token);
    }

    /**
     * @notice Get all user positions across all tokens
     * @param user The user address
     * @return tokens Array of token addresses
     * @return shares Array of share amounts
     * @return values Array of current values
     * @return symbols Array of token symbols
     * @return apys Array of current APYs
     */
    function getUserPortfolio(
        address user
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols,
            uint256[] memory apys
        )
    {
        // Count non-zero positions
        uint256 count = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (positions[supportedTokens[i]][user].shares > 0) {
                count++;
            }
        }

        // Allocate arrays
        tokens = new address[](count);
        shares = new uint256[](count);
        values = new uint256[](count);
        symbols = new string[](count);
        apys = new uint256[](count);

        // Populate arrays
        uint256 index = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            UserPosition memory position = positions[token][user];

            if (position.shares > 0) {
                tokens[index] = token;
                shares[index] = position.shares;
                symbols[index] = tokenInfo[token].symbol;
                apys[index] = yieldOptimizer.getWeightedAPY(token);

                // Calculate current value
                uint256 totalValue = yieldOptimizer.getTotalTVL(token);
                if (tokenInfo[token].totalShares > 0) {
                    values[index] =
                        (position.shares * totalValue) /
                        tokenInfo[token].totalShares;
                }

                index++;
            }
        }
    }

    /**
     * @notice Get vault stats for a specific token
     * @param token The token address
     * @return totalShares Total shares for the token
     * @return totalValue Total value locked
     * @return apy Current weighted APY
     * @return userCount Number of users with positions
     */
    function getTokenStats(
        address token
    )
        external
        view
        returns (
            uint256 totalShares,
            uint256 totalValue,
            uint256 apy,
            uint256 userCount
        )
    {
        require(tokenInfo[token].isSupported, "Token not supported");

        totalShares = tokenInfo[token].totalShares;
        totalValue = yieldOptimizer.getTotalTVL(token);
        apy = yieldOptimizer.getWeightedAPY(token);

        // Note: userCount would require additional tracking to be efficient
        userCount = 0; // Placeholder - could be implemented with additional mappings
    }

    /**
     * @notice Get current allocation for a token across protocols
     * @param token The token address
     * @return allocations Array of current allocations per protocol
     */
    function getTokenAllocation(
        address token
    )
        external
        view
        returns (IYieldOptimizer.AllocationTarget[] memory allocations)
    {
        return yieldOptimizer.getCurrentAllocation(token);
    }

    /**
     * @notice Preview how many shares would be received for a deposit
     * @param token The token address
     * @param amount The deposit amount
     * @return shares Expected shares to receive
     */
    function previewDeposit(
        address token,
        uint256 amount
    ) external view returns (uint256 shares) {
        require(tokenInfo[token].isSupported, "Token not supported");

        uint256 fee = (amount * depositFee) / 10000;
        uint256 netAmount = amount - fee;

        return _calculateDepositShares(token, netAmount);
    }

    /**
     * @notice Preview how much amount would be received for a withdrawal
     * @param token The token address
     * @param shares The number of shares to withdraw
     * @return amount Expected amount to receive
     */
    function previewWithdraw(
        address token,
        uint256 shares
    ) external view returns (uint256 amount) {
        require(tokenInfo[token].isSupported, "Token not supported");

        uint256 grossAmount = _calculateWithdrawAmount(token, shares);
        uint256 fee = (grossAmount * withdrawalFee) / 10000;

        return grossAmount - fee;
    }

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add support for a new token
     * @param token The token address
     * @param minDeposit Minimum deposit amount
     * @param maxDeposit Maximum deposit amount (0 = no limit)
     */
    function addToken(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external onlyOwner {
        token.validateAddress();
        require(!tokenInfo[token].isSupported, "Token already supported");

        // Get token symbol
        string memory symbol;
        try ERC20(token).symbol() returns (string memory _symbol) {
            symbol = _symbol;
        } catch {
            symbol = "UNKNOWN";
        }

        tokenInfo[token] = TokenInfo({
            isSupported: true,
            totalShares: 0,
            totalDeposits: 0,
            totalWithdrawals: 0,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit,
            symbol: symbol
        });

        tokenIndex[token] = supportedTokens.length;
        supportedTokens.push(token);

        emit TokenAdded(token, symbol);
    }

    /**
     * @notice Remove support for a token (only if no active positions)
     * @param token The token address
     */
    function removeToken(address token) external onlyOwner {
        require(tokenInfo[token].isSupported, "Token not supported");
        require(tokenInfo[token].totalShares == 0, "Active positions exist");

        // Remove from supportedTokens array
        uint256 index = tokenIndex[token];
        uint256 lastIndex = supportedTokens.length - 1;

        if (index != lastIndex) {
            address lastToken = supportedTokens[lastIndex];
            supportedTokens[index] = lastToken;
            tokenIndex[lastToken] = index;
        }

        supportedTokens.pop();
        delete tokenIndex[token];
        delete tokenInfo[token];

        emit TokenRemoved(token);
    }

    /**
     * @notice Set deposit fee (only owner)
     * @param newFee New deposit fee in basis points
     */
    function setDepositFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee too high");
        uint256 oldFee = depositFee;
        depositFee = newFee;
        emit DepositFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Set withdrawal fee (only owner)
     * @param newFee New withdrawal fee in basis points
     */
    function setWithdrawalFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "Fee too high");
        uint256 oldFee = withdrawalFee;
        withdrawalFee = newFee;
        emit WithdrawalFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Set fee recipient (only owner)
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        newRecipient.validateAddress();
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @notice Update token limits
     * @param token The token address
     * @param minDeposit New minimum deposit
     * @param maxDeposit New maximum deposit (0 = no limit)
     */
    function updateTokenLimits(
        address token,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external onlyOwner {
        require(tokenInfo[token].isSupported, "Token not supported");

        tokenInfo[token].minDeposit = minDeposit;
        tokenInfo[token].maxDeposit = maxDeposit;
    }

    // ===== INTERNAL FUNCTIONS =====

    /**
     * @notice Calculate shares to mint for a deposit
     * @param token The token address
     * @param amount The deposit amount (after fees)
     * @return shares The number of shares to mint
     */
    function _calculateDepositShares(
        address token,
        uint256 amount
    ) internal view returns (uint256 shares) {
        uint256 totalValue = yieldOptimizer.getTotalTVL(token);
        uint256 totalShares = tokenInfo[token].totalShares;

        if (totalShares == 0 || totalValue == 0) {
            // First deposit or no value - 1:1 ratio
            shares = amount;
        } else {
            // shares = (amount * totalShares) / totalValue
            shares = (amount * totalShares) / totalValue;
        }
    }

    /**
     * @notice Calculate amount to receive for a withdrawal
     * @param token The token address
     * @param shares The number of shares to burn
     * @return amount The amount to receive (before fees)
     */
    function _calculateWithdrawAmount(
        address token,
        uint256 shares
    ) internal view returns (uint256 amount) {
        uint256 totalValue = yieldOptimizer.getTotalTVL(token);
        uint256 totalShares = tokenInfo[token].totalShares;

        if (totalShares == 0) {
            return 0;
        }

        // amount = (shares * totalValue) / totalShares
        amount = (shares * totalValue) / totalShares;
    }

    // ===== UTILITY FUNCTIONS =====

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
     * @notice Check if a token is supported
     * @param token The token address
     * @return supported Whether the token is supported
     */
    function isTokenSupported(
        address token
    ) external view returns (bool supported) {
        return tokenInfo[token].isSupported;
    }

    /**
     * @notice Get the total number of supported tokens
     * @return count Number of supported tokens
     */
    function getSupportedTokenCount() external view returns (uint256 count) {
        return supportedTokens.length;
    }

    /**
     * @notice Emergency function to recover stuck tokens (only owner)
     * @param token The token address
     * @param amount The amount to recover
     */
    function emergencyRecoverToken(
        address token,
        uint256 amount
    ) external onlyOwner {
        // Only allow recovery of unsupported tokens or excess amounts
        if (tokenInfo[token].isSupported) {
            uint256 expectedBalance = yieldOptimizer.getTotalTVL(token);
            uint256 currentBalance = ERC20(token).balanceOf(address(this));
            require(currentBalance > expectedBalance, "No excess tokens");
            require(
                amount <= currentBalance - expectedBalance,
                "Amount too high"
            );
        }

        ERC20(token).safeTransfer(owner(), amount);
    }
}
