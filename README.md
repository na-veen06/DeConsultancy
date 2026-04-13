# 🚀 DeConsultancy – Decentralized Freelance Escrow Platform

A **trustless freelance marketplace smart contract** built on Ethereum that enables secure transactions between buyers and sellers using an escrow mechanism with built-in dispute resolution.

---

## ✨ Features

- 🔒 **Escrow Payments** – Funds are locked until conditions are met  
- 🧑‍💻 **Seller Protection** – Claim funds after buyer inactivity (timeout)  
- 🛡️ **Buyer Protection** – Refund if seller fails to deliver  
- ⚖️ **Dispute Resolution** – Arbiter-based voting system  
- 🧮 **Split Resolution** – Manual fund distribution by arbiter  
- ⏱️ **Timeout Fallback** – Automatic resolution if no votes  
- 💰 **Platform Fees** – Configurable fee deducted from seller earnings  
- 🔐 **Security** – Reentrancy protection + custom errors  

---

## 🧠 How It Works

1. **Seller sets price**
2. **Buyer creates order & sends payment (escrow)**
3. **Seller delivers work (off-chain)**

### Buyer Options:
- ✅ Approve → Seller gets paid  
- ❌ Raise dispute → Arbiter voting  
- ⏳ Do nothing → Seller claims after timeout  

### If Dispute Occurs:
- Majority voting decides winner  
- Arbiter can split funds  
- Timeout fallback resolves automatically  

---

## 📜 Smart Contract Highlights

- Minimal storage using `hashes` for off-chain data  
- Event-driven architecture  
- Gas-optimized custom errors  
- Secure ETH transfers using `ReentrancyGuard`  

---

## 🔮 Future Improvements (v2)

- DAO-based decentralized arbitration  
- Frontend (Web3 UI) integration  
- Reputation system for buyers & sellers  
- Multi-order & milestone support  

---

## 🛠️ Tech Stack

- Solidity `^0.8.19`
- Foundry (Forge, Cast, Anvil)

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
forge script script/DeConsultancy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast
```bash
cast <subcommand>
```

---

## 📄 License
MIT