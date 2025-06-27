// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/adapters/CompoundAdapter.sol";

interface ICometMinimal {
    function baseToken() external view returns (address);
}

contract MockComet is ICometMinimal {
    address public immutable token;

    constructor(address _t) {
        token = _t;
    }

    function baseToken() external view override returns (address) {
        return token;
    }
}

contract MockRewards {
    // stub only; no logic required for this test
}

contract CompoundAdapterTest is Test {
    CompoundAdapter adapter;

    function setUp() public {
        MockComet comet = new MockComet(address(0xBEEF));
        MockRewards rewards = new MockRewards();
        adapter = new CompoundAdapter(
            address(comet),
            address(rewards),
            address(0xCAFE),
            address(this)
        );
    }

    function testProtocolName() public {
        assertEq(adapter.protocolName(), "Compound");
    }
}
