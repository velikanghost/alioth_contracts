// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/CCIPMessenger.sol";
import "../src/interfaces/ICCIPMessenger.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

// Mock contracts for testing
contract MockRouter is IRouterClient {
    uint256 public constant MOCK_FEE = 0.01 ether;

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getSupportedTokens(
        uint64
    ) external pure returns (address[] memory) {
        return new address[](0);
    }

    function getFee(
        uint64,
        Client.EVM2AnyMessage memory
    ) external pure returns (uint256) {
        return MOCK_FEE;
    }

    function ccipSend(
        uint64,
        Client.EVM2AnyMessage memory
    ) external payable returns (bytes32) {
        return keccak256(abi.encode(block.timestamp, msg.sender));
    }
}

contract MockLinkToken is LinkTokenInterface {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    string private _name = "ChainLink Token";
    string private _symbol = "LINK";
    uint8 private _decimals = 18;
    uint256 private _totalSupply = 1000000 * 10 ** 18;

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balances[msg.sender] >= value, "Insufficient balance");
        balances[msg.sender] -= value;
        balances[to] += value;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        require(balances[from] >= value, "Insufficient balance");
        require(
            allowances[from][msg.sender] >= value,
            "Insufficient allowance"
        );
        balances[from] -= value;
        balances[to] += value;
        allowances[from][msg.sender] -= value;
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowances[msg.sender][spender] = value;
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function increaseApproval(address spender, uint256 addedValue) external {
        allowances[msg.sender][spender] += addedValue;
    }

    function decreaseApproval(
        address spender,
        uint256 subtractedValue
    ) external returns (bool) {
        if (subtractedValue > allowances[msg.sender][spender]) {
            allowances[msg.sender][spender] = 0;
        } else {
            allowances[msg.sender][spender] -= subtractedValue;
        }
        return true;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        _totalSupply += amount;
    }

    // LINK-specific functions
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool) {
        require(balances[msg.sender] >= value, "Insufficient balance");
        balances[msg.sender] -= value;
        balances[to] += value;
        return true;
    }
}

