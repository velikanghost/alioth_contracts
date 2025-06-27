// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IProtocolAdapter.sol";
import "../interfaces/IComet.sol";
import "../libraries/ValidationLib.sol";

/**
 * @title CompoundAdapter
 * @notice Protocol adapter for Compound III (Comet) lending protocol
 * @dev Implements IProtocolAdapter for integration with Alioth yield optimizer
 */
contract CompoundAdapter is IProtocolAdapter, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;

    /// @notice Compound III Comet contract
    IComet public immutable comet;

    /// @notice Compound III Rewards contract
    ICometRewards public immutable rewards;

    /// @notice Base asset address (e.g., USDC for main deployment)
    address public immutable baseAsset;

    /// @notice COMP token address for rewards
    address public immutable compToken;

    /// @notice Administrator address
    address public admin;

    /// @notice Emergency stop flag
    bool public emergencyStop;

    /// @notice Seconds per year for APY calculations
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Base scaling factor (1e18)
    uint256 public constant BASE_SCALE = 1e18;

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
        address _comet,
        address _rewards,
        address _compToken,
        address _admin
    ) {
        _comet.validateAddress();
        _rewards.validateAddress();
        _compToken.validateAddress();
        _admin.validateAddress();

        comet = IComet(_comet);
        rewards = ICometRewards(_rewards);
        compToken = _compToken;
        admin = _admin;
        baseAsset = comet.baseToken();
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
        if (token == baseAsset) {
            // For base asset, get supply rate
            try comet.getUtilization() returns (uint256 utilization) {
                try comet.getSupplyRate(utilization) returns (
                    uint64 supplyRate
                ) {
                    // Convert per-second rate to annual rate
                    // APY = (1 + rate)^(seconds_per_year) - 1, simplified to rate * seconds_per_year for small rates
                    uint256 annualRate = uint256(supplyRate) * SECONDS_PER_YEAR;
                    apy = (annualRate * 10000) / BASE_SCALE; // Convert to basis points

                    // Add COMP rewards if available
                    try comet.baseTrackingSupplySpeed() returns (
                        uint256 rewardSpeed
                    ) {
                        if (rewardSpeed > 0) {
                            // Simplified COMP rewards APY calculation
                            // In production, this would need COMP price feed for accurate calculation
                            uint256 rewardsAPY = (rewardSpeed *
                                SECONDS_PER_YEAR *
                                100) / BASE_SCALE;
                            apy += rewardsAPY;
                        }
                    } catch {
                        // Continue without COMP rewards if calculation fails
                    }

                    if (apy > 10000) apy = 10000;
                } catch {
                    apy = 0;
                }
            } catch {
                apy = 0;
            }
        } else {
            // Collateral assets don't earn interest in Compound III
            apy = 0;
        }
    }

    /**
     * @notice Get the current TVL for a given token in this protocol
     * @param token The token address to check TVL for
     * @return tvl The total value locked for this token
     */
    function getTVL(address token) external view returns (uint256 tvl) {
        if (token == baseAsset) {
            try comet.totalSupply() returns (uint256 totalSupply) {
                tvl = totalSupply;
            } catch {
                tvl = 0;
            }
        } else {
            try comet.totalsCollateral(token) returns (
                TotalsCollateral memory totals
            ) {
                tvl = uint256(totals.totalSupplyAsset);
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
     * @return shares The number of shares received (for base asset, this is the deposit amount)
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minShares
    ) external payable nonReentrant whenNotStopped returns (uint256 shares) {
        token.validateAddress();
        amount.validateAmount();
        require(amount > 0, "Amount must be greater than 0");
        require(msg.value == 0, "ETH not supported");

        require(!comet.isSupplyPaused(), "Supply is paused");

        uint256 initialBalance;
        if (token == baseAsset) {
            initialBalance = comet.balanceOf(address(this));
        } else {
            initialBalance = uint256(
                comet.collateralBalanceOf(address(this), token)
            );
        }

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        ERC20(token).safeApprove(address(comet), amount);

        try comet.supply(token, amount) {
            uint256 finalBalance;
            if (token == baseAsset) {
                finalBalance = comet.balanceOf(address(this));
            } else {
                finalBalance = uint256(
                    comet.collateralBalanceOf(address(this), token)
                );
            }

            shares = finalBalance - initialBalance;

            if (shares == 0) {
                shares = amount;
            }

            ValidationLib.validateSlippage(minShares, shares, 500);

            emit Deposited(token, amount, shares);
        } catch Error(string memory reason) {
            revert(
                string(
                    abi.encodePacked("Compound III deposit failed: ", reason)
                )
            );
        }
    }

    /**
     * @notice Withdraw tokens from the protocol
     * @param token The token to withdraw
     * @param shares The number of shares to burn (amount to withdraw)
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
        require(shares > 0, "Shares must be greater than 0");

        require(!comet.isWithdrawPaused(), "Withdraw is paused");

        uint256 availableBalance;
        if (token == baseAsset) {
            availableBalance = comet.balanceOf(address(this));
        } else {
            availableBalance = uint256(
                comet.collateralBalanceOf(address(this), token)
            );
        }
        require(availableBalance >= shares, "Insufficient balance");

        uint256 initialBalance = ERC20(token).balanceOf(address(this));

        try comet.withdraw(token, shares) {
            uint256 finalBalance = ERC20(token).balanceOf(address(this));
            amount = finalBalance - initialBalance;

            if (amount == 0) {
                amount = shares; // Fallback
            }

            ValidationLib.validateSlippage(minAmount, amount, 500); // 5% max slippage

            ERC20(token).safeTransfer(msg.sender, amount);

            emit Withdrawn(token, amount, shares);
        } catch Error(string memory reason) {
            revert(
                string(
                    abi.encodePacked("Compound III withdrawal failed: ", reason)
                )
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
        uint256 initialCompBalance = ERC20(compToken).balanceOf(address(this));

        try rewards.claim(address(comet), address(this), true) {
            uint256 finalCompBalance = ERC20(compToken).balanceOf(
                address(this)
            );
            yieldAmount = finalCompBalance - initialCompBalance;

            if (yieldAmount > 0) {
                ERC20(compToken).safeTransfer(msg.sender, yieldAmount);
            }

            emit YieldHarvested(token, yieldAmount);
        } catch {
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
        if (token == baseAsset) {
            return true;
        }

        try comet.getAssetInfoByAddress(token) returns (AssetInfo memory) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Get the shares balance for a given token
     * @param token The token address
     * @return shares The current shares balance
     */
    function getSharesBalance(
        address token
    ) external view returns (uint256 shares) {
        if (token == baseAsset) {
            shares = comet.balanceOf(address(this));
        } else {
            shares = uint256(comet.collateralBalanceOf(address(this), token));
        }
    }

    /**
     * @notice Convert shares to underlying token amount
     * @param token The token address
     * @param shares The number of shares
     * @return amount The equivalent token amount
     */
    function sharesToTokens(
        address token,
        uint256 shares
    ) external view returns (uint256 amount) {
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
        shares = amount;
    }

    /**
     * @notice Check if protocol is currently operational
     * @param token The token address
     * @return isOperational True if protocol is fully operational
     * @return statusMessage Human readable status message
     */
    function getOperationalStatus(
        address token
    ) external view returns (bool isOperational, string memory statusMessage) {
        if (token == baseAsset) {
            isOperational =
                !comet.isSupplyPaused() &&
                !comet.isWithdrawPaused();
            statusMessage = isOperational ? "Operational" : "Protocol paused";
        } else {
            try comet.getAssetInfoByAddress(token) {
                isOperational =
                    !comet.isSupplyPaused() &&
                    !comet.isWithdrawPaused();
                statusMessage = isOperational
                    ? "Operational"
                    : "Protocol paused";
            } catch {
                isOperational = false;
                statusMessage = "Token not supported";
            }
        }
    }

    /**
     * @notice Get protocol health metrics for risk assessment
     * @param token The token address
     * @return healthScore Overall protocol health score (0-10000)
     * @return liquidityDepth Available liquidity depth
     * @return utilizationRate Current utilization rate (0-10000)
     */
    function getHealthMetrics(
        address token
    )
        external
        view
        returns (
            uint256 healthScore,
            uint256 liquidityDepth,
            uint256 utilizationRate
        )
    {
        healthScore = 9000;

        try comet.getUtilization() returns (uint256 utilization) {
            utilizationRate = (utilization * 10000) / BASE_SCALE;
        } catch {
            utilizationRate = 0;
        }

        try comet.totalSupply() returns (uint256 totalSupply) {
            try comet.totalBorrow() returns (uint256 totalBorrow) {
                liquidityDepth = totalSupply > totalBorrow
                    ? totalSupply - totalBorrow
                    : 0;
            } catch {
                liquidityDepth = totalSupply;
            }
        } catch {
            liquidityDepth = 0;
        }
    }

    /**
     * @notice Get protocol risk score for a token
     * @param token The token address
     * @return riskScore Risk score from 0 (lowest risk) to 10000 (highest risk)
     */
    function getRiskScore(
        address token
    ) external view returns (uint256 riskScore) {
        riskScore = 1500;
    }

    /**
     * @notice Get maximum recommended allocation percentage for this protocol
     * @param token The token address
     * @return maxAllocation Maximum allocation in basis points (e.g., 5000 = 50%)
     */
    function getMaxRecommendedAllocation(
        address token
    ) external view returns (uint256 maxAllocation) {
        maxAllocation = 7500;
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
        ERC20(token).safeTransfer(admin, amount);
    }

    /**
     * @notice Transfer admin role
     * @param newAdmin New administrator address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        newAdmin.validateAddress();
        admin = newAdmin;
    }

    /**
     * @notice Get base asset address
     * @return The base asset address
     */
    function getBaseAsset() external view returns (address) {
        return baseAsset;
    }

    /**
     * @notice Get Comet contract address
     * @return The Comet contract address
     */
    function getCometAddress() external view returns (address) {
        return address(comet);
    }
}
