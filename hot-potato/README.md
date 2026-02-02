# Hot Potato Flash Loan (Fungible Asset + Object Stores)

This project demonstrates a **Flash Loan** implementation using Cedra's Fungible Asset (FA) standard and the Object model. It utilizes the "Hot Potato" pattern to enforce atomicity of borrowing and repayment within a single transaction.

## 🚀 Test Deployment (Devnet)

The contract has been deployed to the Cedra Devnet.

| Key | Value |
| --- | --- |
| **Network** | Devnet |
| **Package ID** | `0x372ea0ac5a1c977e729f72740f73b78ae8a12f81a16c55e384921c26483f1606` |
| **Module Name** | `flash_loan` |
| **Deployment Transaction** | [0xfccdc5871048d4ea9dc021ac786da5e2015da8a9e317147a3db9774502bbfdaf](https://cedrascan.com/txn/0xfccdc5871048d4ea9dc021ac786da5e2015da8a9e317147a3db9774502bbfdaf?network=devnet) |
| **Sender Address** | `0x372ea0ac5a1c977e729f72740f73b78ae8a12f81a16c55e384921c26483f1606` |

## 💡 Concept: The "Hot Potato"

In Move, a struct without the `store`, `copy`, or `drop` abilities is often called a "Hot Potato".
- **Cannot be stored** in global storage.
- **Cannot be copied** (duplicated).
- **Cannot be dropped** (ignored/discarded at end of scope).

The only way to deal with such a struct is to pass it to a function that explicitly consumes it (unpacking it).

In this Flash Loan contract:
1. `borrow()` returns the assets AND a `FlashReceipt` (the hot potato).
2. The borrower uses the assets.
3. The borrower MUST call `repay()` to consume the `FlashReceipt`.
4. If `repay()` is not called, the transaction fails verification because the `FlashReceipt` cannot be dropped.

This mathematically guarantees that the `borrow` and `repay` happen in the same transaction.

## ✨ Features

- **Object-based Vaults**: Each vault is a distinct object holding a specific FA.
- **Dynamic Fees**: Vault owners can set a fee (in basis points, e.g., 30 bps = 0.3%).
- **Metadata Agnostic**: The contract supports any Fungible Asset (FA).

## 📖 Usage Guide

### 1. Create a Flash Loan Vault
A user (provider) creates a vault to lend a specific asset.

```move
use hot_potato::flash_loan;

// Create a vault for a specific FA metadata with a 0.3% fee
let vault_obj = flash_loan::create_vault(owner, fa_metadata, 30);
```

### 2. Deposit Liquidity
The owner deposits assets into the vault to be loaned out.

```move
// Deposit 500,000 units of the asset
flash_loan::deposit_from(owner, vault_obj, fa_metadata, 500_000);
```

### 3. Borrow and Repay (The Flash Loan)
A borrower borrows assets, uses them (arbitrage, liquidation, etc.), and repays them + fee in the same transaction.

```move
use hot_potato::flash_loan;

// 1. Borrow
let amount = 10_000;
let (loaned_assets, receipt) = flash_loan::borrow(vault_obj, amount);

// --- DO SOMETHING WITH ASSETS HERE ---
// e.g., swap on a DEX, liquidate a position, etc.
// For this example, we just move them to borrower's account temporarily
primary_fungible_store::deposit(borrower_addr, loaned_assets);

// 2. Calculate Repayment (Principal + Fee)
// The receipt stores the fee requirement.
// If fee is 30 bps, fee amount = 10,000 * 30 / 10,000 = 30
let total_repayment = 10_030;

// 3. Prepare Repayment Assets
let repayment_assets = primary_fungible_store::withdraw(borrower, fa_metadata, total_repayment);

// 4. Repay (Consumes the Receipt)
flash_loan::repay(vault_obj, repayment_assets, receipt);
```

## 🛠️ Build & Test

### Dependencies
Ensure your `Move.toml` points to the correct Cedra Network repository:
```toml
[dependencies.CedraFramework]
git = "https://github.com/cedra-labs/cedra-network.git"
rev = "main"
subdir = "cedra-move/framework/cedra-framework"
```

### Commands

**Build:**
```bash
cedra move build --named-addresses hot_potato=default
```

**Test:**
```bash
cedra move test
```

**Publish:**
```bash
cedra move publish --named-addresses hot_potato=default
```

## ✅ Verification Report

### Unit Tests
Running `cedra move test` passed on 2026-02-02.

| Test Case | Result |
| --- | --- |
| `test_flash_loan_success` | **PASSED** |
| `test_insufficient_repayment` | **PASSED** |

### Live Verification (Devnet)
Verified end-to-end functionality on Cedra Devnet using the `demo` module.

| Step | Action | Tx Hash |
| --- | --- | --- |
| **1. Init Demo** | Create Coin (HPT) & Vault (10 bps fee) | [0xa5c7...d54f](https://cedrascan.com/txn/0xa5c74c7a96827d16fec1e47f288a3a9a0f29e6084ad435d37289578df367d54f?network=devnet) |
| **2. Flash Loan** | Borrow 1000 HPT, Repay 1001 HPT | [0x725c...ca90](https://cedrascan.com/txn/0x725cec3e3b63fd6e925a5e6d6116d769c1d839ceb029a78938dd0ead5b34ca90?network=devnet) |
