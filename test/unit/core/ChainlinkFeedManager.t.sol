// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/core/ChainlinkFeedManager.sol";
import {MockV3Aggregator} from "src/mocks/MockV3Aggregator.sol";

contract FeedMgrTest is Test {
    ChainlinkFeedManager mgr;
    MockV3Aggregator price;

    address constant ETH = address(0xE);

    function setUp() public {
        mgr = new ChainlinkFeedManager(address(this));
        price = new MockV3Aggregator(8, 1800e8, 60);

        mgr.setTokenFeeds(ETH, address(price), address(0), address(0));
    }

    function testValidateTokenPrice() public {
        // price = 1800 USD; 1 wei token == 1 USD for test
        assertTrue(mgr.validateTokenPrice(ETH, 1e18));
    }

    function testStalePriceReverts() public {
        vm.warp(block.timestamp + 3601);
        bool ok = mgr.validateTokenPrice(ETH, 1e18);
        assertFalse(ok);
    }
}
