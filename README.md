# Alioth Smart Contracts

Alioth is an AI-driven multi-asset yield optimization platform that provides automated yield farming across multiple DeFi protocols. The smart contracts enable users to deposit various ERC20 tokens and receive optimized yield through intelligent protocol selection.

## 🏗️ Architecture Overview

### Core Components

1. **Multi-Asset Vault**: Supports deposits of multiple ERC20 tokens (USDC, DAI, LINK, WETH, etc.)
2. **Receipt Token System**: Issues tradeable receipt tokens (atUSDC, atDAI, etc.) representing user shares
3. **Enhanced Yield Optimizer**: AI-driven protocol selection and automated rebalancing
4. **Protocol Adapters**: Uniform interfaces for DeFi protocol integration (Aave, Compound, Yearn)
5. **Cross-Chain Infrastructure**: Chainlink CCIP for cross-chain yield optimization
6. **AI Agent Integration**: Role-based access for automated operations

### Key Features

- **Multi-Asset Support**: Deposit any supported ERC20 token and earn optimized yield
- **Receipt Tokens**: Get tradeable ERC20 tokens (atUSDC, atDAI) representing your vault shares
- **AI-Driven Protocol Selection**: Automatically selects best yield protocols for each token
- **Automated Rebalancing**: Moves funds between protocols when better yields are available
- **Cross-Chain Operations**: Leverage Chainlink CCIP for cross-chain yield opportunities
- **Chainlink Integration**: Uses Chainlink feeds for price validation and APY tracking
- **Emergency Circuit Breakers**: Multi-layered security with emergency stops

## 📁 Contract Structure

```
src/
├── interfaces/           # Contract interfaces
│   ├── IProtocolAdapter.sol
│   ├── IEnhancedYieldOptimizer.sol
│   └── ICCIPMessenger.sol
├── libraries/           # Shared libraries
│   ├── ValidationLib.sol
│   ├── MathLib.sol
│   └── DynamicAllocationLib.sol
├── core/               # Core contracts
│   ├── EnhancedYieldOptimizer.sol
│   ├── EnhancedChainlinkFeedManager.sol
│   └── CCIPMessenger.sol
├── vaults/             # Vault contracts
│   └── AliothVault.sol
├── tokens/             # Token contracts
│   └── AliothReceiptToken.sol
├── factories/          # Factory contracts
│   └── ReceiptTokenFactory.sol
├── adapters/           # Protocol adapters
│   ├── AaveAdapter.sol
│   └── CompoundAdapter.sol
└── script/             # Deployment scripts
    ├── DeployVault.s.sol
    ├── DeployAdapters.s.sol
    └── DeployAIIntegration.s.sol
```

## 🔧 Core Contracts

### AliothVault

The main multi-asset vault that handles user deposits and issues receipt tokens.

**Key Functions:**

- `deposit(token, amount, minShares, targetProtocol)`: Deposit any supported token
- `withdraw(token, shares, minAmount, targetProtocol)`: Withdraw by burning receipt tokens
- `addToken(token, symbol, minDeposit, maxDeposit)`: Add support for new tokens
- `getUserPortfolio(user)`: Get comprehensive portfolio information

**Receipt Token System:**

- Automatic creation of receipt tokens (atUSDC, atDAI, etc.)
- ERC20 tokens visible in user wallets
- Tradeable and transferable
- Represent proportional shares in yield strategies

### EnhancedYieldOptimizer

The AI-driven yield optimization engine that manages protocol allocation.

**Key Functions:**

- `executeSingleOptimizedDeposit()`: Execute optimized deposits with AI protocol selection
- `executeWithdrawal()`: Handle withdrawals from specific protocols
- `automatedRebalance()`: AI-triggered rebalancing between protocols
- `addProtocol()`: Add new protocol adapters

**AI Integration:**

- Chainlink Automation for automated rebalancing
- Role-based access for AI agents (`REBALANCER_ROLE`, `AUTHORIZED_VAULT_ROLE`)
- Real-time APY monitoring and protocol comparison
- Validation using Chainlink price feeds

### EnhancedChainlinkFeedManager

Manages Chainlink price feeds and market data for yield optimization.

**Key Functions:**

- `setTokenFeeds()`: Configure price, rate, and volatility feeds for tokens
- `getMarketAnalysis()`: Get comprehensive market analysis for supported tokens
- `validateTokenPrice()`: Validate token prices against Chainlink feeds
- `getProtocolAPY()`: Get current APY data for protocols

### CCIPMessenger

Handles secure cross-chain communication using Chainlink CCIP.

**Key Functions:**