contract CCIPMessengerTest is Test {
    CCIPMessenger public ccipMessenger;
    MockRouter public mockRouter;
    MockLinkToken public mockLinkToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public admin = makeAddr("admin");
    address public feeCollector = makeAddr("feeCollector");

    uint64 public constant ETHEREUM_CHAIN_SELECTOR = 5009297550715157269;
    uint64 public constant POLYGON_CHAIN_SELECTOR = 4051577828743386545;

    function setUp() public {
        // Deploy mock contracts
        mockRouter = new MockRouter();
        mockLinkToken = new MockLinkToken();

        // Deploy CCIPMessenger
        vm.prank(admin);
        ccipMessenger = new CCIPMessenger(
            address(mockRouter),
            address(mockLinkToken),
            feeCollector
        );

        // Setup allowlisting
        vm.startPrank(admin);
        ccipMessenger.allowlistDestinationChain(
            POLYGON_CHAIN_SELECTOR,
            address(mockRouter),
            500000
        );
        ccipMessenger.allowlistSourceChain(POLYGON_CHAIN_SELECTOR, true);
        ccipMessenger.allowlistSender(alice, true);
        vm.stopPrank();

        // Fund accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(address(ccipMessenger), 5 ether);

        // Mint LINK tokens
        mockLinkToken.mint(alice, 1000 ether);
        mockLinkToken.mint(bob, 1000 ether);
    }

    function testBasicFunctionality() public {
        // Test that the contract is properly initialized
        assertTrue(ccipMessenger.isSupportedChain(POLYGON_CHAIN_SELECTOR));
        assertTrue(ccipMessenger.isAllowlistedSender(alice));
        assertFalse(ccipMessenger.isAllowlistedSender(bob));
    }

    function testAllowlisting() public {
        // Test chain allowlisting
        vm.prank(admin);
        ccipMessenger.allowlistDestinationChain(
            12345,
            address(mockRouter),
            300000
        );
        assertTrue(ccipMessenger.isSupportedChain(12345));

        // Test denylisting
        vm.prank(admin);
        ccipMessenger.denylistDestinationChain(12345);
        assertFalse(ccipMessenger.isSupportedChain(12345));

        // Test sender allowlisting
        vm.prank(admin);
        ccipMessenger.allowlistSender(bob, true);
        assertTrue(ccipMessenger.isAllowlistedSender(bob));

        vm.prank(admin);
        ccipMessenger.allowlistSender(bob, false);
        assertFalse(ccipMessenger.isAllowlistedSender(bob));
    }

    function testMessageTypeConfiguration() public {
        // Test updating message type config
        vm.prank(admin);
        ccipMessenger.updateMessageTypeConfig(
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            600000,
            true,
            5
        );

        ICCIPMessenger.MessageTypeConfig memory config = ccipMessenger
            .getMessageTypeConfig(ICCIPMessenger.MessageType.YIELD_REBALANCE);

        assertEq(config.gasLimit, 600000);
        assertTrue(config.enabled);
        assertEq(config.maxRetries, 5);
    }

    function testGetFee() public {
        bytes memory data = abi.encode("test message");

        uint256 fee = ccipMessenger.getFee(
            POLYGON_CHAIN_SELECTOR,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );

        // Fee should be greater than 0 (mock fee + platform fee)
        assertGt(fee, mockRouter.MOCK_FEE());
    }

    function testSendMessageWithNativeFees() public {
        bytes memory data = abi.encode("test message");

        uint256 fee = ccipMessenger.getFee(
            POLYGON_CHAIN_SELECTOR,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );

        vm.prank(alice);
        bytes32 messageId = ccipMessenger.sendMessage{value: fee}(
            POLYGON_CHAIN_SELECTOR,
            bob,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );

        // Should return a valid message ID
        assertTrue(messageId != bytes32(0));
    }

    function testSendYieldRebalance() public {
        uint256 fee = ccipMessenger.getFee(
            POLYGON_CHAIN_SELECTOR,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            abi.encode(address(0x123), 1000, address(0x456)),
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );

        vm.prank(alice);
        bytes32 messageId = ccipMessenger.sendYieldRebalance{value: fee}(
            POLYGON_CHAIN_SELECTOR,
            address(0x789), // yield optimizer
            address(0x123), // token
            1000, // amount
            address(0x456), // target protocol
            ICCIPMessenger.PayFeesIn.Native
        );

        assertTrue(messageId != bytes32(0));
    }

    function testEmergencyStop() public {
        // Only emergency role can activate emergency stop
        vm.prank(admin);
        ccipMessenger.setEmergencyStop(true);

        assertTrue(ccipMessenger.paused());

        // Should not be able to send messages when paused
        bytes memory data = abi.encode("test");

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        ccipMessenger.sendMessage(
            POLYGON_CHAIN_SELECTOR,
            bob,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );

        // Deactivate emergency stop
        vm.prank(admin);
        ccipMessenger.setEmergencyStop(false);
        assertFalse(ccipMessenger.paused());
    }

    function testUnauthorizedAccess() public {
        // Test that non-admin cannot perform admin functions
        vm.prank(bob);
        vm.expectRevert();
        ccipMessenger.allowlistDestinationChain(
            54321,
            address(mockRouter),
            300000
        );

        // Test that non-allowlisted sender cannot send messages
        bytes memory data = abi.encode("test");

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPMessenger.SenderNotAllowlisted.selector,
                bob
            )
        );
        ccipMessenger.sendMessage(
            POLYGON_CHAIN_SELECTOR,
            alice,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );
    }

    function testRevertOnUnsupportedChain() public {
        bytes memory data = abi.encode("test");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPMessenger.ChainNotAllowlisted.selector,
                99999
            )
        );
        ccipMessenger.sendMessage(
            99999, // Unsupported chain
            bob,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );
    }

    function testWithdrawFees() public {
        // Send some ETH to the contract
        vm.deal(address(ccipMessenger), 1 ether);

        uint256 initialBalance = feeCollector.balance;

        vm.prank(admin);
        ccipMessenger.withdrawFees(address(0), 0.5 ether, feeCollector);

        assertEq(feeCollector.balance, initialBalance + 0.5 ether);
    }

    function testSupportsInterface() public {
        // Test that the contract supports the required interfaces
        assertTrue(
            ccipMessenger.supportsInterface(type(AccessControl).interfaceId)
        );
        assertTrue(
            ccipMessenger.supportsInterface(
                type(IAny2EVMMessageReceiver).interfaceId
            )
        );
    }

    function testInsufficientFeeReverts() public {
        bytes memory data = abi.encode("test");

        vm.prank(alice);
        vm.expectRevert();
        ccipMessenger.sendMessage{value: 0.001 ether}( // Insufficient fee
            POLYGON_CHAIN_SELECTOR,
            bob,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );
    }

    function testMessageTypeDisabled() public {
        // Disable a message type
        vm.prank(admin);
        ccipMessenger.updateMessageTypeConfig(
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            500000,
            false, // disabled
            3
        );

        bytes memory data = abi.encode("test");
        uint256 fee = 1 ether; // Provide enough fee

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPMessenger.MessageTypeDisabled.selector,
                ICCIPMessenger.MessageType.YIELD_REBALANCE
            )
        );
        ccipMessenger.sendMessage{value: fee}(
            POLYGON_CHAIN_SELECTOR,
            bob,
            ICCIPMessenger.MessageType.YIELD_REBALANCE,
            data,
            address(0),
            0,
            ICCIPMessenger.PayFeesIn.Native
        );
    }
}
