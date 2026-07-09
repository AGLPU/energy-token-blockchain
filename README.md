# Solar Energy Blockchain

Smart contract project for the Rooftop Solar Energy Marketplace.
Handles minting, transferring, and burning of **SEC (Solar Energy Credit)** tokens.

> **1 SEC token = 1 kWh of solar energy**

---

## Project Structure

```
energy-token-blockchain/
├── contracts/
│   └── EnergyToken.sol      ← The smart contract (ERC-20)
├── scripts/
│   └── deploy.js            ← Deployment script
├── test/
│   └── EnergyToken.test.js  ← Automated tests
├── deployments/             ← Auto-generated after deploy (gitignored)
├── artifacts/               ← Auto-generated after compile (gitignored)
├── hardhat.config.js
├── package.json
└── .env.example
```

---

## Prerequisites

- Node.js v18+
- npm

---

## Setup (Run Once)

```bash
cd energy-token-blockchain
npm install
```

---

## Step 1 — Compile the Contract

```bash
npm run compile
```

This generates the ABI file inside `artifacts/` which the Python backend needs.

---

## Step 2 — Run Tests

```bash
npm test
```

All 14 tests should pass.

---

## Step 3 — Run Local Blockchain Node

Open a **separate terminal** and keep it running:

```bash
npm run node
```

This starts a local Ethereum node at `http://127.0.0.1:8545`
and prints 20 test accounts with private keys.

---

## Step 4 — Deploy Contract Locally

In another terminal:

```bash
npm run deploy:local
```

Output will show:
```
✅ Contract deployed!
   Address  : 0xABC...123
   ...

📌 Copy these into your FastAPI .env:
   BLOCKCHAIN_ENABLED=True
   BLOCKCHAIN_CONTRACT_ADDRESS=0xABC...123
   BLOCKCHAIN_RPC_URL=http://127.0.0.1:8545
   BLOCKCHAIN_PRIVATE_KEY=<key from node output>
```

Copy those values into the FastAPI project `.env` file.

---

## Deploy to Sepolia Testnet (optional)

1. Copy `.env.example` to `.env`
2. Fill in `SEPOLIA_RPC_URL` and `DEPLOYER_PRIVATE_KEY`
3. Run:

```bash
npm run deploy:sepolia
```

---

## How It Connects to FastAPI

```
FastAPI (Python)
     │
     │  calls web3.py
     ▼
EnergyToken Contract (Solidity)
     │
     ├── mintEnergy()       ← when seller creates a listing
     ├── recordPurchase()   ← when buyer purchases energy
     └── consumeEnergy()    ← when buyer uses the energy
```

The ABI file location used by Python:
```
energy-token-blockchain/artifacts/contracts/EnergyToken.sol/EnergyToken.json
```

Make sure the Python `blockchain_service.py` points to this path.

