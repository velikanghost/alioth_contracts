# Alioth ⚡️ – AI-Driven Cross-Chain Yield Optimizer

![Chainlink CCIP](https://img.shields.io/badge/Chainlink-CCIP-blue)
![Foundry](https://img.shields.io/badge/Built%20With-Foundry-red)
![Hackathon](https://img.shields.io/badge/Hackathon-Project-important)

> **Alioth** is an on-chain, cross-chain yield optimiser that discovers the best APRs, routes liquidity, and rebalances positions **automatically** using Chainlink Feeds, Automation, and CCIP.

---

## 🚩 Problem Statement

Today's yield strategies are siloed per chain and rely on unverified off-chain signals. Users face:

1. **Fragmented Liquidity** – Attractive APRs move across chains (and between Aave ⇄ Compound), forcing manual bridging.
2. **Data Integrity Risks** – Bots can feed falsified rates to naïve contracts, leading to mis-allocations or losses.
3. **Cumbersome UX** – Depositing into multiple protocols on multiple chains requires a dozen approvals and UI hops.

---

## 🟢 Solution

Alioth delivers:

1. **Cross-Chain Deposits (Live)** – One transaction deposits and, if needed, bridges assets to Sepolia, Base-Sepolia, or Avalanche Fuji via CCIP.
2. **Protocol Abstraction (Live)** – Uniform adapters expose the same interface for **Aave** and **Compound**.
3. **Chainlink-Verified Recommendations (Live)** – Every AI hint is validated on-chain via fresh price & APY feeds before execution.
4. **Automation for Test Feeds (Live)** – `MockV3Aggregator` keeps demo price feeds fresh with Chainlink Automation.
5. **Automated Rebalancing (Planned)** – Upkeep stubs are ready; v0.2 will introduce on-chain liquidity migration.

---

## 1️⃣ Why Alioth?

Current yield aggregators are usually locked to a single chain, rely on off-chain cron jobs, and make naïve rebalancing decisions. Alioth solves these issues by combining:

1. **On-Chain Portfolio Logic** – Solidity contracts that hold assets and talk to protocol adapters (Aave, Compound, …).
2. **Chainlink Feeds & Automation** – Reliable APY / price data and keeper-style jobs that trigger rebalances.
3. **Chainlink CCIP** – Trust-minimised cross-chain messaging & token transfers so the optimiser can chase yields on any supported network.
4. **Optional AI Agent (off-chain)** – _not required for judging;_ all critical portfolio logic lives **on-chain**. No backend setup is necessary for the demo.

---

## 2️⃣ Contract Overview

```text
alioth_contracts/src
├── core
│   ├── AliothYieldOptimizer.sol   # Main orchestrator
│   ├── AliothVault.sol            # ERC-4626-style vault wrapper
│   ├── CCIPMessenger.sol          # Cross-chain router (CCIP)
│   └── ChainlinkFeedManager.sol   # Manages price / APY / vol feeds
├── adapters
│   ├── AaveAdapter.sol            # Talks to Aave v3 markets
│   └── CompoundAdapter.sol        # Talks to Compound v3
├── libraries
│   ├── DynamicAllocationLib.sol   # (WIP) multi-factor optimiser
│   ├── MathLib.sol                # Fixed-point helpers
│   └── ValidationLib.sol          # Common require helpers
├── mocks
│   └── MockV3Aggregator.sol       # Test oracle with Automation
└── factories
    └── ReceiptTokenFactory.sol    # Minimal-proxy receipt tokens
```

### Core Contracts in Detail

| Contract                                        | Purpose                                                                                                                                                                    | Key Chainlink Usage                                                                                                                                        |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AliothYieldOptimizer**                        | Central brain that holds assets, tracks supported adapters, and decides where funds should go. Handles deposits/withdrawals, maintains APY cache, and executes rebalances. | • Feeds – `getBestProtocolAPY` <br> • Automation – `checkUpkeep` / `performUpkeep` <br> • (WIP) Will call `DynamicAllocationLib` for multi-protocol splits |
| **AliothVault** (ERC-4626)                      | User-facing wrapper that tokenises positions (mints `AliothReceiptToken`). Delegates capital to the Optimizer and enforces slippage checks.                                | • Feeds – price validation on deposits/withdrawals                                                                                                         |
| **ChainlinkFeedManager**                        | Aggregator & registrar for price / APY / volatility feeds. Caches projections for gas efficiency.                                                                          | • Feeds – direct calls to `AggregatorV3Interface`                                                                                                          |
| **CCIPMessenger**                               | Thin wrapper around `RouterClient` that sends/receives liquidity & instructions between chains. Includes allow-lists for dest / source chains and authorised senders.      | • CCIP – token+message send / receive                                                                                                                      |
| **Adapters** (`AaveAdapter`, `CompoundAdapter`) | Protocol-specific wrappers that normalise deposits, withdrawals, TVL, APY, health metrics.                                                                                 | —                                                                                                                                                          |
| **DynamicAllocationLib**                        | Scoring engine that produces weighted allocations from Chainlink data + adapter stats. Integration planned post-hackathon.                                                 | • Feeds – price, APY, volatility                                                                                                                           |
| **MockV3Aggregator** _(test only)_              | Lightweight on-chain oracle used in demos and unit tests. Can self-update its answer every `interval` seconds via Chainlink Automation.                                    | • Implements `AggregatorV3Interface` <br> • Automation – `checkUpkeep` / `performUpkeep` push new rounds                                                   |

### End-to-End Flow

1. **Deposit** → Vault pulls token, validates price & APY via FeedManager (guarding against stale or malicious AI data), then forwards funds plus the `targetProtocol` hint to the Optimizer.
2. **Allocation** → Optimizer calls the chosen Adapter (**Aave** or **Compound**) on the selected chain.
3. **Automation** _(test only)_ → `MockV3Aggregator` self-updates via Automation. Optimizer Upkeep is a stub until migration logic arrives in v0.2.
4. **Cross-Chain** → If the chosen chain differs from the origin (Sepolia ⇄ Base-Sepolia ⇄ Fuji), Optimizer sends a CCIP message + token transfer; the destination Optimizer performs the deposit.

---

## 3️⃣ Pre-Deployed Contracts (Testnets)

| Network        | Feed Manager                                 | Optimizer                                    | Vault                                        | CCIP Messenger                               |
| -------------- | -------------------------------------------- | -------------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| Sepolia        | `0x471e0DC1B324c3bE18B9D6a46cDBdDD6464078A6` | `0x3499331d4c0d88028a61bf1516246C29C30AFf8E` | `0x3811F1a5481Ec93ac99d8e76A6FA6C4f6EFd39D4` | `0x86a89efA6029eFEd8b21cDC0A4760761376c2A47` |
| Base Sepolia   | `0xfB300529C4098A956F5C2f15D7E322717097411f` | `0x9F26D100fdB2Ca6810019062B9a3C6c01Afa21e6` | `0x8BA1D001466b23F844041112E92a07e99Cb439F6` | `0xbd82c2a2AA4c5eAB8D401E0b1362CA4548C7BB45` |
| Avalanche Fuji | `0xA4F7c5c3d3fba94Bf77C89bD41818D7662ed9dAE` | `0x2F05369A361e7F452F5e5393a565D4d1cA88F80A` | `0x5d69494cA5e2B7349B2C81F8acf63E1E15057586` | `0x9C62BFe2134C990ef373DF581487d51Eb4Efa989` |

### Adapter Addresses

| Network        | AaveAdapter                                  | CompoundAdapter                              | Mock Price Feed                              |
| -------------- | -------------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| Sepolia        | `0x2F9F0e0f3B936278983498E85cf022ce0Bb7EF2A` | `0x2745490eab4A90a82C80Db969F2Bb2A063c67Dd5` | `0xe21A8b41FC50fd43CFE52AC67790BB60509eAB88` |
| Base Sepolia   | —                                            | `0x62843F00870d99decd0F720038E35fD5114eFd43` | `0x24813C3acf475b9c8Abce1B5E34775A8448f7eD5` |
| Avalanche Fuji | `0x5E4FfA1d7783E2465F7243D86fFC4Fe64011549B` | —                                            | `0x3C4C8B3AA7C43C6045C7bA3517583E355faDe272` |

---

## 4️⃣ Quick Start (Local)

```bash
# 0. Prerequisites
#    – Foundry (https://book.getfoundry.sh/)
#    – Node ≥18 if you want to run the AI backend later

# 1. Clone + install submodules
$ git clone https://github.com/<your-fork>/alioth_contracts.git
$ cd alioth_contracts
$ forge install           # pulls OZ, solmate, etc.

# 2. Run tests
$ forge test -vv          # ≈400 smart-contract tests

# 3. Deploy core to anvil
$ forge script script/DeployCore.s.sol --fork-url http://localhost:8545 --broadcast
```

_Tip:_ all deploy scripts accept `--rpc-url` & `--private-key` so you can broadcast to public testnets.

---

## 5️⃣ Testing

Below are the core Vault functions. They are fully network-agnostic—just point `$RPC` and contract addresses at Sepolia, Base-Sepolia, or Avalanche Fuji.

### Solidity Signatures

```solidity
/**
 * Deposit tokens and let the optimiser choose where to earn yield.
 * - token: ERC-20 address (e.g. LINK)
 * - amount: deposit size
 * - minShares: slippage guard (can be 0 for tests)
 * - targetProtocol: "aave" | "compound" (AI recommendation)
 */
function deposit(
    address token,
    uint256 amount,
    uint256 minShares,
    string calldata targetProtocol
) external nonReentrant returns (uint256 shares);

/**
 * Burn receipt tokens and receive the underlying asset back.
 */
function withdraw(
    address token,
    uint256 shares,
    uint256 minAmount,
    string calldata targetProtocol
) external nonReentrant returns (uint256 amount);
```

### Quick Cast Examples

```bash
# Approve Vault and deposit 1 LINK into Aave on Sepolia
cast send $LINK "approve(address,uint256)" $VAULT 1000000000000000000 \
  --rpc-url $RPC --account $PK

cast send $VAULT "deposit(address,uint256,uint256,string)" \
  $LINK 1000000000000000000 0 "aave" \
  --rpc-url $RPC --account $PK

# Withdraw all shares back from Compound on Base-Sepolia
cast send $VAULT "withdraw(address,uint256,uint256,string)" \
  $LINK $MY_SHARES 0 "compound" \
  --rpc-url $BASE_RPC --account $PK
```

For cross-chain tests, use the _allow-list_ commands shown earlier, then call `initiateCrossChainRebalance` from the Optimizer.

---

## 6️⃣ Project Roadmap

| Phase               | Features                                                                                                                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **MVP (hackathon)** | Single-protocol deposit, APY-based rebalancing stub, CCIP scaffolding                                                                                  |
| **Post-hackathon**  | 🔜 Integrate `DynamicAllocationLib` for weighted splits <br> 🔜 Full on-chain liquidity migration <br> 🔜 Front-end dashboard & AI backend open-source |

---

## 7️⃣ Contributing / Questions

Pull Requests are welcome! For issues reach out in the **Alioth** Discord channel.

---

<p align="center">Made with ❤️  for Chainlink ✦ Monad ✦ ETHGlobal</p>
