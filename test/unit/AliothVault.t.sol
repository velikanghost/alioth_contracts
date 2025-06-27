// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/vaults/AliothVault.sol";
import "src/interfaces/IProtocolAdapter.sol";
import "src/interfaces/IAliothYieldOptimizer.sol";

// ──────────────────────────── Mocks ────────────────────────────

contract MockERC20 is Test {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _sym) {
        name = _sym;
        symbol = _sym;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract MockOptimizer is IAliothYieldOptimizer, Test {
    uint256 public lastId;

    function validateDepositWithChainlink(
        address,
        uint256,
        string calldata
    ) external pure returns (bool) {
        return true;
    }

    function executeSingleOptimizedDeposit(
        address,
        uint256,
        string calldata,
        address
    ) external returns (uint256 id) {
        lastId++;
        return lastId;
    }

    function executeWithdrawal(
        address token,
        uint256 amount,
        string calldata,
        address beneficiary
    ) external returns (uint256) {
        // Simply send tokens back
        MockERC20(token).transfer(beneficiary, amount);
        return amount;
    }

    // below are unused interface functions -> dummy implementations
    function authorizeVault(address) external {}

    function revokeVault(address) external {}

    function authorizeAIBackend(address) external {}

    function revokeAIBackend(address) external {}

    function addProtocol(address) external {}

    function removeProtocol(address) external {}

    function authorizedAIBackends(address) external view returns (bool) {
        return false;
    }

    function optimizations(
        uint256
    )
        external
        view
        returns (
            address,
            address,
            uint256,
            uint8,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint8
        )
    {
        return (address(0), address(0), 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function updateRebalanceParams(uint256, uint256) external {}

    function setEmergencyStop(bool) external {}
}

contract AliothVaultTest is Test {
    AliothVault vault;
    MockERC20 token;
    MockOptimizer optimizer;

    function setUp() public {
        token = new MockERC20("TKN");
        optimizer = new MockOptimizer();
        vault = new AliothVault(address(optimizer), address(this));
        // Add token support
        vault.addToken(address(token), 0, 0);
        // Mint tokens to user
        token.mint(address(this), 1e18);
        token.approve(address(vault), type(uint256).max);
    }

    function testDepositAndWithdraw() public {
        uint256 shares = vault.deposit(address(token), 1e18, 0, "aave");
        assertEq(shares, 1e18, "shares 1:1");

        uint256 recBal = vault.previewWithdraw(address(token), shares);
        assertEq(recBal, 1e18, "preview correct");

        // Withdraw
        uint256 amountOut = vault.withdraw(address(token), shares, 0, "aave");
        assertEq(amountOut, 1e18, "received full amount");
        assertEq(token.balanceOf(address(this)), 1e18, "user got tokens back");
    }
}
