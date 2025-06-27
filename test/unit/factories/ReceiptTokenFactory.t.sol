// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/factories/ReceiptTokenFactory.sol";

contract FactoryTest is Test {
    ReceiptTokenFactory factory;

    function setUp() public {
        factory = new ReceiptTokenFactory(address(this));
    }

    function testCreateAndRemove() public {
        address underlying = address(0x1234);
        address token = factory.createReceiptToken(underlying, "TKN", 18);
        assertTrue(token != address(0));

        factory.removeReceiptToken(underlying);
        // mapping cleared
        assertEq(factory.getReceiptToken(underlying), address(0));
    }
}
