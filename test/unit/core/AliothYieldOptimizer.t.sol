// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/core/AliothYieldOptimizer.sol";
import {MockFeedMgr} from "../../utils/MockFeedMgr.sol";
import {MockAdapter} from "../../utils/MockAdapter.sol";
import {MockERC20} from "../../utils/MockERC20.sol";

contract AliothYieldOptimizerTest is Test {
    AliothYieldOptimizer opt;
    MockFeedMgr feed;
    MockAdapter adapter;
    MockERC20 usdc;

    function setUp() public {
        feed = new MockFeedMgr();
        adapter = new MockAdapter();
        usdc = new MockERC20("USDC");

        opt = new AliothYieldOptimizer(
            address(1), // dummy messenger
            address(feed),
            address(this) // admin
        );
        opt.addProtocol(address(adapter));

        // authorize this contract as vault
        opt.authorizeVault(address(this));

        // Price feed returns >0
        feed.setPrice(address(usdc), 1e8);
        adapter.setAPY(500); // 5 %

        usdc.mint(address(this), 1e6);
        usdc.approve(address(opt), 1e6);
        // also fund optimizer directly to bypass internal transfer logic in mock
        usdc.mint(address(opt), 1e6);
    }

    function testExecuteDeposit() public {
        usdc.mint(address(this), 1e6);
        usdc.approve(address(opt), 1e6);

        uint256 id = opt.executeSingleOptimizedDeposit(
            address(usdc),
            1e6,
            "aave",
            address(this)
        );
        (, , uint256 amt, , , , , , , ) = opt.optimizations(id);
        assertEq(amt, 1e6);
    }
}
