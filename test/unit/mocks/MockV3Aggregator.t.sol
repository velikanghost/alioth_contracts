// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/mocks/MockV3Aggregator.sol";

contract MockAggrTest is Test {
    MockV3Aggregator aggr;

    function setUp() public {
        aggr = new MockV3Aggregator(8, 100e8, 1 hours);
    }

    function testAutomationUpdatesAnswer() public {
        (bool needed, ) = aggr.checkUpkeep("");
        assertFalse(needed);

        vm.warp(block.timestamp + 3600);

        (needed, ) = aggr.checkUpkeep("");
        assertTrue(needed);

        bytes memory data = abi.encode(int256(120e8));
        aggr.performUpkeep(data);

        (, int256 price, , , ) = aggr.latestRoundData();
        assertEq(price, 120e8);
    }
}
