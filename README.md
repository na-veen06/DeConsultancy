# 🚀 DeConsultancy – Decentralized Freelance Escrow Platform

A **trustless freelance marketplace smart contract** built on Ethereum that enables secure transactions between buyers and sellers using an escrow mechanism with built-in dispute resolution.

---

## ✨ Features

- 🔒 **Escrow Payments** – Funds are locked securely inside the contract
- 🤝 **Seller Acceptance Workflow** – Sellers explicitly accept work before starting
- 🧑‍💻 **Seller Protection** – Claim funds after buyer inactivity (timeout)
- 🛡️ **Buyer Protection** – Refund if seller misses delivery deadlines
- ❌ **Order Cancellation** – Buyers can cancel unaccepted orders after timeout
- ⚖️ **Dispute Resolution** – Arbiter-based majority voting system
- 🧮 **Split Resolution** – Manual fund distribution by arbiter
- ⏱️ **Timeout Fallback** – Automatic dispute resolution after timeout
- 💰 **Platform Fees** – Configurable fee deducted from seller earnings
- 🔐 **Security** – Reentrancy protection + gas-efficient custom errors

---

## 🧠 How It Works

### Order Lifecycle

```text
Paid
↓
Seller accepts order
↓
InProgress
↓
Seller delivers work
↓
Delivered
├─ Buyer approves payment
├─ Buyer/Seller raises dispute
└─ Seller claims after timeout
↓
Completed
```

---

### Workflow

1. **Seller sets service price**
2. **Buyer creates order & sends payment into escrow**
3. **Seller accepts the order**
4. **Delivery timer starts**
5. **Seller delivers work (off-chain)**

### Buyer Options

- ✅ Approve delivery → Seller receives payment
- ❌ Raise dispute → Arbiter voting begins
- 💸 Claim refund → If seller misses deadline
- ⏳ Cancel order → If seller never accepts

### Seller Options

- 🤝 Accept project
- 📦 Deliver completed work
- ⏱️ Claim funds after buyer inactivity
- ❌ Raise dispute if necessary

### If Dispute Occurs

- Majority arbiter voting decides outcome
- Arbiter can manually split funds
- Timeout fallback resolves automatically

---

## 📜 Smart Contract Highlights

- Minimal storage using `hashes` for requirements and delivered work
- Event-driven architecture
- Gas-optimized custom errors
- Secure ETH transfers with `ReentrancyGuard`
- Delivery deadlines start only after seller acceptance
- Explicit workflow state management

---

## 📊 Coverage

Current test coverage:

- ✅ Lines: `96.49%`
- ✅ Statements: `97.86%`
- ✅ Functions: `100%`
- ✅ Branches: `77.38%`

---

## 🔮 Future Improvements (v2)

- DAO-based decentralized arbitration
- Full frontend Web3 integration
- Reputation system for buyers & sellers
- Multi-token payment support
- On-chain profile system

---

## 🛠️ Tech Stack

- Solidity `^0.8.19`
- Foundry (`Forge`, `Cast`, `Anvil`)
- OpenZeppelin (`ReentrancyGuard`)

---

## ⚙️ Foundry Usage

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Coverage

```bash
forge coverage
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

### Local Node

```bash
anvil
```

### Deploy

```bash
forge script script/DeConsultancy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

### Cast

```bash
cast <subcommand>
```

---

## 📄 License

MIT