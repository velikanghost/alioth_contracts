// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAliothYieldOptimizer.sol";
import "../libraries/ValidationLib.sol";
import "../factories/ReceiptTokenFactory.sol";
import "../tokens/AliothReceiptToken.sol";

/**
 * @title AliothVault
 * @notice AI-optimized multi asset vault that issues receipt tokens users can see in their wallets
 * @dev Uses EnhancedYieldOptimizer for AI-driven protocol selection and receipt tokens (atUSDC, atDAI, etc.)
 */
contract AliothVault is ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    IAliothYieldOptimizer public immutable aliothYieldOptimizer;
    ReceiptTokenFactory public immutable receiptTokenFactory;

    /// @notice Token configuration and metadata
    struct TokenInfo {
        bool isSupported;
        address receiptToken;
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        uint256 minDeposit;
        uint256 maxDeposit;
        string symbol;
        uint8 decimals;
    }

    mapping(address => TokenInfo) public tokenInfo;

    address[] public supportedTokens;

    mapping(address => uint256) private tokenIndex;

    uint256 public depositFee = 0;

    uint256 public withdrawalFee = 0;

    uint256 public constant MAX_FEE = 500; // 5%

    /// @notice Address that receives fees
    address public feeRecipient;

    /// @notice Minimum shares to prevent dust attacks
    uint256 public constant MIN_SHARES = 1000;

    event TokenDeposit(
        address indexed user,
        address indexed token,
        address indexed receiptToken,
        uint256 amount,
        uint256 shares,
        uint256 optimizationId,
        uint256 timestamp
    );

    event TokenWithdraw(
        address indexed user,
        address indexed token,
        address indexed receiptToken,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event TokenAdded(
        address indexed token,
        address indexed receiptToken,
        string symbol
    );

    event TokenRemoved(address indexed token, address indexed receiptToken);
    event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event AIBackendAuthorized(address indexed aiBackend);
    event AIBackendRevoked(address indexed aiBackend);
    event TokenLimitsUpdated(
        address indexed token,
        uint256 oldMinDeposit,
        uint256 oldMaxDeposit,
        uint256 newMinDeposit,
        uint256 newMaxDeposit
    );

    constructor(address _aliothYieldOptimizer, address _owner) Ownable(_owner) {
        _aliothYieldOptimizer.validateAddress();
        _owner.validateAddress();

        aliothYieldOptimizer = IAliothYieldOptimizer(_aliothYieldOptimizer);
        feeRecipient = _owner;

        receiptTokenFactory = new ReceiptTokenFactory(address(this));
    }

    /**
     * @notice Deposit tokens with AI-driven protocol selection and receive receipt tokens (atTokens)
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares expected (slippage protection)
     * @param targetProtocol Target protocol ("aave", "compound", "yearn") - AI optimized
     * @return shares The number of receipt tokens received
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares,
        string calldata targetProtocol
    ) external nonReentrant returns (uint256 shares) {
        token.validateAddress();
        amount.validateAmount();
        require(tokenInfo[token].isSupported, "Token not supported");
        require(amount >= tokenInfo[token].minDeposit, "Below minimum deposit");

        TokenInfo storage info = tokenInfo[token];
        if (info.maxDeposit > 0) {
            require(amount <= info.maxDeposit, "Exceeds maximum deposit");
        }

        require(
            aliothYieldOptimizer.validateDepositWithChainlink(
                token,
                amount,
                targetProtocol
            ),
            "Chainlink validation failed"
        );

        uint256 fee = (amount * depositFee) / 10000;
        uint256 netAmount = amount - fee;

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        if (fee > 0) {
            ERC20(token).safeTransfer(feeRecipient, fee);
        }

        shares = _calculateDepositShares(token, netAmount);
        require(shares >= minShares, "Insufficient shares received");
        require(shares >= MIN_SHARES, "Shares below minimum");

        ERC20(token).safeTransfer(address(aliothYieldOptimizer), netAmount);

        uint256 optimizationId = aliothYieldOptimizer
            .executeSingleOptimizedDeposit(
                token,
                netAmount,
                targetProtocol,
                msg.sender
            );

        AliothReceiptToken receiptToken = AliothReceiptToken(info.receiptToken);
        receiptToken.mint(msg.sender, shares);

        info.totalDeposits += amount;

        emit TokenDeposit(
            msg.sender,
            token,
            info.receiptToken,
            amount,
            shares,
            optimizationId,
            block.timestamp
        );

        return shares;
    }

    /**
     * @notice Withdraw tokens by burning receipt tokens
     * @param token The token to withdraw
     * @param shares The number of receipt tokens to burn
     * @param minAmount Minimum amount expected (slippage protection)
     * @param targetProtocol Target protocol ("aave", "compound", "yearn") to withdraw from
     * @return amount The amount of tokens received
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount,
        string calldata targetProtocol
    ) external nonReentrant returns (uint256 amount) {
        token.validateAddress();
        shares.validateAmount();
        require(tokenInfo[token].isSupported, "Token not supported");

        TokenInfo storage info = tokenInfo[token];
        AliothReceiptToken receiptToken = AliothReceiptToken(info.receiptToken);

        require(
            receiptToken.balanceOf(msg.sender) >= shares,
            "Insufficient receipt tokens"
        );

        amount = _calculateWithdrawAmount(token, shares);
        require(amount >= minAmount, "Amount below minimum");

        uint256 fee = (amount * withdrawalFee) / 10000;
        uint256 netAmount = amount - fee;

        receiptToken.burn(msg.sender, shares);

        require(
            aliothYieldOptimizer.validateDepositWithChainlink(
                token,
                amount,
                targetProtocol
            ),
            "Chainlink validation failed"
        );

        uint256 withdrawnAmount = aliothYieldOptimizer.executeWithdrawal(
            token,
            amount,
            targetProtocol,
            msg.sender
        );
        require(withdrawnAmount >= netAmount, "Insufficient withdrawal amount");

        if (fee > 0) {
            ERC20(token).safeTransfer(feeRecipient, fee);
        }

        info.totalWithdrawals += amount;

        emit TokenWithdraw(
            msg.sender,
            token,
            info.receiptToken,
            amount,
            shares,
            block.timestamp
        );

        return netAmount;
    }

    /**
     * @notice Get comprehensive user portfolio information
     * @param user The user address
     * @return tokens Array of token addresses with positions
     * @return receiptTokens Array of receipt token addresses
     * @return shares Array of receipt token balances
     * @return values Array of current values
     * @return symbols Array of token symbols
     */
    function getUserPortfolio(
        address user
    )
        external
        view
        returns (
            address[] memory tokens,
            address[] memory receiptTokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols
        )
    {
        uint256 count = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            AliothReceiptToken receiptToken = AliothReceiptToken(
                tokenInfo[token].receiptToken
            );
            if (receiptToken.balanceOf(user) > 0) {
                count++;
            }
        }

        tokens = new address[](count);
        receiptTokens = new address[](count);
        shares = new uint256[](count);
        values = new uint256[](count);
        symbols = new string[](count);

        uint256 index = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            TokenInfo memory info = tokenInfo[token];
            AliothReceiptToken receiptToken = AliothReceiptToken(
                info.receiptToken
            );
            uint256 userShares = receiptToken.balanceOf(user);

            if (userShares > 0) {
                tokens[index] = token;
                receiptTokens[index] = info.receiptToken;
                shares[index] = userShares;
                symbols[index] = info.symbol;

                uint256 totalSupply = receiptToken.totalSupply();
                if (totalSupply > 0) {
                    values[index] = userShares;
                }

                index++;
            }
        }
    }

    /**
     * @notice Get vault stats for a specific token
     * @param token The token address
     * @return totalShares Total receipt tokens in circulation
     * @return totalValue Total value locked (simplified)
     * @return receiptTokenAddress Address of the receipt token
     */
    function getTokenStats(
        address token
    )
        external
        view
        returns (
            uint256 totalShares,
            uint256 totalValue,
            address receiptTokenAddress
        )
    {
        require(tokenInfo[token].isSupported, "Token not supported");

        TokenInfo memory info = tokenInfo[token];
        AliothReceiptToken receiptToken = AliothReceiptToken(info.receiptToken);

        totalShares = receiptToken.totalSupply();
        totalValue = totalShares; // Simplified - in production would query protocols
        receiptTokenAddress = info.receiptToken;
    }

    /**
     * @notice Preview how many receipt tokens would be received for a deposit
     * @param token The token address
     * @param amount The deposit amount
     * @return shares Expected receipt tokens to receive
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
     * @param shares The number of receipt tokens to withdraw
     * @return amount Expected amount to receive (after fees)
     */
    function previewWithdraw(
        address token,
        uint256 shares
    ) external view returns (uint256 amount) {
        require(tokenInfo[token].isSupported, "Token not supported");

        uint256 grossAmount = _calculateWithdrawAmount(token, shares);
        uint256 fee = (grossAmount * withdrawalFee) / 10000;

        return grossAmount > fee ? grossAmount - fee : 0;
    }

    /**
     * @notice Calculate shares to mint for a deposit
     * @param token The token address
     * @param amount The net deposit amount (after fees)
     * @return shares The number of receipt tokens to mint
     */
    function _calculateDepositShares(
        address token,
        uint256 amount
    ) internal view returns (uint256 shares) {
        AliothReceiptToken receiptToken = AliothReceiptToken(
            tokenInfo[token].receiptToken
        );
        uint256 totalSupply = receiptToken.totalSupply();

        if (totalSupply == 0) {
            // First deposit gets 1:1 shares
            return amount;
        }

        // For simplicity in AI optimization, use 1:1 ratio
        // In production, would calculate based on actual vault value
        return amount;
    }

    /**
     * @notice Calculate amount to return for a withdrawal
     * @param token The token address
     * @param shares The number of receipt tokens to burn
     * @return amount The amount of underlying tokens to return
     */
    function _calculateWithdrawAmount(
        address token,
        uint256 shares
    ) internal pure returns (uint256 amount) {
        return shares;
    }

    /**
     * @notice Add support for a new token and create its receipt token
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

        ERC20 tokenContract = ERC20(token);
        string memory symbol;
        uint8 decimals;

        try tokenContract.symbol() returns (string memory _symbol) {
            symbol = _symbol;
        } catch {
            symbol = "UNKNOWN";
        }

        try tokenContract.decimals() returns (uint8 _decimals) {
            decimals = _decimals;
        } catch {
            decimals = 18;
        }

        address receiptToken = receiptTokenFactory.createReceiptToken(
            token,
            symbol,
            decimals
        );

        tokenInfo[token] = TokenInfo({
            isSupported: true,
            receiptToken: receiptToken,
            totalDeposits: 0,
            totalWithdrawals: 0,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit,
            symbol: symbol,
            decimals: decimals
        });

        tokenIndex[token] = supportedTokens.length;
        supportedTokens.push(token);

        emit TokenAdded(token, receiptToken, symbol);
    }

    /**
     * @notice Remove support for a token
     * @param token The token address
     */
    function removeToken(address token) external onlyOwner {
        require(tokenInfo[token].isSupported, "Token not supported");

        uint256 index = tokenIndex[token];
        uint256 lastIndex = supportedTokens.length - 1;

        if (index != lastIndex) {
            address lastToken = supportedTokens[lastIndex];
            supportedTokens[index] = lastToken;
            tokenIndex[lastToken] = index;
        }

        supportedTokens.pop();
        delete tokenIndex[token];

        address receiptToken = tokenInfo[token].receiptToken;

        receiptTokenFactory.removeReceiptToken(token);

        delete tokenInfo[token];

        emit TokenRemoved(token, receiptToken);
    }

    /**
     * @notice Update deposit fee
     * @param _depositFee New deposit fee in basis points
     */
    function setDepositFee(uint256 _depositFee) external onlyOwner {
        require(_depositFee <= MAX_FEE, "Fee too high");
        uint256 oldFee = depositFee;
        depositFee = _depositFee;
        emit DepositFeeUpdated(oldFee, _depositFee);
    }

    /**
     * @notice Update withdrawal fee
     * @param _withdrawalFee New withdrawal fee in basis points
     */
    function setWithdrawalFee(uint256 _withdrawalFee) external onlyOwner {
        require(_withdrawalFee <= MAX_FEE, "Fee too high");
        uint256 oldFee = withdrawalFee;
        withdrawalFee = _withdrawalFee;
        emit WithdrawalFeeUpdated(oldFee, _withdrawalFee);
    }

    /**
     * @notice Update fee recipient
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        _feeRecipient.validateAddress();
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
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
     * @notice Check if a token is supported
     * @param token The token address
     * @return isSupported Whether the token is supported
     */
    function isTokenSupported(
        address token
    ) external view returns (bool isSupported) {
        return tokenInfo[token].isSupported;
    }

    /**
     * @notice Update min and max deposit limits for a supported token
     * @param token The token address
     * @param newMinDeposit New minimum deposit (in token's smallest unit)
     * @param newMaxDeposit New maximum deposit (0 = no limit)
     */
    function updateTokenLimits(
        address token,
        uint256 newMinDeposit,
        uint256 newMaxDeposit
    ) external onlyOwner {
        require(tokenInfo[token].isSupported, "Token not supported");

        TokenInfo storage info = tokenInfo[token];

        uint256 oldMin = info.minDeposit;
        uint256 oldMax = info.maxDeposit;

        info.minDeposit = newMinDeposit;
        info.maxDeposit = newMaxDeposit;

        emit TokenLimitsUpdated(
            token,
            oldMin,
            oldMax,
            newMinDeposit,
            newMaxDeposit
        );
    }
}
