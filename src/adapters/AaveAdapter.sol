// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IProtocolAdapter.sol";
import "../libraries/ValidationLib.sol";

// Mock Aave interfaces for demonstration
interface IAavePool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function getReserveData(
        address asset
    ) external view returns (ReserveData memory);
}

interface IAToken {
    function balanceOf(address user) external view returns (uint256);

    function scaledBalanceOf(address user) external view returns (uint256);
}

struct ReserveData {
    uint256 liquidityRate;
    uint256 variableBorrowRate;
    uint256 stableBorrowRate;
    uint256 liquidityIndex;
    uint256 variableBorrowIndex;
    uint256 lastUpdateTimestamp;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
}

/**
 * @title AaveAdapter
 * @notice Protocol adapter for Aave lending protocol
 * @dev Implements IProtocolAdapter for integration with Alioth yield optimizer
 */
contract AaveAdapter is IProtocolAdapter, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    /// @notice Aave pool contract
    IAavePool public immutable aavePool;

    /// @notice Mapping of token to aToken address
    mapping(address => address) public aTokens;

    /// @notice Mapping of supported tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Administrator address
    address public admin;

    /// @notice Emergency stop flag
    bool public emergencyStop;

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

    constructor(address _aavePool, address _admin) {
        _aavePool.validateAddress();
        _admin.validateAddress();

        aavePool = IAavePool(_aavePool);
        admin = _admin;
    }

    /**
     * @notice Get the name of the protocol this adapter interfaces with
     * @return The protocol name
     */
    function protocolName() external pure returns (string memory) {
        return "Aave";
    }

    /**
     * @notice Get the current APY for a given token
     * @param token The token address to check APY for
     * @return apy The current annual percentage yield (in basis points)
     */
    function getAPY(address token) external view returns (uint256 apy) {
        require(supportedTokens[token], "Token not supported");

        try aavePool.getReserveData(token) returns (
            ReserveData memory reserveData
        ) {
            // Convert Aave's liquidity rate (ray format) to basis points
            // Aave rates are in ray (1e27), we need basis points (1e4)
            apy = reserveData.liquidityRate / 1e23; // 1e27 / 1e23 = 1e4 (basis points)

            // Cap at reasonable maximum (50%)
            if (apy > 5000) apy = 5000;
        } catch {
            apy = 0;
        }
    }

    /**
     * @notice Get the current TVL for a given token in this protocol
     * @param token The token address to check TVL for
     * @return tvl The total value locked for this token
     */
    function getTVL(address token) external view returns (uint256 tvl) {
        require(supportedTokens[token], "Token not supported");

        address aToken = aTokens[token];
        if (aToken != address(0)) {
            try IAToken(aToken).balanceOf(address(this)) returns (
                uint256 balance
            ) {
                tvl = balance;
            } catch {
                tvl = 0;
            }
        }
    }

    /**
     * @notice Deposit tokens into the protocol
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param minShares Minimum shares expected to prevent slippage
     * @return shares The number of shares received (aToken balance)
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external payable nonReentrant whenNotStopped returns (uint256 shares) {
        require(msg.value == 0, "ETH not supported");
        token.validateAddress();
        amount.validateAmount();
        require(supportedTokens[token], "Token not supported");

        address aToken = aTokens[token];
        require(aToken != address(0), "aToken not configured");

        // Get initial aToken balance
        uint256 initialBalance = IAToken(aToken).balanceOf(address(this));

        // Transfer tokens from caller
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Approve Aave pool
        ERC20(token).safeApprove(address(aavePool), amount);

        // Supply to Aave
        try aavePool.supply(token, amount, address(this), 0) {
            // Calculate shares received (difference in aToken balance)
            uint256 finalBalance = IAToken(aToken).balanceOf(address(this));
            shares = finalBalance - initialBalance;

            // Validate minimum shares
            ValidationLib.validateSlippage(minShares, shares, 500); // 5% max slippage

            emit Deposited(token, amount, shares);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Aave deposit failed: ", reason)));
        }
    }

    /**
     * @notice Withdraw tokens from the protocol
     * @param token The token to withdraw
     * @param shares The number of shares to burn (amount in aTokens)
     * @param minAmount Minimum amount expected to prevent slippage
     * @return amount The amount of tokens received
     */
    function withdraw(
        address token,
        uint256 shares,
        uint256 minAmount
    ) external nonReentrant whenNotStopped returns (uint256 amount) {
        token.validateAddress();
        shares.validateAmount();
        require(supportedTokens[token], "Token not supported");

        address aToken = aTokens[token];
        require(aToken != address(0), "aToken not configured");

        // Check if we have enough aToken balance
        uint256 aTokenBalance = IAToken(aToken).balanceOf(address(this));
        require(aTokenBalance >= shares, "Insufficient aToken balance");

        // Withdraw from Aave (shares = amount in this case for aTokens)
        try aavePool.withdraw(token, shares, address(this)) returns (
            uint256 withdrawn
        ) {
            amount = withdrawn;

            // Validate minimum amount
            ValidationLib.validateSlippage(minAmount, amount, 500); // 5% max slippage

            // Transfer tokens to caller
            ERC20(token).safeTransfer(msg.sender, amount);

            emit Withdrawn(token, amount, shares);
        } catch Error(string memory reason) {
            revert(
                string(abi.encodePacked("Aave withdrawal failed: ", reason))
            );
        }
    }

    /**
     * @notice Harvest yield from the protocol
     * @param token The token to harvest yield for
     * @return yieldAmount The amount of yield harvested
     */
    function harvestYield(
        address token
    ) external returns (uint256 yieldAmount) {
        require(supportedTokens[token], "Token not supported");

        // For Aave, yield is automatically compounded in aTokens
        // This function could potentially claim any additional rewards
        // For now, we'll just return 0 as aTokens automatically compound
        yieldAmount = 0;

        emit YieldHarvested(token, yieldAmount);
    }

    /**
     * @notice Check if the protocol supports a given token
     * @param token The token address to check
     * @return supported True if the token is supported
     */
    function supportsToken(
        address token
    ) external view returns (bool supported) {
        return supportedTokens[token];
    }

    /**
     * @notice Get the shares balance for a given token
     * @param token The token address
     * @return shares The current shares balance (aToken balance)
     */
    function getSharesBalance(
        address token
    ) external view returns (uint256 shares) {
        require(supportedTokens[token], "Token not supported");

        address aToken = aTokens[token];
        if (aToken != address(0)) {
            shares = IAToken(aToken).balanceOf(address(this));
        }
    }

    /**
     * @notice Convert shares to underlying token amount
     * @param token The token address
     * @param shares The number of shares (aToken amount)
     * @return amount The equivalent token amount
     */
    function sharesToTokens(
        address token,
        uint256 shares
    ) external view returns (uint256 amount) {
        require(supportedTokens[token], "Token not supported");

        // For Aave, aTokens have 1:1 relationship with underlying tokens
        // plus accrued interest, so we can use the shares amount directly
        // In a more sophisticated implementation, we'd use the liquidity index
        amount = shares;
    }

    /**
     * @notice Convert token amount to shares
     * @param token The token address
     * @param amount The token amount
     * @return shares The equivalent number of shares
     */
    function tokensToShares(
        address token,
        uint256 amount
    ) external view returns (uint256 shares) {
        require(supportedTokens[token], "Token not supported");

        // For Aave, tokens have approximately 1:1 relationship with aTokens
        // In a more sophisticated implementation, we'd use the liquidity index
        shares = amount;
    }

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add support for a new token
     * @param token The token address
     * @param aToken The corresponding aToken address
     */
    function addSupportedToken(
        address token,
        address aToken
    ) external onlyAdmin {
        token.validateAddress();
        aToken.validateAddress();

        supportedTokens[token] = true;
        aTokens[token] = aToken;
    }

    /**
     * @notice Remove support for a token
     * @param token The token address
     */
    function removeSupportedToken(address token) external onlyAdmin {
        supportedTokens[token] = false;
        delete aTokens[token];
    }

    /**
     * @notice Toggle emergency stop
     */
    function toggleEmergencyStop() external onlyAdmin {
        emergencyStop = !emergencyStop;
    }

    /**
     * @notice Emergency withdraw function for stuck funds
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyAdmin {
        require(emergencyStop, "Emergency stop not active");

        if (token == address(0)) {
            payable(admin).transfer(amount);
        } else {
            ERC20(token).safeTransfer(admin, amount);
        }
    }

    /**
     * @notice Transfer admin role
     * @param newAdmin New administrator address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        newAdmin.validateAddress();
        admin = newAdmin;
    }
}
