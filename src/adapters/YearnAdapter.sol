// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IProtocolAdapter.sol";
import "../libraries/ValidationLib.sol";
import "../libraries/MathLib.sol";

// Yearn interfaces
interface IYearnVault {
    function deposit(
        uint256 amount,
        address recipient
    ) external returns (uint256);

    function withdraw(
        uint256 shares,
        address recipient,
        uint256 maxLoss
    ) external returns (uint256);

    function redeem(
        uint256 shares,
        address recipient,
        address owner
    ) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function asset() external view returns (address);

    function decimals() external view returns (uint8);

    function pricePerShare() external view returns (uint256);

    function depositLimit() external view returns (uint256);

    function availableDepositLimit() external view returns (uint256);

    function withdrawalQueue(uint256 index) external view returns (address);

    function lastReport() external view returns (uint256);

    function emergencyShutdown() external view returns (bool);
}

interface IYearnRegistry {
    function latestVault(address token) external view returns (address);

    function vaults(
        address token,
        uint256 index
    ) external view returns (address);

    function numVaults(address token) external view returns (uint256);
}

/**
 * @title YearnAdapter
 * @notice Protocol adapter for Yearn Finance vault protocol
 * @dev Implements IProtocolAdapter for integration with Alioth yield optimizer
 */
contract YearnAdapter is IProtocolAdapter, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ValidationLib for uint256;
    using ValidationLib for address;
    using MathLib for uint256;

    /// @notice Yearn Registry contract
    IYearnRegistry public immutable yearnRegistry;

    /// @notice Mapping of token to preferred vault address
    mapping(address => address) public vaults;

    /// @notice Mapping of supported tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Administrator address
    address public admin;

    /// @notice Emergency stop flag
    bool public emergencyStop;

    /// @notice Maximum withdrawal loss tolerance (in basis points)
    uint256 public maxLoss = 100; // 1% default

    /// @notice APY calculation period (1 week in seconds)
    uint256 public constant APY_PERIOD = 7 days;

    /// @notice Minimum time between APY updates
    uint256 public constant MIN_APY_UPDATE_INTERVAL = 1 hours;

    /// @notice Cached APY data
    mapping(address => uint256) public cachedAPY;
    mapping(address => uint256) public lastAPYUpdate;

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

    constructor(address _yearnRegistry, address _admin) {
        _yearnRegistry.validateAddress();
        _admin.validateAddress();

        yearnRegistry = IYearnRegistry(_yearnRegistry);
        admin = _admin;
    }

    /**
     * @notice Get the name of the protocol this adapter interfaces with
     * @return The protocol name
     */
    function protocolName() external pure returns (string memory) {
        return "Yearn";
    }

    /**
     * @notice Get the current APY for a given token
     * @param token The token address to check APY for
     * @return apy The current annual percentage yield (in basis points)
     */
    function getAPY(address token) external view returns (uint256 apy) {
        require(supportedTokens[token], "Token not supported");

        address vaultAddr = vaults[token];
        require(vaultAddr != address(0), "Vault not configured");

        IYearnVault vault = IYearnVault(vaultAddr);

        // Use cached APY if recently updated
        if (block.timestamp - lastAPYUpdate[token] < MIN_APY_UPDATE_INTERVAL) {
            return cachedAPY[token];
        }

        try vault.totalAssets() returns (uint256 totalAssets) {
            try vault.totalSupply() returns (uint256 totalSupply) {
                if (totalSupply == 0 || totalAssets == 0) {
                    return 0;
                }

                // Calculate APY based on price per share growth
                // This is a simplified calculation - in production would use historical data
                try vault.pricePerShare() returns (uint256 currentPPS) {
                    // Assume historical price per share for APY calculation
                    // In production, this would come from stored historical data or oracle
                    uint256 historicalPPS = (currentPPS * 9800) / 10000; // Assume 2% growth for demo

                    if (historicalPPS > 0 && currentPPS > historicalPPS) {
                        // Calculate APY: ((currentPPS / historicalPPS) - 1) * (365 / 7) * 10000
                        uint256 growthRate = ((currentPPS * 10000) /
                            historicalPPS) - 10000;
                        apy = (growthRate * 365) / 7; // Annualize weekly growth

                        // Cap at reasonable maximum (50%)
                        if (apy > 5000) apy = 5000;
                    }
                } catch {
                    apy = 0;
                }
            } catch {
                apy = 0;
            }
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

        address vaultAddr = vaults[token];
        if (vaultAddr != address(0)) {
            IYearnVault vault = IYearnVault(vaultAddr);

            try vault.balanceOf(address(this)) returns (uint256 shares) {
                if (shares > 0) {
                    try vault.convertToAssets(shares) returns (uint256 assets) {
                        tvl = assets;
                    } catch {
                        // Fallback calculation using price per share
                        try vault.pricePerShare() returns (uint256 pps) {
                            tvl = (shares * pps) / 1e18;
                        } catch {
                            tvl = 0;
                        }
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
     * @return shares The number of shares received (vault tokens)
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

        address vaultAddr = vaults[token];
        require(vaultAddr != address(0), "Vault not configured");

        IYearnVault vault = IYearnVault(vaultAddr);

        // Check deposit limits
        try vault.availableDepositLimit() returns (uint256 availableLimit) {
            require(amount <= availableLimit, "Deposit exceeds vault limit");
        } catch {
            // Continue if limit check fails - vault might not implement this
        }

        // Transfer tokens from caller
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Approve vault to spend tokens
        ERC20(token).safeApprove(vaultAddr, amount);

        try vault.deposit(amount, address(this)) returns (
            uint256 receivedShares
        ) {
            shares = receivedShares;

            // Validate minimum shares received
            ValidationLib.validateSlippage(minShares, shares, 500); // 5% max slippage

            emit Deposited(token, amount, shares);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Yearn deposit failed: ", reason)));
        }
    }

    /**
     * @notice Withdraw tokens from the protocol
     * @param token The token to withdraw
     * @param shares The number of shares to burn (vault token amount)
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

        address vaultAddr = vaults[token];
        require(vaultAddr != address(0), "Vault not configured");

        IYearnVault vault = IYearnVault(vaultAddr);

        // Check if we have enough vault shares
        uint256 vaultBalance = vault.balanceOf(address(this));
        require(vaultBalance >= shares, "Insufficient vault shares");

        try vault.redeem(shares, msg.sender, address(this)) returns (
            uint256 receivedAmount
        ) {
            amount = receivedAmount;

            // Validate minimum amount received
            ValidationLib.validateSlippage(minAmount, amount, maxLoss);

            emit Withdrawn(token, amount, shares);
        } catch {
            // Fallback to withdraw function if redeem fails
            try vault.withdraw(shares, msg.sender, maxLoss) returns (
                uint256 receivedAmount
            ) {
                amount = receivedAmount;

                // Validate minimum amount received
                ValidationLib.validateSlippage(minAmount, amount, maxLoss);

                emit Withdrawn(token, amount, shares);
            } catch Error(string memory reason) {
                revert(
                    string(
                        abi.encodePacked("Yearn withdrawal failed: ", reason)
                    )
                );
            }
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

        address vaultAddr = vaults[token];
        require(vaultAddr != address(0), "Vault not configured");

        IYearnVault vault = IYearnVault(vaultAddr);

        // Calculate unrealized yield (vault shares appreciation)
        uint256 currentShares = vault.balanceOf(address(this));
        if (currentShares > 0) {
            try vault.convertToAssets(currentShares) returns (
                uint256 /* currentValue */
            ) {
                // This is a simplified yield calculation
                // In practice, we'd track the original deposit amount
                yieldAmount = 0; // Yearn vaults auto-compound, so yield is in share appreciation

                emit YieldHarvested(token, yieldAmount);
            } catch {
                yieldAmount = 0;
                emit YieldHarvested(token, 0);
            }
        } else {
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
     * @return shares The current shares balance (vault token balance)
     */
    function getSharesBalance(
        address token
    ) external view returns (uint256 shares) {
        require(supportedTokens[token], "Token not supported");

        address vaultAddr = vaults[token];
        if (vaultAddr != address(0)) {
            IYearnVault vault = IYearnVault(vaultAddr);
            shares = vault.balanceOf(address(this));
        }
    }

    /**
     * @notice Convert shares to underlying token amount
     * @param token The token address
     * @param shares The number of shares (vault token amount)
     * @return amount The equivalent token amount
     */
    function sharesToTokens(
        address token,
        uint256 shares
    ) external view returns (uint256 amount) {
        require(supportedTokens[token], "Token not supported");

        address vaultAddr = vaults[token];
        if (vaultAddr != address(0) && shares > 0) {
            IYearnVault vault = IYearnVault(vaultAddr);

            try vault.convertToAssets(shares) returns (uint256 assets) {
                amount = assets;
            } catch {
                // Fallback calculation using price per share
                try vault.pricePerShare() returns (uint256 pps) {
                    amount = (shares * pps) / 1e18;
                } catch {
                    amount = 0;
                }
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

        address vaultAddr = vaults[token];
        if (vaultAddr != address(0) && amount > 0) {
            IYearnVault vault = IYearnVault(vaultAddr);

            try vault.convertToShares(amount) returns (uint256 vaultShares) {
                shares = vaultShares;
            } catch {
                // Fallback calculation using price per share
                try vault.pricePerShare() returns (uint256 pps) {
                    if (pps > 0) {
                        shares = (amount * 1e18) / pps;
                    }
                } catch {
                    shares = 0;
                }
            }
        }
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
        if (!supportedTokens[token]) {
            return (false, "Token not supported");
        }

        address vaultAddr = vaults[token];
        if (vaultAddr == address(0)) {
            return (false, "Vault not configured");
        }

        IYearnVault vault = IYearnVault(vaultAddr);

        // Check if vault is working and not emergency shutdown
        try vault.emergencyShutdown() returns (bool shutdown) {
            if (shutdown) {
                return (false, "Vault in emergency shutdown");
            }
        } catch {
            return (false, "Vault access failed");
        }

        // Check if vault has capacity
        try vault.availableDepositLimit() returns (uint256 limit) {
            if (limit == 0) {
                return (false, "Vault at capacity");
            }
        } catch {
            return (false, "Vault limit check failed");
        }

        isOperational = true;
        statusMessage = "Operational";
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
        require(supportedTokens[token], "Token not supported");

        // Yearn is considered high health protocol due to battle-tested strategies
        healthScore = 8800; // 88% health score

        address vaultAddr = vaults[token];
        if (vaultAddr != address(0)) {
            IYearnVault vault = IYearnVault(vaultAddr);

            // Get available liquidity (vault balance + strategy liquid assets)
            try vault.totalAssets() returns (uint256 totalAssets) {
                liquidityDepth = totalAssets;

                // For Yearn, utilization is typically high as assets are deployed in strategies
                // Most assets are utilized, so we'll estimate based on vault mechanics
                try vault.totalSupply() returns (uint256 supply) {
                    if (supply > 0) {
                        // Yearn vaults typically have high utilization (95%+)
                        utilizationRate = 9500; // 95% utilization estimate
                    } else {
                        utilizationRate = 0;
                    }
                } catch {
                    utilizationRate = 9000; // Default high utilization
                }
            } catch {
                liquidityDepth = 0;
                utilizationRate = 0;
            }
        } else {
            liquidityDepth = 0;
            utilizationRate = 0;
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
        require(supportedTokens[token], "Token not supported");

        // Yearn has medium risk due to:
        // - Strategy complexity and smart contract risk
        // - Dependency on underlying protocols
        // - But excellent track record and security practices
        riskScore = 3000; // 30% risk score (medium risk)
    }

    /**
     * @notice Get maximum recommended allocation percentage for this protocol
     * @param token The token address
     * @return maxAllocation Maximum allocation in basis points (e.g., 5000 = 50%)
     */
    function getMaxRecommendedAllocation(
        address token
    ) external view returns (uint256 maxAllocation) {
        require(supportedTokens[token], "Token not supported");

        // Yearn can handle moderate-large allocations but strategies have capacity limits
        maxAllocation = 5500; // 55% maximum allocation
    }

    // ===== ADMIN FUNCTIONS =====

    /**
     * @notice Add support for a new token with its vault
     * @param token The token address
     * @param vault The corresponding vault address
     */
    function addSupportedToken(
        address token,
        address vault
    ) external onlyAdmin {
        token.validateAddress();
        vault.validateAddress();

        IYearnVault vaultContract = IYearnVault(vault);

        // Validate vault corresponds to token
        try vaultContract.asset() returns (address vaultAsset) {
            require(vaultAsset == token, "Token/vault mismatch");
        } catch {
            revert("Invalid vault");
        }

        supportedTokens[token] = true;
        vaults[token] = vault;
    }

    /**
     * @notice Add support for a token using latest vault from registry
     * @param token The token address
     */
    function addSupportedTokenFromRegistry(address token) external onlyAdmin {
        token.validateAddress();

        try yearnRegistry.latestVault(token) returns (address latestVault) {
            require(latestVault != address(0), "No vault found in registry");

            // Validate the vault
            IYearnVault vaultContract = IYearnVault(latestVault);
            try vaultContract.asset() returns (address vaultAsset) {
                require(vaultAsset == token, "Registry vault mismatch");
            } catch {
                revert("Invalid registry vault");
            }

            supportedTokens[token] = true;
            vaults[token] = latestVault;
        } catch {
            revert("Failed to get vault from registry");
        }
    }

    /**
     * @notice Remove support for a token
     * @param token The token address
     */
    function removeSupportedToken(address token) external onlyAdmin {
        supportedTokens[token] = false;
        delete vaults[token];
        delete cachedAPY[token];
        delete lastAPYUpdate[token];
    }

    /**
     * @notice Update cached APY for a token
     * @param token The token address
     */
    function updateAPY(address token) external {
        require(supportedTokens[token], "Token not supported");

        // Force APY recalculation by calling getAPY
        uint256 newAPY = this.getAPY(token);
        cachedAPY[token] = newAPY;
        lastAPYUpdate[token] = block.timestamp;
    }

    /**
     * @notice Set maximum withdrawal loss tolerance
     * @param _maxLoss New maximum loss in basis points
     */
    function setMaxLoss(uint256 _maxLoss) external onlyAdmin {
        require(_maxLoss <= 1000, "Max loss too high"); // Max 10%
        maxLoss = _maxLoss;
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
}
