// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../libraries/DynamicAllocationLib.sol";

/**
 * @title ChainlinkFeedManager
 * @notice Manages Chainlink data feed addresses for different tokens
 * @dev Central registry for price feeds, rate feeds, and volatility feeds
 */
contract ChainlinkFeedManager is AccessControl {
    bytes32 public constant FEED_MANAGER_ROLE = keccak256("FEED_MANAGER_ROLE");

    /// @notice Mapping from token address to its Chainlink feeds
    mapping(address => DynamicAllocationLib.ChainlinkFeeds) public tokenFeeds;

    /// @notice Array of supported tokens
    address[] public supportedTokens;

    /// @notice Mapping to check if token is supported
    mapping(address => bool) public isSupportedToken;

    event FeedsUpdated(
        address indexed token,
        address priceFeed,
        address rateFeed,
        address volatilityFeed
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEED_MANAGER_ROLE, admin);
    }

    /**
     * @notice Add or update Chainlink feeds for a token
     * @param token Token address
     * @param priceFeed Price feed address (required)
     * @param rateFeed Rate/APY feed address (optional)
     * @param volatilityFeed Volatility feed address (optional)
     */
    function setTokenFeeds(
        address token,
        address priceFeed,
        address rateFeed,
        address volatilityFeed
    ) public onlyRole(FEED_MANAGER_ROLE) {
        require(token != address(0), "Invalid token address");
        require(priceFeed != address(0), "Price feed required");

        // Add token to supported list if not already present
        if (!isSupportedToken[token]) {
            supportedTokens.push(token);
            isSupportedToken[token] = true;
            emit TokenAdded(token);
        }

        tokenFeeds[token] = DynamicAllocationLib.ChainlinkFeeds({
            priceFeed: AggregatorV3Interface(priceFeed),
            rateFeed: AggregatorV3Interface(rateFeed),
            volatilityFeed: AggregatorV3Interface(volatilityFeed)
        });

        emit FeedsUpdated(token, priceFeed, rateFeed, volatilityFeed);
    }

    /**
     * @notice Remove a token and its feeds
     * @param token Token address to remove
     */
    function removeToken(address token) external onlyRole(FEED_MANAGER_ROLE) {
        require(isSupportedToken[token], "Token not supported");

        // Remove from supported tokens array
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
                supportedTokens.pop();
                break;
            }
        }

        // Clear feeds
        delete tokenFeeds[token];
        isSupportedToken[token] = false;

        emit TokenRemoved(token);
    }

    /**
     * @notice Get Chainlink feeds for a token
     * @param token Token address
     * @return feeds ChainlinkFeeds struct containing all feed addresses
     */
    function getTokenFeeds(
        address token
    ) external view returns (DynamicAllocationLib.ChainlinkFeeds memory feeds) {
        require(isSupportedToken[token], "Token not supported");
        return tokenFeeds[token];
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
     * @notice Get number of supported tokens
     * @return count Number of supported tokens
     */
    function getSupportedTokensCount() external view returns (uint256 count) {
        return supportedTokens.length;
    }

    /**
     * @notice Check if token has all required feeds
     * @param token Token address
     * @return hasPrice True if token has price feed
     * @return hasRate True if token has rate feed
     * @return hasVolatility True if token has volatility feed
     */
    function checkFeedAvailability(
        address token
    ) external view returns (bool hasPrice, bool hasRate, bool hasVolatility) {
        if (!isSupportedToken[token]) {
            return (false, false, false);
        }

        DynamicAllocationLib.ChainlinkFeeds memory feeds = tokenFeeds[token];
        hasPrice = address(feeds.priceFeed) != address(0);
        hasRate = address(feeds.rateFeed) != address(0);
        hasVolatility = address(feeds.volatilityFeed) != address(0);
    }

    /**
     * @notice Batch set feeds for multiple tokens
     * @param tokens Array of token addresses
     * @param priceFeeds Array of price feed addresses
     * @param rateFeeds Array of rate feed addresses
     * @param volatilityFeeds Array of volatility feed addresses
     */
    function batchSetTokenFeeds(
        address[] calldata tokens,
        address[] calldata priceFeeds,
        address[] calldata rateFeeds,
        address[] calldata volatilityFeeds
    ) external onlyRole(FEED_MANAGER_ROLE) {
        require(
            tokens.length == priceFeeds.length &&
                tokens.length == rateFeeds.length &&
                tokens.length == volatilityFeeds.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            setTokenFeeds(
                tokens[i],
                priceFeeds[i],
                rateFeeds[i],
                volatilityFeeds[i]
            );
        }
    }

    /**
     * @notice Emergency function to update a single feed
     * @param token Token address
     * @param feedType Feed type (0=price, 1=rate, 2=volatility)
     * @param newFeed New feed address
     */
    function emergencyUpdateFeed(
        address token,
        uint8 feedType,
        address newFeed
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isSupportedToken[token], "Token not supported");
        require(feedType <= 2, "Invalid feed type");

        DynamicAllocationLib.ChainlinkFeeds storage feeds = tokenFeeds[token];

        if (feedType == 0) {
            require(newFeed != address(0), "Price feed cannot be zero");
            feeds.priceFeed = AggregatorV3Interface(newFeed);
        } else if (feedType == 1) {
            feeds.rateFeed = AggregatorV3Interface(newFeed);
        } else {
            feeds.volatilityFeed = AggregatorV3Interface(newFeed);
        }

        emit FeedsUpdated(
            token,
            address(feeds.priceFeed),
            address(feeds.rateFeed),
            address(feeds.volatilityFeed)
        );
    }
}
