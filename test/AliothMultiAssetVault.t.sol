// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/vaults/AliothMultiAssetVault.sol";
import "../src/interfaces/IAliothMultiAssetVault.sol";
import "../src/core/YieldOptimizer.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/core/CCIPMessenger.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol, decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

// Mock YieldOptimizer for testing
contract MockYieldOptimizer {
    mapping(address => uint256) public totalTVL;
    mapping(address => uint256) public weightedAPY;

    function deposit(
        address token,
        uint256 amount,
        uint256
    ) external returns (uint256) {
        totalTVL[token] += amount;
        return amount; // 1:1 shares for simplicity
    }

    function withdraw(
        address token,
        uint256 shares,
        uint256
    ) external returns (uint256) {
        uint256 amount = shares; // 1:1 for simplicity
        totalTVL[token] -= amount;
        MockERC20(token).transfer(msg.sender, amount);
        return amount;
    }

    function getTotalTVL(address token) external view returns (uint256) {
        return totalTVL[token];
    }

    function getWeightedAPY(address token) external view returns (uint256) {
        return weightedAPY[token];
    }

    function harvestAll(address) external pure returns (uint256) {
        return 0; // No yield for mock
    }

    function getCurrentAllocation(
        address
    ) external pure returns (IYieldOptimizer.AllocationTarget[] memory) {
        return new IYieldOptimizer.AllocationTarget[](0);
    }

    // Helper functions for testing
    function setAPY(address token, uint256 apy) external {
        weightedAPY[token] = apy;
    }

    function fundContract(address token, uint256 amount) external {
        MockERC20(token).mint(address(this), amount);
    }
}

