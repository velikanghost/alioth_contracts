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

## 🟢 Solution Overview (Alioth v0.1)

Alioth tackles those points with an all-on-chain approach:

• **Cross-Chain Deposits (Live)** – Users deposit once and Alioth bridges to Sepolia, Base-Sepolia, or Avalanche Fuji behind the scenes.
• **Protocol Abstraction (Live)** – Uniform adapters for **Aave** and **Compound** mean one API for both.
• **Chainlink-Verified Recommendations (Live)** – Every AI suggestion is validated on-chain via fresh price + APY feeds.
• **Automation for Test Feeds (Live)** – `MockV3Aggregator` uses Chainlink Automation to self-update during demos.
• **Automated Rebalancing (Planned)** – Optimizer contains Upkeep stubs; on-chain liquidity moves will ship in v0.2.

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

### End-to-End Flow

1. **Deposit** → Vault pulls token, validates price & APY via FeedManager (guarding against stale or malicious AI data), then forwards funds plus the `targetProtocol` hint to the Optimizer.
2. **Allocation** → Optimizer calls the chosen Adapter (**Aave** or **Compound**) on the selected chain.
3. **Automation** _(test only)_ → `MockV3Aggregator` self-updates via Automation. Optimizer Upkeep is a stub until migration logic arrives in v0.2.
4. **Cross-Chain** → If the chosen chain differs from the origin (Sepolia ⇄ Base-Sepolia ⇄ Fuji), Optimizer sends a CCIP message + token transfer; the destination Optimizer performs the deposit.

---

## 3️⃣ Pre-Deployed Contracts (Testnets)

| Network        | Feed Manager | Optimizer   | Vault       | CCIP Messenger |
| -------------- | ------------ | ----------- | ----------- | -------------- |
| Sepolia        | `0x471e0D…`  | `0x349933…` | `0x3811F1…` | `0x86a89e…`    |
| Base Sepolia   | `0xfB3005…`  | `0x9F26D1…` | `0x8BA1D0…` | `0xbd82c2…`    |
| Avalanche Fuji | `0xA4F7c5…`  | `0x2F0536…` | `0x5d6949…` | `0x9C62BF…`    |

Adapters & feed addresses for LINK / WBTC / ETH are listed in [`notes.txt`](notes.txt).

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

## 5️⃣ Mandatory End-to-End Demo (Single & Cross-Chain)

1. **Add LINK feeds & adapter support (Sepolia)**

   ```bash
   # 1A. Register LINK price feed
   cast send $FEED_MANAGER "setTokenFeeds(address,address,address,address)" \
       $LINK  $LINK_USD_FEED  0x000…0  0x000…0  --rpc-url $RPC  --account $PK

   # 1B. Register LINK in AaveAdapter
   cast send $AAVE_ADAPTER "addSupportedToken(address,address)" \
       $LINK  $LINK_ATOKEN --rpc-url $RPC --account $PK
   ```

2. **Add the adapter to the optimizer**

   ```bash
   cast send $OPTIMIZER "addProtocol(address)" $AAVE_ADAPTER --rpc-url $RPC --account $PK
   ```

3. **Verify setup**

   ```bash
   cast call $FEED_MANAGER  "isSupportedToken(address)(bool)"  $LINK  --rpc-url $RPC
   cast call $AAVE_ADAPTER  "supportsToken(address)(bool)"     $LINK  --rpc-url $RPC
   cast call $OPTIMIZER     "isChainlinkAllocationEnabled(address)(bool)" $LINK --rpc-url $RPC
   ```

4. **Run the dry-run allocation**

   ```bash
   cast call $OPTIMIZER "calculateOptimalAllocation(address,uint256)(uint256)" \
       $LINK  1000000000000000000 --rpc-url $RPC
   # should return non-zero APY value
   ```

5. **Deposit through the vault**

   ```bash
   cast send $LINK "approve(address,uint256)" $VAULT 1000000000000000000 --rpc-url $RPC --account $PK
   cast send $VAULT "deposit(address,uint256,uint256)" $LINK 1000000000000000000 0 --rpc-url $RPC --account $PK
   ```

6. **Cross-Chain Rebalance** – allow-list _destination_ and _source_ chains, then trigger a cross-chain message:

   ```bash
   # On origin chain
   cast send $CCIP_MESSENGER "allowlistDestinationChain(uint64,address,uint256)" \
       $DST_SELECTOR $DST_ROUTER 500000 --rpc-url $RPC --account $PK
   # On dest chain
   cast send $CCIP_MESSENGER "allowlistSourceChain(uint64,bool)" $SRC_SELECTOR true --rpc-url $DST_RPC --account $PK

   # Trigger the cross-chain rebalance (example moves 1 LINK to Base-Sepolia Optimizer)
   cast send $ORIGIN_OPTIMIZER "initiateCrossChainRebalance(uint64,address,address,uint256,address)" \
       $DST_SELECTOR $DEST_OPTIMIZER $LINK 1000000000000000000 $AAVE_ADAPTER \
       --rpc-url $RPC --account $PK
   ```

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