- `sendMessage()`: Send cross-chain messages with optional token transfers
- `sendYieldRebalance()`: Trigger rebalancing on other chains
- `allowlistChain()`: Configure supported destination chains
- `allowlistSender()`: Configure trusted cross-chain senders

## 🔌 Protocol Integration

### IProtocolAdapter Interface

All protocol integrations implement the standardized `IProtocolAdapter` interface:

```solidity
interface IProtocolAdapter {
    function protocolName() external view returns (string memory);
    function getAPY(address token) external view returns (uint256);
    function getTVL(address token) external view returns (uint256);
    function deposit(address token, uint256 amount, uint256 minShares) external payable returns (uint256);
    function withdraw(address token, uint256 shares, uint256 minAmount) external returns (uint256);
    function harvestYield(address token) external returns (uint256);
}
```

### Supported Protocols

- **Aave**: Lending protocol adapter (`AaveAdapter.sol`)
- **Compound**: Money market protocol adapter (`CompoundAdapter.sol`)
- **Yearn Finance**: (Planned)
- **Convex**: (Planned)

## 🪙 Receipt Token System

### How It Works

1. **Deposit**: User deposits USDC → receives atUSDC receipt tokens
2. **Yield Earning**: atUSDC represents share in USDC yield strategy
3. **Withdrawal**: User burns atUSDC → receives USDC + earned yield
4. **Transferable**: atUSDC can be traded, transferred, or used in other protocols

### Supported Tokens & Receipt Tokens

| Token | Receipt Token | Symbol |
| ----- | ------------- | ------ |
| USDC  | Alioth USDC   | atUSDC |
| DAI   | Alioth DAI    | atDAI  |
| LINK  | Alioth LINK   | atLINK |
| WETH  | Alioth WETH   | atWETH |
| WBTC  | Alioth WBTC   | atWBTC |

## 🤖 AI Agent Integration

### Role-Based Access Control

The contracts implement role-based access control for AI agents:

```solidity
// Enhanced Yield Optimizer Roles
bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
bytes32 public constant AUTHORIZED_VAULT_ROLE = keccak256("AUTHORIZED_VAULT_ROLE");

// Cross-Chain Roles
bytes32 public constant SENDER_ROLE = keccak256("SENDER_ROLE");
bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
```

### AI Agent Functions

**Yield Optimization Agent:**

- Monitors APRs across protocols for each token
- Triggers rebalancing when profitable opportunities arise
- Selects optimal protocols for new deposits
- Validates operations using Chainlink feeds

**Cross-Chain Coordinator:**

- Monitors yield opportunities across different chains
- Triggers cross-chain rebalancing via CCIP
- Manages cross-chain asset allocation
- Handles emergency cross-chain operations

## 🔄 User Flow Example

1. **User deposits 1000 USDC** to AliothVault
2. **AI analyzes** current yields: Aave USDC (4.2%), Compound USDC (4.8%)
3. **Vault selects** Compound for better yield
4. **User receives** atUSDC receipt tokens representing their share
5. **AI monitors** continuously and rebalances if better yields emerge
6. **User withdraws** anytime by burning atUSDC for USDC + earned yield

## 🛡️ Security Features

### Access Control

- Multi-signature requirements for admin functions
- Role-based access for different operations
- Timelock mechanisms for critical parameter updates

### Safety Mechanisms

- Emergency stop functionality across all contracts
- Reentrancy guards on all external functions
- Slippage protection for all trades
- Oracle staleness checks

### Validation

- Comprehensive input validation using `ValidationLib`
- Custom errors for gas efficiency
- Range checks for all parameters

## 🚀 Deployment

### Prerequisites

1. Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:

```bash
forge install
```

3. Set environment variables:

```bash
export ADMIN_ADDRESS=0x...
export SEPOLIA_RPC_URL=https://...
export PRIVATE_KEY=0x...
```

### Deploy to Sepolia Testnet

1. **Deploy Enhanced Yield Optimizer and dependencies:**

```bash
forge script script/DeployAIIntegration.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

2. **Deploy Protocol Adapters:**

```bash
forge script script/DeployAdapters.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

3. **Deploy Multi-Asset Vault:**

