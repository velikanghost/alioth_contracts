// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/adapters/AaveAdapter.sol";

contract AaveAdapterTest is Test {
    AaveAdapter adapter;

    function setUp() public {
        adapter = new AaveAdapter(address(1), address(this));
    }

    function testProtocolName() public {
        assertEq(adapter.protocolName(), "Aave");
    }

    // addDeposit / withdraw mocks as needed
}
