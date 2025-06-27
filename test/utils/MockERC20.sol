// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

contract MockERC20 is Test {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory sym) {
        name = sym;
        symbol = sym;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address t, uint256 a) external returns (bool) {
        _move(msg.sender, t, a);
        return true;
    }

    function transferFrom(
        address f,
        address t,
        uint256 a
    ) external returns (bool) {
        require(allowance[f][msg.sender] >= a, "allow");
        allowance[f][msg.sender] -= a;
        _move(f, t, a);
        return true;
    }

    function _move(address f, address t, uint256 a) internal {
        require(balanceOf[f] >= a, "bal");
        balanceOf[f] -= a;
        balanceOf[t] += a;
    }
}
