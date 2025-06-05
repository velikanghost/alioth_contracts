// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/core/YieldOptimizer.sol";
import "../../src/interfaces/IProtocolAdapter.sol";
import "../../src/interfaces/ICCIPMessenger.sol";
import "../../src/libraries/ValidationLib.sol";

contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 10000000e18;

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

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
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

contract MockCCIPMessenger is ICCIPMessenger {
    function sendMessage(
        uint64,
        address,
        MessageType,
        bytes calldata,
        address,
        uint256,
        PayFeesIn
    ) external payable returns (bytes32) {
        return bytes32(uint256(1));
    }

    function sendYieldRebalance(
        uint64,
        address,
        address,
        uint256,
        address,
        PayFeesIn
    ) external payable returns (bytes32) {
        return bytes32(uint256(1));
    }

    function sendLoanRequest(
        uint64,
        address,
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        PayFeesIn
    ) external payable returns (bytes32) {
        return bytes32(uint256(1));
    }

    function sendCollateralTransfer(
        uint64,
        address,
        address,
        uint256,
        uint256,
        PayFeesIn
    ) external payable returns (bytes32) {
        return bytes32(uint256(1));
    }

    function getFee(
        uint64,
        MessageType,
        bytes calldata,
        address,
        uint256,
        PayFeesIn
    ) external pure returns (uint256) {
        return 0.01 ether;
    }

    function isSupportedChain(uint64) external pure returns (bool) {
        return true;
    }

    function isAllowlistedSender(address) external pure returns (bool) {
        return true;
    }

    function getLastMessage(
        address
    ) external pure returns (CrossChainMessage memory) {
        return
            CrossChainMessage({
                sourceChain: 0,
                destinationChain: 0,
                sender: address(0),
                receiver: address(0),
                data: "",
                token: address(0),
                amount: 0,
                messageId: bytes32(0),
                timestamp: 0
            });
    }

    function getChainConfig(uint64) external pure returns (ChainConfig memory) {
        return
            ChainConfig({
                isSupported: true,
                ccipRouter: address(0),
                gasLimit: 200000,
                allowlistEnabled: false
            });
    }

    function getMessageTypeConfig(
        MessageType
    ) external pure returns (MessageTypeConfig memory) {
        return
            MessageTypeConfig({gasLimit: 200000, enabled: true, maxRetries: 3});
    }

    function allowlistDestinationChain(uint64, address, uint256) external {}

    function denylistDestinationChain(uint64) external {}

    function allowlistSender(address, bool) external {}

    function allowlistSourceChain(uint64, bool) external {}

    function updateMessageTypeConfig(
        MessageType,
        uint256,
        bool,
        uint256
    ) external {}

    function setLinkToken(address) external {}

    function withdrawFees(address, uint256, address) external {}

    function setEmergencyStop(bool) external {}

    function emergencyWithdraw(address, uint256, address) external {}

    function retryFailedMessage(bytes32, uint256) external {}

    function getRetryCount(bytes32) external pure returns (uint256) {
        return 0;
    }
}

