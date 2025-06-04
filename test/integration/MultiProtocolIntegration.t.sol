// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/core/YieldOptimizer.sol";
import "../../src/adapters/AaveAdapter.sol";
import "../../src/adapters/CompoundAdapter.sol";
import "../../src/adapters/YearnAdapter.sol";

contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000e18;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor() {
        balanceOf[msg.sender] = totalSupply;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Mock CCIP Messenger for testing
contract MockCCIPMessenger {
    function sendMessage(uint64, address, bytes calldata, uint256) external payable returns (bytes32) {
        return bytes32(uint256(1));
    }
}

// Simplified mock adapters for integration testing
contract MockProtocolAdapter is IProtocolAdapter {
    string public protocolName;
    uint256 public mockAPY;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public shares;
    
    constructor(string memory _name, uint256 _apy) {
        protocolName = _name;
        mockAPY = _apy;
    }
    
    function getAPY(address) external view returns (uint256) {
        return mockAPY;
    }
    
    function getTVL(address token) external view returns (uint256) {
        return shares[token];
    }
    
    function deposit(address token, uint256 amount, uint256) external returns (uint256) {
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
        shares[token] += amount;
        emit Deposited(token, amount, amount);
        return amount;
    }
    
    function withdraw(address token, uint256 amount, uint256) external returns (uint256) {
        require(shares[token] >= amount, "Insufficient shares");
        shares[token] -= amount;
        MockERC20(token).transfer(msg.sender, amount);
        emit Withdrawn(token, amount, amount);
        return amount;
    }
    
    function harvestYield(address token) external returns (uint256) {
        emit YieldHarvested(token, 0);
        return 0;
    }
    
    function supportsToken(address token) external view returns (bool) {
        return supportedTokens[token];
    }
    
    function getSharesBalance(address token) external view returns (uint256) {
        return shares[token];
    }
    
    function sharesToTokens(address, uint256 amount) external pure returns (uint256) {
        return amount;
    }
    
    function tokensToShares(address, uint256 amount) external pure returns (uint256) {
        return amount;
    }
    
    function addSupportedToken(address token) external {
        supportedTokens[token] = true;
    }
    
    function setAPY(uint256 _apy) external {
        mockAPY = _apy;
    }
}

contract MultiProtocolIntegrationTest is Test {
    YieldOptimizer public yieldOptimizer;
    MockCCIPMessenger public ccipMessenger;
    MockProtocolAdapter public aaveAdapter;
    MockProtocolAdapter public compoundAdapter;
    MockProtocolAdapter public yearnAdapter;
    MockERC20 public token;
    
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    event ProtocolAdded(address indexed adapter, uint256 weight);
    event FundsAllocated(address indexed token, uint256 totalAmount);
    event Rebalanced(address indexed token, uint256 newTotalAllocation);
    
    function setUp() public {
        // Deploy mock contracts
        token = new MockERC20();
        ccipMessenger = new MockCCIPMessenger();
        
        // Deploy YieldOptimizer
        yieldOptimizer = new YieldOptimizer(address(ccipMessenger), admin);
        
        // Deploy mock protocol adapters with different APYs
        aaveAdapter = new MockProtocolAdapter("Aave", 500);        // 5% APY
        compoundAdapter = new MockProtocolAdapter("Compound", 450); // 4.5% APY
        yearnAdapter = new MockProtocolAdapter("Yearn", 800);      // 8% APY
        
        // Setup token support for all adapters
        aaveAdapter.addSupportedToken(address(token));
        compoundAdapter.addSupportedToken(address(token));
        yearnAdapter.addSupportedToken(address(token));
        
        // Transfer tokens to users
        token.transfer(user1, 10000e18);
        token.transfer(user2, 10000e18);
        
        // Add protocols to yield optimizer
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 3000);      // 30%
        yieldOptimizer.addProtocol(address(compoundAdapter), 3000);   // 30% 
        yieldOptimizer.addProtocol(address(yearnAdapter), 4000);     // 40%
        vm.stopPrank();
    }
    
    function testMultiProtocolDeposit() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        
        uint256 sharesBefore = yieldOptimizer.balanceOf(user1, address(token));
        uint256 shares = yieldOptimizer.deposit(address(token), depositAmount, 0);
        uint256 sharesAfter = yieldOptimizer.balanceOf(user1, address(token));
        
        vm.stopPrank();
        
        // Verify shares received
        assertEq(shares, depositAmount);
        assertEq(sharesAfter - sharesBefore, shares);
        
        // Verify allocation across protocols (approximately)
        uint256 aaveBalance = aaveAdapter.getSharesBalance(address(token));
        uint256 compoundBalance = compoundAdapter.getSharesBalance(address(token));
        uint256 yearnBalance = yearnAdapter.getSharesBalance(address(token));
        
        // Check allocations are roughly in proportion to weights
        assertApproxEqRel(aaveBalance, depositAmount * 3000 / 10000, 0.1e18);      // 30% ±10%
        assertApproxEqRel(compoundBalance, depositAmount * 3000 / 10000, 0.1e18);   // 30% ±10%
        assertApproxEqRel(yearnBalance, depositAmount * 4000 / 10000, 0.1e18);     // 40% ±10%
        
        console.log("Aave allocation:", aaveBalance);
        console.log("Compound allocation:", compoundBalance);
        console.log("Yearn allocation:", yearnBalance);
    }
    
    function testOptimalAllocationBasedOnAPY() public {
        // Update APYs to create clear optimal allocation
        aaveAdapter.setAPY(300);        // 3%
        compoundAdapter.setAPY(600);    // 6%
        yearnAdapter.setAPY(900);       // 9%
        
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        vm.stopPrank();
        
        // Yearn should get the highest allocation due to highest APY
        uint256 yearnBalance = yearnAdapter.getSharesBalance(address(token));
        uint256 compoundBalance = compoundAdapter.getSharesBalance(address(token));
        uint256 aaveBalance = aaveAdapter.getSharesBalance(address(token));
        
        // Verify Yearn gets the most allocation
        assertGt(yearnBalance, compoundBalance);
        assertGt(yearnBalance, aaveBalance);
        assertGt(compoundBalance, aaveBalance);
        
        console.log("APY-based allocation - Yearn:", yearnBalance, "Compound:", compoundBalance, "Aave:", aaveBalance);
    }
    
    function testMultiUserDeposits() public {
        uint256 depositAmount1 = 500e18;
        uint256 depositAmount2 = 1500e18;
        
        // User 1 deposits
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount1);
        uint256 shares1 = yieldOptimizer.deposit(address(token), depositAmount1, 0);
        vm.stopPrank();
        
        // User 2 deposits
        vm.startPrank(user2);
        token.approve(address(yieldOptimizer), depositAmount2);
        uint256 shares2 = yieldOptimizer.deposit(address(token), depositAmount2, 0);
        vm.stopPrank();
        
        // Verify individual balances
        assertEq(yieldOptimizer.balanceOf(user1, address(token)), shares1);
        assertEq(yieldOptimizer.balanceOf(user2, address(token)), shares2);
        
        // Verify total allocation
        uint256 totalDeposited = depositAmount1 + depositAmount2;
        uint256 totalAllocated = aaveAdapter.getSharesBalance(address(token)) +
                                compoundAdapter.getSharesBalance(address(token)) +
                                yearnAdapter.getSharesBalance(address(token));
        
        assertEq(totalAllocated, totalDeposited);
        
        console.log("Multi-user total allocated:", totalAllocated);
    }
    
    function testWithdrawalFromMultipleProtocols() public {
        uint256 depositAmount = 1000e18;
        
        // Deposit first
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        uint256 shares = yieldOptimizer.deposit(address(token), depositAmount, 0);
        
        // Withdraw half
        uint256 withdrawShares = shares / 2;
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 amountWithdrawn = yieldOptimizer.withdraw(address(token), withdrawShares, 0);
        uint256 balanceAfter = token.balanceOf(user1);
        
        vm.stopPrank();
        
        // Verify withdrawal
        assertEq(balanceAfter - balanceBefore, amountWithdrawn);
        assertEq(yieldOptimizer.balanceOf(user1, address(token)), shares - withdrawShares);
        
        // Verify protocols still have remaining funds
        uint256 totalRemaining = aaveAdapter.getSharesBalance(address(token)) +
                                 compoundAdapter.getSharesBalance(address(token)) +
                                 yearnAdapter.getSharesBalance(address(token));
        
        assertApproxEqRel(totalRemaining, depositAmount - amountWithdrawn, 0.01e18); // 1% tolerance
        
        console.log("Withdrawal amount:", amountWithdrawn);
        console.log("Remaining in protocols:", totalRemaining);
    }
    
    function testRebalancingBetweenProtocols() public {
        uint256 depositAmount = 1000e18;
        
        // Initial deposit
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        vm.stopPrank();
        
        // Record initial allocations
        uint256 initialAave = aaveAdapter.getSharesBalance(address(token));
        uint256 initialCompound = compoundAdapter.getSharesBalance(address(token));
        uint256 initialYearn = yearnAdapter.getSharesBalance(address(token));
        
        // Change APYs to trigger rebalancing
        aaveAdapter.setAPY(1000);       // 10% - now highest
        compoundAdapter.setAPY(400);    // 4%
        yearnAdapter.setAPY(300);       // 3%
        
        // Execute rebalancing
        vm.startPrank(admin);
        IYieldOptimizer.RebalanceParams memory params = IYieldOptimizer.RebalanceParams({
            token: address(token),
            newAllocations: new IYieldOptimizer.AllocationTarget[](3),
            maxSlippage: 500, // 5%
            deadline: block.timestamp + 1 hours
        });
        
        // Define new allocations favoring Aave (highest APY)
        params.newAllocations[0] = IYieldOptimizer.AllocationTarget({
            protocolAdapter: address(aaveAdapter),
            targetPercentage: 6000, // 60%
            currentAllocation: 600e18,
            currentAPY: 1000
        });
        
        params.newAllocations[1] = IYieldOptimizer.AllocationTarget({
            protocolAdapter: address(compoundAdapter),
            targetPercentage: 2000, // 20%
            currentAllocation: 200e18,
            currentAPY: 400
        });
        
        params.newAllocations[2] = IYieldOptimizer.AllocationTarget({
            protocolAdapter: address(yearnAdapter),
            targetPercentage: 2000, // 20%
            currentAllocation: 200e18,
            currentAPY: 300
        });
        
        yieldOptimizer.executeRebalance(params);
        vm.stopPrank();
        
        // Verify rebalancing occurred
        uint256 newAave = aaveAdapter.getSharesBalance(address(token));
        uint256 newCompound = compoundAdapter.getSharesBalance(address(token));
        uint256 newYearn = yearnAdapter.getSharesBalance(address(token));
        
        // Aave should have more allocation now
        assertGt(newAave, initialAave);
        console.log("Rebalancing - New Aave allocation:", newAave, "vs initial:", initialAave);
        
        // Verify total is preserved
        uint256 totalAfterRebalance = newAave + newCompound + newYearn;
        assertApproxEqRel(totalAfterRebalance, depositAmount, 0.01e18);
    }
    
    function testYieldHarvesting() public {
        uint256 depositAmount = 1000e18;
        
        // Deposit funds
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        vm.stopPrank();
        
        // Harvest yield from all protocols
        vm.startPrank(admin);
        uint256 totalYield = yieldOptimizer.harvestAllYield(address(token));
        vm.stopPrank();
        
        // In our mock, yield is 0, but verify the call succeeded
        assertEq(totalYield, 0);
        
        console.log("Total yield harvested:", totalYield);
    }
    
    function testProtocolFailureHandling() public {
        uint256 depositAmount = 1000e18;
        
        // Deposit funds
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        vm.stopPrank();
        
        // Remove one protocol (simulating failure)
        vm.startPrank(admin);
        yieldOptimizer.removeProtocol(address(compoundAdapter));
        vm.stopPrank();
        
        // Verify remaining protocols still work
        vm.startPrank(user2);
        token.approve(address(yieldOptimizer), 500e18);
        uint256 shares = yieldOptimizer.deposit(address(token), 500e18, 0);
        vm.stopPrank();
        
        assertGt(shares, 0);
        
        // Verify funds only go to remaining protocols
        uint256 compoundBalance = compoundAdapter.getSharesBalance(address(token));
        // Compound should still have old balance (no new allocations)
        console.log("Compound balance after removal:", compoundBalance);
    }
    
    function testGasEfficiencyMultiProtocol() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        
        uint256 gasBefore = gasleft();
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        uint256 gasUsed = gasBefore - gasleft();
        
        vm.stopPrank();
        
        // Should use less than 500k gas for multi-protocol deposit
        assertLt(gasUsed, 500000);
        
        console.log("Multi-protocol deposit gas usage:", gasUsed);
    }
    
    function testEmergencyWithdrawAcrossProtocols() public {
        uint256 depositAmount = 1000e18;
        
        // Deposit funds
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        vm.stopPrank();
        
        // Emergency withdraw from all protocols
        vm.startPrank(admin);
        yieldOptimizer.emergencyWithdraw(address(token));
        vm.stopPrank();
        
        // Verify all funds are withdrawn from protocols
        assertEq(aaveAdapter.getSharesBalance(address(token)), 0);
        assertEq(compoundAdapter.getSharesBalance(address(token)), 0);
        assertEq(yearnAdapter.getSharesBalance(address(token)), 0);
        
        // Funds should be in the yield optimizer contract
        assertGt(token.balanceOf(address(yieldOptimizer)), 0);
    }
    
    function testMaximumProtocolLimit() public {
        // Test that we can handle the maximum number of protocols
        // Current limit should be reasonable for gas efficiency
        
        uint256 protocolCount = yieldOptimizer.getActiveProtocolCount();
        assertEq(protocolCount, 3);
        
        console.log("Active protocol count:", protocolCount);
    }
} 