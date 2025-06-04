_Note: This repo has been recently updated for Sepolia_

# Foundry Starter Kit

<br/>
<p align="center">
<a href="https://chain.link" target="_blank">
<img src="./img/chainlink-foundry.png" width="225" alt="Chainlink Foundry logo">
</a>
</p>
<br/>

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/smartcontractkit/foundry-starter-kit)

Foundry Starter Kit is a repo that shows developers how to quickly build, test, and deploy smart contracts with one of the fastest frameworks out there, [foundry](https://github.com/gakonst/foundry)!

- [Foundry Starter Kit](#foundry-starter-kit)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Quickstart](#quickstart)
  - [Testing](#testing)
- [Deploying to a network](#deploying-to-a-network)
  - [Setup](#setup)
  - [Deploying](#deploying)
    - [Working with a local network](#working-with-a-local-network)
    - [Working with other chains](#working-with-other-chains)
- [Security](#security)
- [Contributing](#contributing)
- [Thank You!](#thank-you)
  - [Resources](#resources)
    - [TODO](#todo)

# Getting Started

## Requirements

Please install the following:

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you've done it right if you can run `git --version`
- [Foundry / Foundryup](https://github.com/gakonst/foundry)
  - This will install `forge`, `cast`, and `anvil`
  - You can test you've installed them right by running `forge --version` and get an output like: `forge 0.2.0 (f016135 2022-07-04T00:15:02.930499Z)`
  - To get the latest of each, just run `foundryup`

## Quickstart

```sh
git clone https://github.com/smartcontractkit/foundry-starter-kit
cd foundry-starter-kit
```

## Install dependencies as follows:

Run `forge install` to install dependencies. [Foundry uses git submodules](https://book.getfoundry.sh/projects/dependencies) as its dependency management system.

> ⚠️ when running forge install, you may see an error message if you have uncomitted changes in your repo. Read the message carefully - it may inform you that you can add the `--no-commit` flag to each of these `install` commands if your workspace has uncommitted changes.

You can update dependencies by running `forge update`

## Testing

To check that everything is compiling and working as intended after cloning and installing dependencies, run

```
forge test
```

All tests should pass.

# Chainlink Foundry Starter Kit

Implementation of the following 4 Chainlink services using the [Foundry] (https://book.getfoundry.sh/) smart contract development tooling:

- [Chainlink Price Feeds](https://docs.chain.link/docs/using-chainlink-reference-contracts)
- [Chainlink VRF V2](https://docs.chain.link/docs/chainlink-vrf)
- [Chainlink Automation](https://docs.chain.link/chainlink-automation/introduction)

For [Chainlink Functions](https://docs.chain.link/chainlink-functions) please go to these starter kits: [Hardhat](https://github.com/smartcontractkit/functions-hardhat-starter-kit) | [Foundry (coming soon)](https://github.com/smartcontractkit/functions-foundry-starter-kit)

For [Chainlink CCIP (Cross Chain Interoperability Prototocol)](https://docs.chain.link/ccip) please go to these starter kits: [Hardhat](https://github.com/smartcontractkit/ccip-starter-kit-hardhat) | [Foundry](https://github.com/smartcontractkit/ccip-starter-kit-foundry)

# Deploying to a network

Deploying to a network uses the [foundry scripting system](https://book.getfoundry.sh/tutorials/solidity-scripting.html), where you write your deploy scripts in solidity!

## Setup

We'll demo using the Sepolia testnet. (Go here for [testnet sepolia ETH](https://faucets.chain.link/).)

You'll need to add the following variables to a `.env` file:

- `SEPOLIA_RPC_URL`: A URL to connect to the blockchain. You can get one for free from [Infura](https://www.infura.io/) account
- `PRIVATE_KEY`: A private key from your wallet. You can get a private key from a new [Metamask](https://metamask.io/) account
  - Additionally, if you want to deploy to a testnet, you'll need test ETH and/or LINK. You can get them from [faucets.chain.link](https://faucets.chain.link/).
- Optional `ETHERSCAN_API_KEY`: If you want to verify on etherscan

When you've added your environment variables to the `.env` file, run `source .env` in your terminal (and for each new terminal session) to load the environment variables into your terminal.

## Deploying

Deploy scripts are in `./script`. The relevant Chainlink Service can be determined from the name of the Contract script. `HelperConfig` is not meant to be deployed.

To deploy one of the Chainlink Service consumer contracts run the script as follows:

```
forge script script/${CONTRACT_NAME}.s.sol:Deploy${CONTRACT_NAME} --rpc-url $SEPOLIA_RPC_URL  --private-key PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY  -vvvv
make deploy-sepolia contract=<CONTRACT_NAME>
```

For example, to deploy the `PriceFeedConsumer` contract:

```
forge script script/PriceFeedConsumer.s.sol:DeployPriceFeedConsumer  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
```

If you don't have an `ETHERSCAN_API_KEY`, you can omit `--verify --etherscan-api-key $ETHERSCAN_API_KEY`

### Working with Anvil local development network

Foundry comes with local network [anvil](https://book.getfoundry.sh/anvil/index.html) baked in, and allows us to deploy to our local network for quick testing locally.

To start a local network run the following in a new terminal window or tab:

```
anvil
```

This will spin up a local blockchain on `http://localhost:8545` : (see console output for the mnemonic used, and 10 private keys and their associated wallet address), so you can use the same private key each time.

Then, you can deploy to it with one of those private keys; in this example we use the first one:

```
forge script script/${contract}.s.sol:Deploy${contract} --rpc-url http://localhost:8545  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

### Working with other chains

To add a chain, you'd just need to pass in the RPC URL for the relevant chain to the `--rpc-url` flag.

```
forge script script/${contract}.s.sol:Deploy${contract} --rpc-url ${<OTHER_CHAIN>_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast -vvvv

```

# Security

This framework comes with slither parameters, a popular security framework from [Trail of Bits](https://www.trailofbits.com/). To use slither, you'll first need to [install python](https://www.python.org/downloads/) and [install slither](https://github.com/crytic/slither#how-to-install).

Then, you can run:

```
make slither
```

And get your slither output.

# Contributing

Contributions are always welcome! Open a PR or an issue!
If you do contribute please add `solidity.formatter": "forge` to your VSCode Settings, or run `forge fmt` before you commit and push.

# Thank You!

## Resources

- [Chainlink Documentation](https://docs.chain.link/)
- [Foundry Documentation](https://book.getfoundry.sh/)

### TODO

[ ] Add bash scripts to interact with contracts using `cast`

[ ] Make deploying contracts to `anvil` simpler

# Alioth Smart Contracts

Alioth is an AI-driven cross-chain DeFi platform that combines yield optimization and undercollateralized lending. The smart contracts provide the core infrastructure for automated yield farming and cross-chain lending with AI-powered decision making.

## 🏗️ Architecture Overview

### Core Components

1. **Yield Optimizer Module**: AI-driven APR chasing across protocols and chains
2. **Cross-Chain Lending Module**: Undercollateralized loans with dynamic rates
3. **CCIP Integration**: Chainlink CCIP for secure cross-chain communication
4. **Protocol Adapters**: Uniform interfaces for DeFi protocol integration
5. **AI Agent Integration**: Role-based access for ElizaOS agents

### Key Features

- **AI-Driven Yield Optimization**: Automatically rebalances funds across protocols for optimal APY
- **Cross-Chain Lending**: Borrow assets on one chain using collateral from another
- **Undercollateralized Loans**: Dynamic interest rates based on credit scoring
- **Idle Collateral Routing**: Automatically routes loan collateral into yield strategies
- **Automated Liquidation Protection**: Monitors health factors and prevents liquidations
- **Emergency Circuit Breakers**: Multi-layered security with emergency stops

## 📁 Contract Structure

```
src/
├── interfaces/           # Contract interfaces
│   ├── IProtocolAdapter.sol
│   ├── IYieldOptimizer.sol
│   ├── ICrossChainLending.sol
│   └── ICCIPMessenger.sol
├── libraries/           # Shared libraries
│   ├── ValidationLib.sol
│   └── MathLib.sol
├── core/               # Core contracts
│   ├── YieldOptimizer.sol
│   ├── CrossChainLending.sol
│   └── CCIPMessenger.sol
├── adapters/           # Protocol adapters
│   └── AaveAdapter.sol
└── script/             # Deployment scripts
    └── DeployAlioth.s.sol
```

## 🔧 Core Contracts

### YieldOptimizer

The main yield optimization engine that manages fund allocation across multiple protocols.

**Key Functions:**

- `deposit()`: Deposit tokens with automatic optimal allocation
- `withdraw()`: Withdraw tokens with minimal market impact
- `executeRebalance()`: Rebalance funds based on AI recommendations
- `harvestAll()`: Harvest yield from all integrated protocols

**AI Integration:**

- Chainlink Automation for automated rebalancing
- Role-based access for AI agents (`REBALANCER_ROLE`)
- Real-time APY monitoring and optimization

### CrossChainLending

Enables undercollateralized lending with cross-chain capabilities.

**Key Functions:**

- `requestLoan()`: Submit loan request with collateral
- `approveLoan()`: AI agent approves loans based on credit analysis
- `makePayment()`: Make loan payments with automatic interest calculation
- `liquidateLoan()`: Liquidate undercollateralized positions

**Dynamic Features:**

- Credit score-based interest rates
- Health factor monitoring
- Cross-chain collateral management
- Automatic yield routing for idle collateral

### CCIPMessenger

Handles secure cross-chain communication using Chainlink CCIP.

**Key Functions:**

- `sendMessage()`: Send cross-chain messages with optional token transfers
- `sendYieldRebalance()`: Trigger rebalancing on other chains
- `sendLoanRequest()`: Submit cross-chain loan requests
- `sendLiquidationTrigger()`: Trigger liquidations across chains

## 🔌 Protocol Integration

### IProtocolAdapter Interface

All protocol integrations implement the standardized `IProtocolAdapter` interface:

```solidity
interface IProtocolAdapter {
    function protocolName() external view returns (string memory);
    function getAPY(address token) external view returns (uint256);
    function deposit(address token, uint256 amount, uint256 minShares) external returns (uint256);
    function withdraw(address token, uint256 shares, uint256 minAmount) external returns (uint256);
    function harvestYield(address token) external returns (uint256);
    // ... additional functions
}
```

### Supported Protocols

- **Aave**: Lending protocol adapter (`AaveAdapter.sol`)
- **Compound**: (Planned)
- **Yearn Finance**: (Planned)
- **Convex**: (Planned)

## 🤖 AI Agent Integration

### Role-Based Access Control

The contracts implement role-based access control for AI agents:

```solidity
// Yield Optimizer Roles
bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

// Lending Roles
bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");
bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

// Cross-Chain Roles
bytes32 public constant SENDER_ROLE = keccak256("SENDER_ROLE");
```

### AI Agent Functions

**Yield Monitoring Agent:**

- Monitors APRs across protocols
- Triggers rebalancing when profitable
- Harvests yield automatically

**Underwriting Agent:**

- Processes loan applications
- Analyzes credit data and risk factors
- Approves loans with dynamic rates

**Liquidation Monitor:**

- Monitors loan health factors
- Triggers liquidations before defaults
- Optimizes liquidation strategies

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
export FEE_COLLECTOR=0x...
export RPC_URL=https://...
export PRIVATE_KEY=0x...
```

### Deploy to Testnet

```bash
forge script script/DeployAlioth.s.sol:DeployTestnet --rpc-url $RPC_URL --broadcast --verify
```

### Deploy to Mainnet

```bash
forge script script/DeployAlioth.s.sol:DeployAlioth --rpc-url $RPC_URL --broadcast --verify
```

## 🔗 Chain Support

### Supported Networks

- **Ethereum**: Main deployment with full protocol support
- **Polygon**: Cross-chain lending and yield optimization
- **Arbitrum**: Lower gas costs for frequent operations
- **Avalanche**: (Planned)
- **Base**: (Planned)

### Cross-Chain Configuration

Each deployment supports cross-chain operations via Chainlink CCIP:

```solidity
// Chain Selectors
uint64 constant ETHEREUM_SELECTOR = 5009297550715157269;
uint64 constant POLYGON_SELECTOR = 4051577828743386545;
uint64 constant ARBITRUM_SELECTOR = 4949039107694359620;
```

## 📊 Key Metrics & KPIs

- **TVL Target**: $10M+ by launch
- **APY Performance**: Beat benchmark by 2%+
- **Liquidation Rate**: <2% of loans
- **Agent Uptime**: 99.9%
- **Cross-chain Success Rate**: >98%

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
forge test --match-path test/YieldOptimizer.t.sol
```

## 📚 Integration Examples

### Frontend Integration

```typescript
import { YieldOptimizer__factory } from './types'

const yieldOptimizer = YieldOptimizer__factory.connect(contractAddress, signer)

// Deposit tokens with optimal allocation
const tx = await yieldOptimizer.deposit(tokenAddress, amount, minShares)
```

### Backend API Integration

```typescript
// Monitor rebalancing opportunities
const shouldRebalance = await yieldOptimizer.shouldRebalance(
  tokenAddress,
  minImprovementBps,
)

if (shouldRebalance) {
  // Trigger AI agent rebalancing
  await triggerRebalanceAgent(tokenAddress)
}
```

## 🏛️ Governance & Upgrades

### Parameter Updates

Critical parameters can be updated through admin functions:

- Interest rate models
- LTV ratios and liquidation thresholds
- Protocol weights and allocations
- Fee rates and slippage tolerances

### Emergency Procedures

1. **Emergency Stop**: Immediate halt of all operations
2. **Parameter Freeze**: Lock parameter updates during incidents
3. **Fund Recovery**: Emergency withdrawal of stuck funds
4. **Protocol Pause**: Disable specific protocol integrations

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Documentation**: [docs.alioth.finance](https://docs.alioth.finance)
- **Website**: [alioth.finance](https://alioth.finance)
- **Discord**: [discord.gg/alioth](https://discord.gg/alioth)
- **Twitter**: [@AliothFinance](https://twitter.com/AliothFinance)

## ⚠️ Disclaimer

This software is experimental and unaudited. Use at your own risk. The Alioth protocol is under active development and contracts may change without notice.
