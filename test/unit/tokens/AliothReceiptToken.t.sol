// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/tokens/AliothReceiptToken.sol";

contract ReceiptTokenTest is Test {
    AliothReceiptToken rt;

    function setUp() public {
        rt = new AliothReceiptToken(
            address(0x1234), // dummy asset
            address(this), // vault/owner
            "Alioth TKN",
            "atTKN",
            18
        );
    }

    function testMintBurn() public {
        rt.mint(address(0xA), 100);
        assertEq(rt.totalSupply(), 100);
        assertEq(rt.balanceOf(address(0xA)), 100);

        vm.prank(address(this));
        rt.burn(address(0xA), 50);
        assertEq(rt.totalSupply(), 50);
        assertEq(rt.balanceOf(address(0xA)), 50);
    }
}
