// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IProtocolAdapter.sol";
import "../libraries/ValidationLib.sol";

// Compound interfaces
interface ICToken {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function underlying() external view returns (address);
}

interface IComptroller {
    function claimComp(address holder) external;

    function getCompAddress() external view returns (address);

    function compSpeeds(address cToken) external view returns (uint256);
}

interface ICEther {
    function mint() external payable;

    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);
}

/**
 * @title CompoundAdapter
 * @notice Protocol adapter for Compound Finance lending protocol
 * @dev Implements IProtocolAdapter for integration with Alioth yield optimizer
 */
contract CompoundAdapter is IProtocolAdapter, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    /// @notice Compound Comptroller contract
    IComptroller public immutable comptroller;

    /// @notice COMP token address
    address public immutable compToken;

    /// @notice cETH address for native ETH handling
    address public immutable cEther;

    /// @notice Mapping of token to cToken address
    mapping(address => address) public cTokens;

    /// @notice Mapping of supported tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Administrator address
    address public admin;

    /// @notice Emergency stop flag
    bool public emergencyStop;

    /// @notice Blocks per year for APY calculations (approximately 2,102,400 blocks/year)
    uint256 public constant BLOCKS_PER_YEAR = 2102400;

    /// @notice Base mantissa for calculations (1e18)
    uint256 public constant BASE_MANTISSA = 1e18;

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

    constructor(
        address _comptroller,
        address _compToken,
        address _cEther,
        address _admin
    ) {
        _comptroller.validateAddress();
        _compToken.validateAddress();
        _cEther.validateAddress();
        _admin.validateAddress();

        comptroller = IComptroller(_comptroller);
        compToken = _compToken;
        cEther = _cEther;
        admin = _admin;
    }

    /**
     * @notice Get the name of the protocol this adapter interfaces with
     * @return The protocol name
     */
    function protocolName() external pure returns (string memory) {
        return "Compound";
    }

    /**
     * @notice Get the current APY for a given token
     * @param token The token address to check APY for
     * @return apy The current annual percentage yield (in basis points)
     */
    function getAPY(address token) external view returns (uint256 apy) {
        require(supportedTokens[token], "Token not supported");

        address cTokenAddr = cTokens[token];
        require(cTokenAddr != address(0), "cToken not configured");

        try ICToken(cTokenAddr).supplyRatePerBlock() returns (
            uint256 supplyRatePerBlock
        ) {
            // Convert per-block rate to annual rate
            // APY = ((1 + supplyRatePerBlock)^BLOCKS_PER_YEAR - 1) * 10000 (for basis points)
            // Simplified calculation for gas efficiency
            uint256 annualSupplyRate = supplyRatePerBlock * BLOCKS_PER_YEAR;
            apy = (annualSupplyRate * 10000) / BASE_MANTISSA;

            // Add COMP rewards if available
            try comptroller.compSpeeds(cTokenAddr) returns (uint256 compSpeed) {
                if (compSpeed > 0) {
                    // Simplified COMP rewards calculation
                    // In production, this would need price feeds for accurate calculation
                    uint256 compRewardsAPY = (compSpeed *
                        BLOCKS_PER_YEAR *
                        100) / BASE_MANTISSA; // Simplified
                    apy += compRewardsAPY;
                }
            } catch {
                // Continue without COMP rewards if calculation fails
            }

            // Cap at reasonable maximum (100%)
            if (apy > 10000) apy = 10000;
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

        address cTokenAddr = cTokens[token];
        if (cTokenAddr != address(0)) {
            try ICToken(cTokenAddr).balanceOf(address(this)) returns (
                uint256 cTokenBalance
            ) {
                if (cTokenBalance > 0) {
                    try ICToken(cTokenAddr).exchangeRateStored() returns (
                        uint256 exchangeRate
                    ) {
                        tvl = (cTokenBalance * exchangeRate) / BASE_MANTISSA;
                    } catch {
                        tvl = 0;
                    }
                }
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
     * @return shares The number of shares received (cToken balance)
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external payable nonReentrant whenNotStopped returns (uint256 shares) {
        token.validateAddress();
        amount.validateAmount();
        require(supportedTokens[token], "Token not supported");

        address cTokenAddr = cTokens[token];
        require(cTokenAddr != address(0), "cToken not configured");

        // Get initial cToken balance
        uint256 initialBalance = ICToken(cTokenAddr).balanceOf(address(this));

        // Handle ETH vs ERC20
        if (token == address(0)) {
            // Native ETH deposit
            require(msg.value == amount, "ETH amount mismatch");

            try ICEther(cTokenAddr).mint{value: amount}() {
                uint256 finalBalance = ICToken(cTokenAddr).balanceOf(
                    address(this)
                );
                shares = finalBalance - initialBalance;

                // Validate minimum shares
                ValidationLib.validateSlippage(minShares, shares, 500); // 5% max slippage

                emit Deposited(token, amount, shares);
            } catch Error(string memory reason) {
                revert(
                    string(
                        abi.encodePacked(
                            "Compound ETH deposit failed: ",
                            reason
                        )
                    )
                );
            }
        } else {
            // ERC20 token deposit
            ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            ERC20(token).safeApprove(cTokenAddr, amount);

            try ICToken(cTokenAddr).mint(amount) returns (uint256 mintResult) {
                require(mintResult == 0, "Compound mint failed");

                uint256 finalBalance = ICToken(cTokenAddr).balanceOf(
                    address(this)
                );
                shares = finalBalance - initialBalance;

                // Validate minimum shares
                ValidationLib.validateSlippage(minShares, shares, 500); // 5% max slippage

                emit Deposited(token, amount, shares);
            } catch Error(string memory reason) {
                revert(
                    string(
                        abi.encodePacked("Compound deposit failed: ", reason)
                    )
                );
            }
        }
    }

    /**
     * @notice Withdraw tokens from the protocol
     * @param token The token to withdraw
     * @param shares The number of shares to burn (cToken amount)
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

        address cTokenAddr = cTokens[token];
        require(cTokenAddr != address(0), "cToken not configured");

        // Check if we have enough cToken balance
        uint256 cTokenBalance = ICToken(cTokenAddr).balanceOf(address(this));
        require(cTokenBalance >= shares, "Insufficient cToken balance");

        // Get initial token balance
        uint256 initialBalance = token == address(0)
            ? address(this).balance
            : ERC20(token).balanceOf(address(this));

        try ICToken(cTokenAddr).redeem(shares) returns (uint256 redeemResult) {
            require(redeemResult == 0, "Compound redeem failed");

            // Calculate amount received
            uint256 finalBalance = token == address(0)
                ? address(this).balance
                : ERC20(token).balanceOf(address(this));
            amount = finalBalance - initialBalance;

            // Validate minimum amount
            ValidationLib.validateSlippage(minAmount, amount, 500); // 5% max slippage

            // Transfer tokens to caller
            if (token == address(0)) {
                payable(msg.sender).transfer(amount);
            } else {
                ERC20(token).safeTransfer(msg.sender, amount);
            }

            emit Withdrawn(token, amount, shares);
        } catch Error(string memory reason) {
            revert(
                string(abi.encodePacked("Compound withdrawal failed: ", reason))
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

        // Claim COMP rewards
        uint256 initialCompBalance = ERC20(compToken).balanceOf(address(this));

        try comptroller.claimComp(address(this)) {
            uint256 finalCompBalance = ERC20(compToken).balanceOf(
                address(this)
            );
            yieldAmount = finalCompBalance - initialCompBalance;

            if (yieldAmount > 0) {
                // Transfer COMP to caller (in production, might want to convert to base token)
                ERC20(compToken).safeTransfer(msg.sender, yieldAmount);
            }

            emit YieldHarvested(token, yieldAmount);
        } catch {
            // Continue if COMP claiming fails
            yieldAmount = 0;
            emit YieldHarvested(token, 0);
        }
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
     * @return shares The current shares balance (cToken balance)
     */
    function getSharesBalance(
        address token
    ) external view returns (uint256 shares) {
        require(supportedTokens[token], "Token not supported");

        address cTokenAddr = cTokens[token];
        if (cTokenAddr != address(0)) {
            shares = ICToken(cTokenAddr).balanceOf(address(this));
        }
    }

    /**
     * @notice Convert shares to underlying token amount
     * @param token The token address
     * @param shares The number of shares (cToken amount)
     * @return amount The equivalent token amount
     */
    function sharesToTokens(
        address token,
        uint256 shares
    ) external view returns (uint256 amount) {
        require(supportedTokens[token], "Token not supported");

        address cTokenAddr = cTokens[token];
        if (cTokenAddr != address(0) && shares > 0) {
            try ICToken(cTokenAddr).exchangeRateStored() returns (
                uint256 exchangeRate
            ) {
                amount = (shares * exchangeRate) / BASE_MANTISSA;
            } catch {
                amount = 0;
            }
        }
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

        address cTokenAddr = cTokens[token];
        if (cTokenAddr != address(0) && amount > 0) {
            try ICToken(cTokenAddr).exchangeRateStored() returns (
                uint256 exchangeRate
            ) {
                shares = (amount * BASE_MANTISSA) / exchangeRate;
            } catch {
                shares = 0;
            }
        }
    }

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add support for a new token
     * @param token The token address (address(0) for ETH)
     * @param cToken The corresponding cToken address
     */
    function addSupportedToken(
        address token,
        address cToken
    ) external onlyAdmin {
        cToken.validateAddress();

        // Validate cToken corresponds to token
        if (token != address(0)) {
            try ICToken(cToken).underlying() returns (address underlying) {
                require(underlying == token, "Token/cToken mismatch");
            } catch {
                revert("Invalid cToken");
            }
        } else {
            // For ETH, ensure it's the cETH token
            require(cToken == cEther, "Must use cETH for ETH");
        }

        supportedTokens[token] = true;
        cTokens[token] = cToken;
    }

    /**
     * @notice Remove support for a token
     * @param token The token address
     */
    function removeSupportedToken(address token) external onlyAdmin {
        supportedTokens[token] = false;
        delete cTokens[token];
    }

    /**
     * @notice Toggle emergency stop
     */
    function toggleEmergencyStop() external onlyAdmin {
        emergencyStop = !emergencyStop;
    }

    /**
     * @notice Emergency withdraw function for stuck funds
     * @param token Token to withdraw (address(0) for ETH)
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

    // Allow contract to receive ETH
    receive() external payable {}
}
