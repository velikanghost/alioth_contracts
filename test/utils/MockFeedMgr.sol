// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "src/core/ChainlinkFeedManager.sol";
import "src/mocks/MockV3Aggregator.sol";

contract MockFeedMgr is ChainlinkFeedManager {
    constructor() ChainlinkFeedManager(msg.sender) {}

    function setPrice(address tok, uint256 price) external {
        MockV3Aggregator feed = new MockV3Aggregator(8, int256(price), 60);
        setTokenFeeds(tok, address(feed), address(0), address(0));
    }
}
