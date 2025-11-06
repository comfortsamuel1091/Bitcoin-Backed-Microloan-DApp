# 🏦 Bitcoin-Backed Microloan DApp

A decentralized finance (DeFi) application built on Stacks that allows users to lock Bitcoin (STX) as collateral to obtain microloans in fungible tokens. Perfect for quick liquidity without selling your Bitcoin holdings! 💰

## 🌟 Features

- 🔒 **Collateral-Based Lending**: Lock STX tokens as collateral
- 💸 **Instant Loans**: Get microloan tokens immediately upon collateral deposit
- 📈 **Interest Tracking**: Automatic interest calculation and tracking
- ⏰ **Repayment Deadlines**: Time-bound loan repayment system
- ⚡ **Liquidation Protection**: Automatic liquidation for expired loans
- 📊 **Real-time Stats**: Track loan status and contract statistics

## 🚀 Quick Start

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Deploy the contract using Clarinet

```bash
clarinet deploy
```

## 📋 Contract Functions

### 🔧 Admin Functions
- `initialize-contract()` - Initialize the contract and mint tokens
- `update-btc-price(new-price)` - Update BTC price oracle
- `emergency-withdraw()` - Emergency fund withdrawal (admin only)

### 💰 Loan Functions
- `request-loan(collateral-amount)` - Request a loan with STX collateral
- `repay-loan()` - Repay your active loan
- `liquidate-loan(borrower)` - Liquidate an expired loan

### 📊 Read-Only Functions
- `get-loan-info(borrower)` - Get detailed loan information
- `get-loan-status(borrower)` - Get current loan status
- `get-contract-stats()` - Get overall contract statistics
- `calculate-max-loan(collateral)` - Calculate maximum loan for collateral amount

## 💡 How It Works

1. **🏦 Deposit Collateral**: Users deposit STX tokens as collateral (150% collateralization ratio)
2. **💳 Receive Loan**: Instantly receive microloan tokens based on collateral value
3. **📅 Repayment Period**: 144 blocks (~24 hours) to repay loan + 5% interest
4. **🔄 Repay or Liquidate**: Repay to get collateral back, or face liquidation after deadline

## 📈 Key Parameters

- **Collateral Ratio**: 150% (over-collateralized)
- **Interest Rate**: 5% of loan amount
- **Loan Duration**: 144 blocks (~24 hours)
- **Liquidation Penalty**: 10% of collateral

## 🛡️ Security Features

- Over-collateralization ensures loan security
- Time-locked repayment system
- Automatic liquidation for expired loans
- Admin controls for emergency situations

## 📝 Usage Example

```clarity
;; Request a loan with 1000 STX as collateral
(contract-call? .Bitcoin-Backed-Microloan-DApp request-loan u1000)

;; Check loan status
(contract-call? .Bitcoin-Backed-Microloan-DApp get-loan-status tx-sender)

;; Repay the loan
(contract-call? .Bitcoin-Backed-Microloan-DApp repay-loan)
```

## ⚠️ Important Notes

- Always repay loans before the deadline to avoid liquidation
- Monitor your loan status regularly
- Ensure sufficient token balance for repayment
- BTC price updates affect loan calculations

## 🤝 Contributing

Feel free to submit issues and enhancement requests! 

## 📄 License

This project is open source and available under the MIT License.

---

**⚡ Built with Clarity on Stacks - Bringing Bitcoin DeFi to life! ⚡**
```

