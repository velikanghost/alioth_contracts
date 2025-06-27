// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IComet
 * @notice Interface for Compound III (Comet) protocol
 * @dev Main Comet contract interface for supply, withdraw, and market operations
 */
interface IComet {
    // Core functions
    function supply(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function supplyTo(address dst, address asset, uint256 amount) external;

    function withdrawTo(address to, address asset, uint256 amount) external;

    function supplyFrom(
        address from,
        address dst,
        address asset,
        uint256 amount
    ) external;

    function withdrawFrom(
        address src,
        address to,
        address asset,
        uint256 amount
    ) external;

    // Balance functions
    function balanceOf(address account) external view returns (uint256);

    function collateralBalanceOf(
        address account,
        address asset
    ) external view returns (uint128);

    function borrowBalanceOf(address account) external view returns (uint256);

    // Market configuration
    function baseToken() external view returns (address);

    function baseScale() external view returns (uint64);

    function baseIndexScale() external pure returns (uint64);

    function baseBorrowMin() external view returns (uint256);

    function baseMinForRewards() external view returns (uint256);

    function baseTrackingSupplySpeed() external view returns (uint256);

    function baseTrackingBorrowSpeed() external view returns (uint256);

    // Asset information
    function getAssetInfoByAddress(
        address asset
    ) external view returns (AssetInfo memory);

    function numAssets() external view returns (uint8);

    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

    // Market totals and state
    function totalsBasic() external view returns (TotalsBasic memory);

    function totalSupply() external view returns (uint256);

    function totalBorrow() external view returns (uint256);

    function totalsCollateral(
        address asset
    ) external view returns (TotalsCollateral memory);

    // Interest rates and pricing
    function getUtilization() external view returns (uint256);

    function getSupplyRate(uint256 utilization) external view returns (uint64);

    function getBorrowRate(uint256 utilization) external view returns (uint64);

    function getPrice(address priceFeed) external view returns (uint128);

    // Protocol state
    function isSupplyPaused() external view returns (bool);

    function isWithdrawPaused() external view returns (bool);

    function isBorrowCollateralized(
        address account
    ) external view returns (bool);

    function isLiquidatable(address account) external view returns (bool);

    // Account management
    function allow(address manager, bool isAllowed) external;

    function hasPermission(
        address owner,
        address manager
    ) external view returns (bool);

    function userNonce(address account) external view returns (uint256);

    // Transfer functions
    function transfer(address dst, uint256 amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool);

    function transferAsset(address dst, address asset, uint256 amount) external;

    function transferAssetFrom(
        address src,
        address dst,
        address asset,
        uint256 amount
    ) external;

    // Utility functions
    function accrueAccount(address account) external;

    function version() external view returns (string memory);
}

/**
 * @title ICometRewards
 * @notice Interface for Compound III rewards contract
 * @dev Handles claiming of COMP rewards for Comet users
 */
interface ICometRewards {
    function getRewardOwed(
        address comet,
        address account
    ) external returns (uint256);

    function claim(address comet, address src, bool shouldAccrue) external;

    function claimTo(
        address comet,
        address src,
        address to,
        bool shouldAccrue
    ) external;
}

/**
 * @title ICometConfiguration
 * @notice Interface for Compound III configurator contract
 * @dev Provides configuration data for Comet markets
 */
interface ICometConfiguration {
    function getConfiguration(
        address cometProxy
    ) external view returns (Configuration memory);

    function factory(address cometProxy) external view returns (address);
}

// Compound III data structures
struct AssetInfo {
    uint8 offset;
    address asset;
    address priceFeed;
    uint64 scale;
    uint64 borrowCollateralFactor;
    uint64 liquidateCollateralFactor;
    uint64 liquidationFactor;
    uint128 supplyCap;
}

struct TotalsBasic {
    uint64 baseSupplyIndex;
    uint64 baseBorrowIndex;
    uint64 trackingSupplyIndex;
    uint64 trackingBorrowIndex;
    uint104 totalSupplyBase;
    uint104 totalBorrowBase;
    uint40 lastAccrualTime;
    uint8 pauseFlags;
}

struct TotalsCollateral {
    uint128 totalSupplyAsset;
    uint128 _reserved;
}

struct UserBasic {
    int104 principal;
    uint64 baseTrackingIndex;
    uint64 baseTrackingAccrued;
    uint16 assetsIn;
}

struct Configuration {
    address governor;
    address pauseGuardian;
    address baseToken;
    address baseTokenPriceFeed;
    address extensionDelegate;
    uint64 supplyKink;
    uint64 supplyPerYearInterestRateSlopeLow;
    uint64 supplyPerYearInterestRateSlopeHigh;
    uint64 supplyPerYearInterestRateBase;
    uint64 borrowKink;
    uint64 borrowPerYearInterestRateSlopeLow;
    uint64 borrowPerYearInterestRateSlopeHigh;
    uint64 borrowPerYearInterestRateBase;
    uint64 storeFrontPriceFactor;
    uint64 trackingIndexScale;
    uint64 baseTrackingSupplySpeed;
    uint64 baseTrackingBorrowSpeed;
    uint104 baseMinForRewards;
    uint104 baseBorrowMin;
    uint104 targetReserves;
}

struct AssetConfig {
    address asset;
    address priceFeed;
    uint8 decimals;
    uint64 borrowCollateralFactor;
    uint64 liquidateCollateralFactor;
    uint64 liquidationFactor;
    uint128 supplyCap;
}