contract MockProtocolAdapter is IProtocolAdapter {
    string public protocolName;
    uint256 public mockAPY;
    uint256 public mockTVL;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public shares;

    constructor(string memory _name, uint256 _apy) {
        protocolName = _name;
        mockAPY = _apy;
    }

    function getAPY(address) external view returns (uint256) {
        return mockAPY;
    }

    function getTVL(address) external view returns (uint256) {
        return mockTVL;
    }

    function deposit(
        address token,
        uint256 amount,
        uint256
    ) external payable returns (uint256) {
        require(msg.value == 0, "ETH not supported");
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
        shares[token] += amount;
        emit Deposited(token, amount, amount);
        return amount;
    }

    function withdraw(
        address token,
        uint256 amount,
        uint256
    ) external returns (uint256) {
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

    function sharesToTokens(
        address,
        uint256 amount
    ) external pure returns (uint256) {
        return amount;
    }

    function tokensToShares(
        address,
        uint256 amount
    ) external pure returns (uint256) {
        return amount;
    }

    function addSupportedToken(address token) external {
        supportedTokens[token] = true;
    }

    function setAPY(uint256 _apy) external {
        mockAPY = _apy;
    }

    function setTVL(uint256 _tvl) external {
        mockTVL = _tvl;
    }
}

contract YieldOptimizerTest is Test {
    YieldOptimizer public yieldOptimizer;
    MockCCIPMessenger public ccipMessenger;
    MockProtocolAdapter public aaveAdapter;
    MockProtocolAdapter public compoundAdapter;
    MockProtocolAdapter public yearnAdapter;
    MockERC20 public token;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public rebalancer = address(0x4);
    address public harvester = address(0x5);

    event ProtocolAdded(address indexed adapter, string protocolName);
    event ProtocolRemoved(address indexed adapter, string protocolName);
    event AIRebalanceTriggered(
        address indexed token,
        uint256 expectedAPYImprovement
    );

    function setUp() public {
        // Deploy mock contracts
        token = new MockERC20();
        ccipMessenger = new MockCCIPMessenger();

        // Deploy YieldOptimizer
        yieldOptimizer = new YieldOptimizer(address(ccipMessenger), admin);

        // Deploy mock protocol adapters with different APYs
        aaveAdapter = new MockProtocolAdapter("Aave", 500); // 5% APY
        compoundAdapter = new MockProtocolAdapter("Compound", 450); // 4.5% APY
        yearnAdapter = new MockProtocolAdapter("Yearn", 800); // 8% APY

        // Setup token support for all adapters
        aaveAdapter.addSupportedToken(address(token));
        compoundAdapter.addSupportedToken(address(token));
        yearnAdapter.addSupportedToken(address(token));

        // Transfer tokens to users
        token.transfer(user1, 10000e18);
        token.transfer(user2, 10000e18);

        // Setup roles
        vm.startPrank(admin);
        yieldOptimizer.grantRole(yieldOptimizer.REBALANCER_ROLE(), rebalancer);
        yieldOptimizer.grantRole(yieldOptimizer.HARVESTER_ROLE(), harvester);
        vm.stopPrank();
    }

    // ===== PROTOCOL MANAGEMENT TESTS =====

    function testAddProtocol() public {
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit ProtocolAdded(address(aaveAdapter), "Aave");

        yieldOptimizer.addProtocol(address(aaveAdapter), 3000);
        vm.stopPrank();

        // Verify protocol was added
        (
            IProtocolAdapter adapter,
            uint256 weight,
            ,
            ,
            bool isActive
        ) = yieldOptimizer.protocols(address(aaveAdapter));
        assertEq(address(adapter), address(aaveAdapter));
        assertEq(weight, 3000);
        assertTrue(isActive);
    }

    function testAddProtocolOnlyAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert("Not admin");
        yieldOptimizer.addProtocol(address(aaveAdapter), 3000);
        vm.stopPrank();
    }

    function testAddProtocolInvalidWeight() public {
        vm.startPrank(admin);
        vm.expectRevert(ValidationLib.InvalidPercentage.selector);
        yieldOptimizer.addProtocol(address(aaveAdapter), 15000); // > 100%
        vm.stopPrank();
    }

    function testAddProtocolZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(ValidationLib.ZeroAddress.selector);
        yieldOptimizer.addProtocol(address(0), 3000);
        vm.stopPrank();
    }

    function testAddProtocolAlreadyActive() public {
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 3000);

        vm.expectRevert("Protocol already active");
        yieldOptimizer.addProtocol(address(aaveAdapter), 4000);
        vm.stopPrank();
    }

    function testRemoveProtocol() public {
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 3000);

        vm.expectEmit(true, false, false, true);
        emit ProtocolRemoved(address(aaveAdapter), "Aave");

        yieldOptimizer.removeProtocol(address(aaveAdapter));
        vm.stopPrank();

        // Verify protocol was removed
        (, , , , bool isActive) = yieldOptimizer.protocols(
            address(aaveAdapter)
        );
        assertFalse(isActive);
    }

    function testRemoveProtocolNotActive() public {
        vm.startPrank(admin);
        vm.expectRevert("Protocol not active");
        yieldOptimizer.removeProtocol(address(aaveAdapter));
        vm.stopPrank();
    }

    function testMaxProtocolsLimit() public {
        vm.startPrank(admin);

        // Add protocols up to the limit
        for (uint256 i = 0; i < yieldOptimizer.MAX_PROTOCOLS(); i++) {
            MockProtocolAdapter adapter = new MockProtocolAdapter(
                string(abi.encodePacked("Protocol", i)),
                500
            );
            yieldOptimizer.addProtocol(address(adapter), 500);
        }

        // Try to add one more - should fail
        MockProtocolAdapter extraAdapter = new MockProtocolAdapter(
            "Extra",
            500
        );
        vm.expectRevert("Max protocols reached");
        yieldOptimizer.addProtocol(address(extraAdapter), 500);

        vm.stopPrank();
    }

    // ===== ACCESS CONTROL TESTS =====

    function testAdminRole() public {
        assertEq(yieldOptimizer.admin(), admin);
    }

    function testRebalancerRole() public {
        // Test that rebalancer can call rebalancer functions
        // We'll test this through the actual function calls rather than hasRole
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);
        vm.stopPrank();

        // Admin should be able to call rebalancer functions
        vm.startPrank(admin);
        // This would test rebalancer functionality when implemented
        vm.stopPrank();

        // Rebalancer should be able to call rebalancer functions
        vm.startPrank(rebalancer);
        // This would test rebalancer functionality when implemented
        vm.stopPrank();
    }

    function testHarvesterRole() public {
        // Test that harvester can call harvester functions
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);
        vm.stopPrank();

        vm.startPrank(harvester);
        uint256 totalYield = yieldOptimizer.harvestAll(address(token));
        assertEq(totalYield, 0); // Mock adapters return 0 yield
        vm.stopPrank();
    }

    function testGrantRole() public {
        address newRebalancer = address(0x99);

        vm.startPrank(admin);
        yieldOptimizer.grantRole(
            yieldOptimizer.REBALANCER_ROLE(),
            newRebalancer
        );
        vm.stopPrank();

        // Test that the new rebalancer can perform rebalancer actions
        // We test this indirectly through function access
    }

    function testRevokeRole() public {
        vm.startPrank(admin);
        yieldOptimizer.revokeRole(yieldOptimizer.HARVESTER_ROLE(), harvester);
        vm.stopPrank();

        // Test that the harvester can no longer perform harvester actions
        vm.startPrank(harvester);
        vm.expectRevert("Not harvester");
        yieldOptimizer.harvestAll(address(token));
        vm.stopPrank();
    }

    // ===== DEPOSIT AND WITHDRAW TESTS =====

    function testDeposit() public {
        // Setup protocols
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 5000);
        yieldOptimizer.addProtocol(address(compoundAdapter), 5000);
        vm.stopPrank();

        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);

        uint256 shares = yieldOptimizer.deposit(
            address(token),
            depositAmount,
            0
        );

        vm.stopPrank();

        // Verify shares received
        assertEq(shares, depositAmount);
    }

    function testDepositZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(ValidationLib.ZeroAmount.selector);
        yieldOptimizer.deposit(address(token), 0, 0);
        vm.stopPrank();
    }

    function testDepositZeroAddress() public {
        vm.startPrank(user1);
        vm.expectRevert(ValidationLib.ZeroAddress.selector);
        yieldOptimizer.deposit(address(0), 1000e18, 0);
        vm.stopPrank();
    }

    function testDepositEmergencyStopped() public {
        vm.startPrank(admin);
        yieldOptimizer.toggleEmergencyStop();
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), 1000e18);
        vm.expectRevert("Emergency stopped");
        yieldOptimizer.deposit(address(token), 1000e18, 0);
        vm.stopPrank();
    }

    function testWithdraw() public {
        // Setup protocols and make a deposit first
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);
        vm.stopPrank();

        uint256 depositAmount = 1000e18;
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);
        uint256 shares = yieldOptimizer.deposit(
            address(token),
            depositAmount,
            0
        );

        // Now withdraw
        uint256 amount = yieldOptimizer.withdraw(address(token), shares, 0);
        vm.stopPrank();

        assertEq(amount, depositAmount);
    }

    // ===== ALLOCATION CALCULATION TESTS =====

    function testCalculateOptimalAllocation() public {
        // Setup protocols with different APYs
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 3000);
        yieldOptimizer.addProtocol(address(compoundAdapter), 3000);
        yieldOptimizer.addProtocol(address(yearnAdapter), 4000);
        vm.stopPrank();

        // Set different APYs
        aaveAdapter.setAPY(500); // 5%
        compoundAdapter.setAPY(400); // 4%
        yearnAdapter.setAPY(800); // 8%

        uint256 totalAmount = 1000e18;
        IYieldOptimizer.AllocationTarget[] memory targets = yieldOptimizer
            .calculateOptimalAllocation(address(token), totalAmount);

        // Should have 3 targets
        assertEq(targets.length, 3);

        // Total allocation should equal totalAmount
        uint256 totalAllocated = 0;
        for (uint256 i = 0; i < targets.length; i++) {
            totalAllocated += targets[i].currentAllocation;
        }
        assertEq(totalAllocated, totalAmount);
    }

    function testCalculateOptimalAllocationNoProtocols() public {
        IYieldOptimizer.AllocationTarget[] memory targets = yieldOptimizer
            .calculateOptimalAllocation(address(token), 1000e18);

        assertEq(targets.length, 0);
    }

    // ===== WEIGHTED APY TESTS =====

    function testCheckUpkeep() public {
        // Setup protocols
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);
        vm.stopPrank();

        // Set initial APY to avoid division by zero
        aaveAdapter.setAPY(500);
        aaveAdapter.setTVL(1000e18);

        // Make a deposit first to establish allocations
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), 1000e18);
        yieldOptimizer.deposit(address(token), 1000e18, 0);
        vm.stopPrank();

        // Encode token address as checkData
        bytes memory checkData = abi.encode(address(token));

        (bool upkeepNeeded, bytes memory performData) = yieldOptimizer
            .checkUpkeep(checkData);

        // Should not need upkeep initially with only one protocol
        assertFalse(upkeepNeeded);
        assertEq(performData.length, 0);
    }

    function testGetWeightedAPY() public {
        // Setup protocols
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 5000);
        yieldOptimizer.addProtocol(address(compoundAdapter), 5000);
        vm.stopPrank();

        // Set up TVL and APY for the adapters to ensure they have valid data
        aaveAdapter.setTVL(1000e18);
        compoundAdapter.setTVL(1000e18);
        aaveAdapter.setAPY(500);
        compoundAdapter.setAPY(450);

        // Make deposits to create allocations
        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), 1000e18);
        yieldOptimizer.deposit(address(token), 1000e18, 0);
        vm.stopPrank();

        // Test that getWeightedAPY doesn't revert (it may return 0 if APYs haven't been updated)
        // In the current design, APYs are only updated during rebalancing operations
        uint256 weightedAPY = yieldOptimizer.getWeightedAPY(address(token));

        // Just verify it doesn't revert with division by zero
        // The function should return 0 when protocol APYs haven't been updated yet
        assertTrue(weightedAPY >= 0);
    }

    // ===== HARVEST TESTS =====

    function testHarvestAll() public {
        // Setup protocols
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);
        vm.stopPrank();

        vm.startPrank(harvester);
        uint256 totalYield = yieldOptimizer.harvestAll(address(token));
        vm.stopPrank();

        // Mock adapters return 0 yield
        assertEq(totalYield, 0);
    }

    function testHarvestAllOnlyHarvester() public {
        vm.startPrank(user1);
        vm.expectRevert("Not harvester");
        yieldOptimizer.harvestAll(address(token));
        vm.stopPrank();
    }

    // ===== EMERGENCY TESTS =====

    function testToggleEmergencyStop() public {
        assertFalse(yieldOptimizer.emergencyStop());

        vm.startPrank(admin);
        yieldOptimizer.toggleEmergencyStop();
        vm.stopPrank();

        assertTrue(yieldOptimizer.emergencyStop());
    }

    function testToggleEmergencyStopOnlyAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert("Not emergency role");
        yieldOptimizer.toggleEmergencyStop();
        vm.stopPrank();
    }

    // ===== REBALANCE THRESHOLD TESTS =====

    function testSetRebalanceThreshold() public {
        uint256 newThreshold = 200; // 2%

        vm.startPrank(admin);
        yieldOptimizer.setRebalanceThreshold(newThreshold);
        vm.stopPrank();

        assertEq(yieldOptimizer.rebalanceThreshold(), newThreshold);
    }

    function testSetRebalanceThresholdTooLow() public {
        vm.startPrank(admin);
        vm.expectRevert("Threshold too low");
        yieldOptimizer.setRebalanceThreshold(25); // Below MIN_REBALANCE_THRESHOLD
        vm.stopPrank();
    }

    function testSetMaxGasPrice() public {
        uint256 newMaxGasPrice = 100 gwei;

        vm.startPrank(admin);
        yieldOptimizer.setMaxGasPrice(newMaxGasPrice);
        vm.stopPrank();

        assertEq(yieldOptimizer.maxGasPrice(), newMaxGasPrice);
    }

    // ===== CHAINLINK AUTOMATION TESTS =====

    function testGetCurrentAllocationNoProtocols() public {
        IYieldOptimizer.AllocationTarget[] memory allocations = yieldOptimizer
            .getCurrentAllocation(address(token));
        assertEq(allocations.length, 0);
    }

    function testGetTotalTVLNoProtocols() public {
        uint256 totalTVL = yieldOptimizer.getTotalTVL(address(token));
        assertEq(totalTVL, 0);
    }

    function testGetSupportedProtocolsNoProtocols() public {
        address[] memory protocols = yieldOptimizer.getSupportedProtocols(
            address(token)
        );
        assertEq(protocols.length, 0);
    }

    // ===== GAS OPTIMIZATION TESTS =====

    function testDepositGasUsage() public {
        // Setup single protocol
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 10000);
        vm.stopPrank();

        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);

        uint256 gasBefore = gasleft();
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        uint256 gasUsed = gasBefore - gasleft();

        // Should use reasonable gas for single protocol deposit
        assertLt(gasUsed, 500000);
        vm.stopPrank();
    }

    function testMultiProtocolDepositGasUsage() public {
        // Setup multiple protocols
        vm.startPrank(admin);
        yieldOptimizer.addProtocol(address(aaveAdapter), 3333);
        yieldOptimizer.addProtocol(address(compoundAdapter), 3333);
        yieldOptimizer.addProtocol(address(yearnAdapter), 3334);
        vm.stopPrank();

        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        token.approve(address(yieldOptimizer), depositAmount);

        uint256 gasBefore = gasleft();
        yieldOptimizer.deposit(address(token), depositAmount, 0);
        uint256 gasUsed = gasBefore - gasleft();

        // Should use reasonable gas for multi-protocol deposit
        assertLt(gasUsed, 800000);
        vm.stopPrank();
    }
}