contract AliothMultiAssetVaultTest is Test {
    AliothMultiAssetVault vault;
    MockYieldOptimizer mockOptimizer;
    MockERC20 aaveToken;
    MockERC20 usdcToken;
    MockERC20 wethToken;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address feeRecipient = address(0x4);

    event TokenDeposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event TokenWithdraw(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    function setUp() public {
        // Create mock tokens
        aaveToken = new MockERC20("AAVE", "AAVE", 18);
        usdcToken = new MockERC20("USD Coin", "USDC", 6);
        wethToken = new MockERC20("Wrapped Ether", "WETH", 18);

        // Create mock optimizer
        mockOptimizer = new MockYieldOptimizer();

        // Deploy vault
        vault = new AliothMultiAssetVault(address(mockOptimizer), owner);

        // Add tokens to vault
        vm.startPrank(owner);
        vault.addToken(address(aaveToken), 1e17, 0); // Min 0.1 AAVE
        vault.addToken(address(usdcToken), 1e6, 10000e6); // Min 1 USDC, max 10k
        vault.addToken(address(wethToken), 1e16, 0); // Min 0.01 ETH
        vm.stopPrank();

        // Mint tokens to users
        aaveToken.mint(user1, 1000e18);
        usdcToken.mint(user1, 100000e6);
        wethToken.mint(user1, 100e18);

        aaveToken.mint(user2, 1000e18);
        usdcToken.mint(user2, 100000e6);
        wethToken.mint(user2, 100e18);

        // Fund the mock optimizer
        mockOptimizer.fundContract(address(aaveToken), 10000e18);
        mockOptimizer.fundContract(address(usdcToken), 1000000e6);
        mockOptimizer.fundContract(address(wethToken), 1000e18);

        // Set mock APYs
        mockOptimizer.setAPY(address(aaveToken), 800); // 8%
        mockOptimizer.setAPY(address(usdcToken), 1200); // 12%
        mockOptimizer.setAPY(address(wethToken), 400); // 4%
    }

    // ===== BASIC FUNCTIONALITY TESTS =====

    function testDeployment() public {
        assertEq(address(vault.yieldOptimizer()), address(mockOptimizer));
        assertEq(vault.owner(), owner);
        assertEq(vault.feeRecipient(), owner);
        assertEq(vault.depositFee(), 0);
        assertEq(vault.withdrawalFee(), 0);
        assertEq(vault.getSupportedTokenCount(), 3);
    }

    function testTokenSupport() public {
        assertTrue(vault.isTokenSupported(address(aaveToken)));
        assertTrue(vault.isTokenSupported(address(usdcToken)));
        assertTrue(vault.isTokenSupported(address(wethToken)));

        address[] memory tokens = vault.getSupportedTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(aaveToken));
        assertEq(tokens[1], address(usdcToken));
        assertEq(tokens[2], address(wethToken));
    }

    // ===== DEPOSIT TESTS =====

    function testSingleTokenDeposit() public {
        uint256 depositAmount = 100e18; // 100 AAVE

        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);

        vm.expectEmit(true, true, false, false);
        emit TokenDeposit(
            user1,
            address(aaveToken),
            depositAmount,
            depositAmount,
            block.timestamp
        );

        uint256 shares = vault.deposit(
            address(aaveToken),
            depositAmount,
            depositAmount
        );
        vm.stopPrank();

        assertEq(shares, depositAmount); // 1:1 ratio for first deposit

        // Check user position
        (uint256 userShares, uint256 value, uint256 apy) = vault
            .getUserPosition(user1, address(aaveToken));
        assertEq(userShares, depositAmount);
        assertEq(value, depositAmount);
        assertEq(apy, 800); // 8%

        // Check token stats
        (uint256 totalShares, uint256 totalValue, uint256 tokenAPY, ) = vault
            .getTokenStats(address(aaveToken));
        assertEq(totalShares, depositAmount);
        assertEq(totalValue, depositAmount);
        assertEq(tokenAPY, 800);
    }

    function testMultiTokenDeposit() public {
        uint256 aaveAmount = 50e18;
        uint256 usdcAmount = 1000e6;
        uint256 wethAmount = 2e18;

        vm.startPrank(user1);
        aaveToken.approve(address(vault), aaveAmount);
        usdcToken.approve(address(vault), usdcAmount);
        wethToken.approve(address(vault), wethAmount);

        uint256 aaveShares = vault.deposit(
            address(aaveToken),
            aaveAmount,
            aaveAmount
        );
        uint256 usdcShares = vault.deposit(
            address(usdcToken),
            usdcAmount,
            usdcAmount
        );
        uint256 wethShares = vault.deposit(
            address(wethToken),
            wethAmount,
            wethAmount
        );
        vm.stopPrank();

        assertEq(aaveShares, aaveAmount);
        assertEq(usdcShares, usdcAmount);
        assertEq(wethShares, wethAmount);

        // Check portfolio
        (
            address[] memory tokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols,
            uint256[] memory apys
        ) = vault.getUserPortfolio(user1);

        assertEq(tokens.length, 3);
        assertEq(shares.length, 3);
        assertEq(values.length, 3);
        assertEq(symbols.length, 3);
        assertEq(apys.length, 3);

        // Verify AAVE position
        assertEq(tokens[0], address(aaveToken));
        assertEq(shares[0], aaveAmount);
        assertEq(values[0], aaveAmount);
        assertEq(keccak256(bytes(symbols[0])), keccak256(bytes("AAVE")));
        assertEq(apys[0], 800);
    }

    function testDepositSlippageProtection() public {
        uint256 depositAmount = 100e18;
        uint256 minShares = 150e18; // More than expected

        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);

        vm.expectRevert("Insufficient shares received");
        vault.deposit(address(aaveToken), depositAmount, minShares);
        vm.stopPrank();
    }

    function testDepositMinimumAmount() public {
        uint256 tooSmall = 1e16; // 0.01 AAVE (below 0.1 minimum)

        vm.startPrank(user1);
        aaveToken.approve(address(vault), tooSmall);

        vm.expectRevert("Below minimum deposit");
        vault.deposit(address(aaveToken), tooSmall, tooSmall);
        vm.stopPrank();
    }

    function testDepositMaximumAmount() public {
        uint256 tooLarge = 20000e6; // 20k USDC (above 10k maximum)

        vm.startPrank(user1);
        usdcToken.approve(address(vault), tooLarge);

        vm.expectRevert("Exceeds maximum deposit");
        vault.deposit(address(usdcToken), tooLarge, tooLarge);
        vm.stopPrank();
    }

    // ===== WITHDRAWAL TESTS =====

    function testSingleTokenWithdraw() public {
        uint256 depositAmount = 100e18;

        // First deposit
        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(
            address(aaveToken),
            depositAmount,
            depositAmount
        );

        // Then withdraw half
        uint256 withdrawShares = shares / 2;

        vm.expectEmit(true, true, false, false);
        emit TokenWithdraw(
            user1,
            address(aaveToken),
            withdrawShares,
            withdrawShares,
            block.timestamp
        );

        uint256 amountReceived = vault.withdraw(
            address(aaveToken),
            withdrawShares,
            withdrawShares
        );
        vm.stopPrank();

        assertEq(amountReceived, withdrawShares);

        // Check remaining position
        (uint256 remainingShares, uint256 value, ) = vault.getUserPosition(
            user1,
            address(aaveToken)
        );
        assertEq(remainingShares, shares - withdrawShares);
        assertEq(value, shares - withdrawShares);
    }

    function testWithdrawAllPositions() public {
        uint256 aaveAmount = 50e18;
        uint256 usdcAmount = 1000e6;

        // Deposit to multiple tokens
        vm.startPrank(user1);
        aaveToken.approve(address(vault), aaveAmount);
        usdcToken.approve(address(vault), usdcAmount);

        uint256 aaveShares = vault.deposit(
            address(aaveToken),
            aaveAmount,
            aaveAmount
        );
        uint256 usdcShares = vault.deposit(
            address(usdcToken),
            usdcAmount,
            usdcAmount
        );

        // Withdraw all AAVE
        vault.withdraw(address(aaveToken), aaveShares, aaveShares);

        // Withdraw all USDC
        vault.withdraw(address(usdcToken), usdcShares, usdcShares);
        vm.stopPrank();

        // Check portfolio is empty
        (address[] memory tokens, uint256[] memory shares, , , ) = vault
            .getUserPortfolio(user1);

        assertEq(tokens.length, 0);
        assertEq(shares.length, 0);
    }

    function testWithdrawInsufficientShares() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);
        vault.deposit(address(aaveToken), depositAmount, depositAmount);

        vm.expectRevert("Insufficient shares");
        vault.withdraw(address(aaveToken), depositAmount + 1, 0);
        vm.stopPrank();
    }

    // ===== PREVIEW FUNCTIONS TESTS =====

    function testPreviewDeposit() public {
        uint256 amount = 100e18;

        uint256 expectedShares = vault.previewDeposit(
            address(aaveToken),
            amount
        );
        assertEq(expectedShares, amount); // 1:1 for first deposit

        // Actually deposit
        vm.startPrank(user1);
        aaveToken.approve(address(vault), amount);
        uint256 actualShares = vault.deposit(address(aaveToken), amount, 0);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function testPreviewWithdraw() public {
        uint256 depositAmount = 100e18;

        // First deposit
        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(
            address(aaveToken),
            depositAmount,
            depositAmount
        );
        vm.stopPrank();

        // Preview withdrawal
        uint256 expectedAmount = vault.previewWithdraw(
            address(aaveToken),
            shares
        );
        assertEq(expectedAmount, depositAmount); // 1:1 ratio
    }

    // ===== MULTI-USER TESTS =====

    function testMultiUserDeposits() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // User1 deposits
        vm.startPrank(user1);
        aaveToken.approve(address(vault), amount1);
        uint256 shares1 = vault.deposit(address(aaveToken), amount1, amount1);
        vm.stopPrank();

        // User2 deposits (should get same ratio)
        vm.startPrank(user2);
        aaveToken.approve(address(vault), amount2);
        uint256 shares2 = vault.deposit(address(aaveToken), amount2, amount2);
        vm.stopPrank();

        assertEq(shares1, amount1);
        assertEq(shares2, amount2);

        // Check individual positions
        (uint256 user1Shares, , ) = vault.getUserPosition(
            user1,
            address(aaveToken)
        );
        (uint256 user2Shares, , ) = vault.getUserPosition(
            user2,
            address(aaveToken)
        );

        assertEq(user1Shares, amount1);
        assertEq(user2Shares, amount2);

        // Check total stats
        (uint256 totalShares, uint256 totalValue, , ) = vault.getTokenStats(
            address(aaveToken)
        );
        assertEq(totalShares, amount1 + amount2);
        assertEq(totalValue, amount1 + amount2);
    }

    // ===== ADMIN FUNCTIONS TESTS =====

    function testAddToken() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit IAliothMultiAssetVault.TokenAdded(address(newToken), "NEW");

        vault.addToken(address(newToken), 1e18, 1000e18);
        vm.stopPrank();

        assertTrue(vault.isTokenSupported(address(newToken)));
        assertEq(vault.getSupportedTokenCount(), 4);

        (
            bool isSupported,
            uint256 totalShares,
            uint256 totalDeposits,
            uint256 totalWithdrawals,
            uint256 minDeposit,
            uint256 maxDeposit,
            string memory symbol
        ) = vault.tokenInfo(address(newToken));
        assertEq(minDeposit, 1e18);
        assertEq(maxDeposit, 1000e18);
        assertEq(keccak256(bytes(symbol)), keccak256(bytes("NEW")));
    }

    function testRemoveToken() public {
        // Can't remove token with active positions
        vm.startPrank(user1);
        aaveToken.approve(address(vault), 100e18);
        vault.deposit(address(aaveToken), 100e18, 100e18);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("Active positions exist");
        vault.removeToken(address(aaveToken));
        vm.stopPrank();

        // Withdraw all positions
        vm.startPrank(user1);
        vault.withdraw(address(aaveToken), 100e18, 100e18);
        vm.stopPrank();

        // Now can remove
        vm.startPrank(owner);
        vault.removeToken(address(aaveToken));
        vm.stopPrank();

        assertFalse(vault.isTokenSupported(address(aaveToken)));
        assertEq(vault.getSupportedTokenCount(), 2);
    }

    function testSetFees() public {
        vm.startPrank(owner);

        vault.setDepositFee(100); // 1%
        vault.setWithdrawalFee(50); // 0.5%

        assertEq(vault.depositFee(), 100);
        assertEq(vault.withdrawalFee(), 50);

        // Can't set fee too high
        vm.expectRevert("Fee too high");
        vault.setDepositFee(600); // 6% > 5% max

        vm.stopPrank();
    }

    function testFeeRecipient() public {
        vm.startPrank(owner);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        assertEq(vault.feeRecipient(), feeRecipient);
    }

    function testOnlyOwnerFunctions() public {
        vm.startPrank(user1);

        vm.expectRevert();
        vault.addToken(address(0), 0, 0);

        vm.expectRevert();
        vault.removeToken(address(aaveToken));

        vm.expectRevert();
        vault.setDepositFee(100);

        vm.expectRevert();
        vault.setWithdrawalFee(50);

        vm.expectRevert();
        vault.setFeeRecipient(feeRecipient);

        vm.stopPrank();
    }

    // ===== FEE FUNCTIONALITY TESTS =====

    function testDepositWithFees() public {
        uint256 depositFee = 100; // 1%
        uint256 depositAmount = 100e18;
        uint256 expectedFee = (depositAmount * depositFee) / 10000;
        uint256 expectedNetAmount = depositAmount - expectedFee;

        vm.startPrank(owner);
        vault.setDepositFee(depositFee);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        uint256 feeRecipientBalanceBefore = aaveToken.balanceOf(feeRecipient);

        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(address(aaveToken), depositAmount, 0);
        vm.stopPrank();

        uint256 feeRecipientBalanceAfter = aaveToken.balanceOf(feeRecipient);

        assertEq(shares, expectedNetAmount); // Shares based on net amount
        assertEq(
            feeRecipientBalanceAfter - feeRecipientBalanceBefore,
            expectedFee
        );
    }

    function testWithdrawWithFees() public {
        uint256 withdrawalFee = 50; // 0.5%
        uint256 depositAmount = 100e18;

        // First deposit without fees
        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(
            address(aaveToken),
            depositAmount,
            depositAmount
        );
        vm.stopPrank();

        // Set withdrawal fee
        vm.startPrank(owner);
        vault.setWithdrawalFee(withdrawalFee);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        uint256 feeRecipientBalanceBefore = aaveToken.balanceOf(feeRecipient);
        uint256 userBalanceBefore = aaveToken.balanceOf(user1);

        vm.startPrank(user1);
        uint256 amountReceived = vault.withdraw(address(aaveToken), shares, 0);
        vm.stopPrank();

        uint256 feeRecipientBalanceAfter = aaveToken.balanceOf(feeRecipient);
        uint256 userBalanceAfter = aaveToken.balanceOf(user1);

        uint256 expectedFee = (depositAmount * withdrawalFee) / 10000;
        uint256 expectedNetAmount = depositAmount - expectedFee;

        assertEq(amountReceived, expectedNetAmount);
        assertEq(userBalanceAfter - userBalanceBefore, expectedNetAmount);
        assertEq(
            feeRecipientBalanceAfter - feeRecipientBalanceBefore,
            expectedFee
        );
    }

    // ===== EDGE CASES AND ERROR HANDLING =====

    function testUnsupportedToken() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);

        vm.startPrank(user1);
        vm.expectRevert("Token not supported");
        vault.deposit(address(unsupportedToken), 100e18, 0);

        vm.expectRevert("Token not supported");
        vault.withdraw(address(unsupportedToken), 100e18, 0);

        vm.expectRevert("Token not supported");
        vault.previewDeposit(address(unsupportedToken), 100e18);

        vm.expectRevert("Token not supported");
        vault.previewWithdraw(address(unsupportedToken), 100e18);
        vm.stopPrank();
    }

    function testZeroAmountDeposit() public {
        vm.startPrank(user1);
        vm.expectRevert(); // ValidationLib should revert on zero amounts
        vault.deposit(address(aaveToken), 0, 0);
        vm.stopPrank();
    }

    function testEmptyPortfolio() public {
        (
            address[] memory tokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols,
            uint256[] memory apys
        ) = vault.getUserPortfolio(user1);

        assertEq(tokens.length, 0);
        assertEq(shares.length, 0);
        assertEq(values.length, 0);
        assertEq(symbols.length, 0);
        assertEq(apys.length, 0);
    }

    // ===== INTEGRATION TESTS =====

    function testCompleteUserJourney() public {
        uint256 aaveAmount = 100e18;
        uint256 usdcAmount = 5000e6;

        // 1. User deposits multiple tokens
        vm.startPrank(user1);
        aaveToken.approve(address(vault), aaveAmount);
        usdcToken.approve(address(vault), usdcAmount);

        vault.deposit(address(aaveToken), aaveAmount, aaveAmount);
        vault.deposit(address(usdcToken), usdcAmount, usdcAmount);
        vm.stopPrank();

        // 2. Check portfolio
        (
            address[] memory tokens,
            uint256[] memory shares,
            uint256[] memory values,
            string[] memory symbols,
            uint256[] memory apys
        ) = vault.getUserPortfolio(user1);

        assertEq(tokens.length, 2);
        assertEq(shares[0], aaveAmount);
        assertEq(shares[1], usdcAmount);

        // 3. Partial withdrawal
        vm.startPrank(user1);
        vault.withdraw(address(aaveToken), aaveAmount / 2, 0);
        vm.stopPrank();

        // 4. Check updated portfolio
        (tokens, shares, , , ) = vault.getUserPortfolio(user1);
        assertEq(tokens.length, 2); // Still 2 tokens
        assertEq(shares[0], aaveAmount / 2); // Half AAVE remaining
        assertEq(shares[1], usdcAmount); // Full USDC remaining

        // 5. Full exit
        vm.startPrank(user1);
        vault.withdraw(address(aaveToken), aaveAmount / 2, 0);
        vault.withdraw(address(usdcToken), usdcAmount, 0);
        vm.stopPrank();

        // 6. Portfolio should be empty
        (tokens, shares, , , ) = vault.getUserPortfolio(user1);
        assertEq(tokens.length, 0);
        assertEq(shares.length, 0);
    }

    // ===== GAS BENCHMARKING =====

    function testGasBenchmarks() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        aaveToken.approve(address(vault), depositAmount);

        // Benchmark deposit
        uint256 gasBefore = gasleft();
        vault.deposit(address(aaveToken), depositAmount, depositAmount);
        uint256 gasUsedDeposit = gasBefore - gasleft();

        // Benchmark getUserPosition
        gasBefore = gasleft();
        vault.getUserPosition(user1, address(aaveToken));
        uint256 gasUsedGetPosition = gasBefore - gasleft();

        // Benchmark getUserPortfolio
        gasBefore = gasleft();
        vault.getUserPortfolio(user1);
        uint256 gasUsedGetPortfolio = gasBefore - gasleft();

        // Benchmark withdraw
        gasBefore = gasleft();
        vault.withdraw(address(aaveToken), depositAmount, 0);
        uint256 gasUsedWithdraw = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for deposit:", gasUsedDeposit);
        console.log("Gas used for getUserPosition:", gasUsedGetPosition);
        console.log("Gas used for getUserPortfolio:", gasUsedGetPortfolio);
        console.log("Gas used for withdraw:", gasUsedWithdraw);

        // Basic gas sanity checks
        assertLt(gasUsedDeposit, 300000); // Should be under 300k gas
        assertLt(gasUsedGetPosition, 50000); // Should be under 50k gas
        assertLt(gasUsedGetPortfolio, 100000); // Should be under 100k gas
        assertLt(gasUsedWithdraw, 200000); // Should be under 200k gas
    }
}