```bash
forge script script/DeployVault.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

### Deployed Contracts (Sepolia)

```
EnhancedYieldOptimizer: 0xDeE85d65aaDaff8e10164e05e0a8d2AD871e8db0
AliothVault: 0xFBC065B72f312Ad41676B977E01aBd9cf86CeF1A
ReceiptTokenFactory: 0xa224d911E2888b2e92188C6586879E18d50c1404
AaveAdapter: 0x806A4f611061b80d7422Ef4Cc108c0e1c7090A05
CompoundAdapter: 0xb33FacE783e024843964A2Dc7fcb32F77E7D4d03
```

## 🔗 Chain Support

### Supported Networks

- **Ethereum Sepolia**: Primary testnet deployment
- **Arbitrum Sepolia**: Lower gas costs for frequent operations
- **Base Sepolia**: (Planned)
- **Avalanche Fuji**: (Planned)

### Supported Tokens (Sepolia)

- **LINK**: 0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5
- **WBTC**: 0x29f2D40B0605204364af54EC677bD022dA425d03
- **WETH**: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c

### Cross-Chain Configuration

Each deployment supports cross-chain operations via Chainlink CCIP:

```solidity
// Chain Selectors (Testnet)
uint64 constant SEPOLIA_SELECTOR = 16015286601757825753;
uint64 constant ARBITRUM_SEPOLIA_SELECTOR = 3478487238524512106;
uint64 constant BASE_SEPOLIA_SELECTOR = 10344971235874465080;
```

## 📊 Key Metrics & KPIs

- **TVL Target**: $1M+ on testnet
- **APY Performance**: Beat individual protocol yields
- **Agent Uptime**: 99.9%
- **Cross-chain Success Rate**: >98%
- **Receipt Token Adoption**: Tradeable and transferable

## 🧪 Testing

Run the test suite:

```bash
forge test
```

Run tests with gas reporting:

```bash
forge test --gas-report
```

Run specific test files:

```bash
forge test --match-path test/unit/
forge test --match-path test/integration/
```

## 📚 Integration Examples

### Frontend Integration

```typescript
import { AliothVault__factory, AliothReceiptToken__factory } from './types'

const vault = AliothVault__factory.connect(vaultAddress, signer)

// Deposit USDC and receive atUSDC receipt tokens
const tx = await vault.deposit(
  usdcAddress,
  ethers.parseUnits('1000', 6), // 1000 USDC
  ethers.parseUnits('990', 6), // Min 990 atUSDC (1% slippage)
  'aave', // Target protocol
)

// Check user's atUSDC balance
const receiptToken = AliothReceiptToken__factory.connect(atUsdcAddress, signer)
const balance = await receiptToken.balanceOf(userAddress)
```

### Backend AI Integration

```typescript
// Monitor rebalancing opportunities across protocols
const aaveAPY = await enhancedYieldOptimizer.getProtocolAPY(0, usdcAddress) // AAVE
const compoundAPY = await enhancedYieldOptimizer.getProtocolAPY(1, usdcAddress) // COMPOUND

if (compoundAPY > aaveAPY + rebalanceThreshold) {
  // Trigger AI agent rebalancing
  await enhancedYieldOptimizer.automatedRebalance(
    optimizationId,
    compoundAPY,
    Date.now(),
  )
}
```

### Portfolio Management

```typescript
// Get user's complete portfolio across all tokens
const portfolio = await vault.getUserPortfolio(userAddress)

console.log('User Portfolio:')
for (let i = 0; i < portfolio.tokens.length; i++) {
  console.log(`${portfolio.symbols[i]}: ${portfolio.shares[i]} shares`)
  console.log(`Receipt Token: ${portfolio.receiptTokens[i]}`)
  console.log(`Current Value: ${portfolio.values[i]}`)
}
```

## 🏛️ Governance & Upgrades

### Parameter Updates

Critical parameters can be updated through admin functions:

- Rebalance intervals and thresholds
- Protocol adapter weights and priorities
- Fee rates and slippage tolerances
- Token support and minimum deposits

### Emergency Procedures

1. **Emergency Stop**: Immediate halt of all vault operations
2. **Protocol Pause**: Disable specific protocol integrations
3. **Fund Recovery**: Emergency withdrawal capabilities
4. **Parameter Freeze**: Lock parameter updates during incidents

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Development Guidelines

- Follow Alioth smart contract development rules
- Use Foundry for testing and deployment
- Implement proper access controls
- Add comprehensive NatSpec documentation
- Test on testnets before mainnet deployment

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Documentation**: [docs.alioth.finance](https://docs.alioth.finance)
- **Website**: [alioth.finance](https://alioth.finance)
- **Discord**: [discord.gg/alioth](https://discord.gg/alioth)
- **Twitter**: [@AliothFinance](https://twitter.com/AliothFinance)

## ⚠️ Disclaimer

This software is experimental and unaudited. Use at your own risk. The Alioth protocol is under active development and contracts may change without notice. Receipt tokens represent shares in yield strategies and their value may fluctuate based on underlying protocol performance.
