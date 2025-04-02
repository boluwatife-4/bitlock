# BitLock USDA Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A decentralized finance protocol enabling Bitcoin-backed stablecoin issuance on Stacks L2. Implements secure vault management, collateralized debt positions, and decentralized governance mechanisms compliant with Bitcoin's security model.

## Table of Contents

- [BitLock USDA Protocol](#bitlock-usda-protocol)
	- [Table of Contents](#table-of-contents)
	- [Key Features](#key-features)
		- [Bitcoin-Collateralized Vaults](#bitcoin-collateralized-vaults)
		- [Debt Management System](#debt-management-system)
		- [Risk Management](#risk-management)
		- [Governance](#governance)
	- [Technical Specifications](#technical-specifications)
		- [Contract Constants](#contract-constants)
		- [Data Model](#data-model)
		- [Token Standards](#token-standards)
	- [Core Mechanisms](#core-mechanisms)
		- [Vault Operations](#vault-operations)
		- [Redemption Mechanism](#redemption-mechanism)
	- [Usage Examples](#usage-examples)
		- [Create Vault](#create-vault)
		- [Mint Stablecoins](#mint-stablecoins)
		- [Repay Debt](#repay-debt)
		- [Liquidate Vault](#liquidate-vault)
	- [Security Considerations](#security-considerations)
		- [Oracle Reliability](#oracle-reliability)
		- [Liquidation Protection](#liquidation-protection)
		- [System Safeguards](#system-safeguards)
	- [Governance](#governance-1)
		- [Adjustable Parameters](#adjustable-parameters)
		- [Governance Process](#governance-process)

## Key Features

### Bitcoin-Collateralized Vaults

- Create vaults using sBTC (wrapped Bitcoin)
- Minimum 120% collateralization ratio
- Real-time price feeds via decentralized oracles

### Debt Management System

- Mint USDA stablecoins against BTC collateral
- Dynamic stability fee (currently 1% annual)
- Global debt ceiling enforcement

### Risk Management

- 150% liquidation threshold
- 13% liquidation penalty
- System-wide collateralization monitoring

### Governance

- Parameter adjustments via DAO voting
- Emergency pause functionality
- Protocol fee configuration (0.5% default)

## Technical Specifications

### Contract Constants

| Constant               | Value | Description           |
| ---------------------- | ----- | --------------------- |
| `ERR_UNAUTHORIZED`     | u100  | Authorization failure |
| `LIQUIDATION_RATIO`    | 1500  | 150% basis points     |
| `MIN_COLLATERAL_RATIO` | 1200  | 120% basis points     |

### Data Model

- **Vault Structure**:

  ```clarity
  {
    owner: principal,
    collateral: uint,  // Satoshis
    debt: uint,        // Micro-USDA
    last-update: uint, // Block height
    liquidated: bool
  }
  ```

- **System Metrics**:
  - Total debt ceiling: 10,000,000 USDA
  - Real-time collateralization ratio tracking

### Token Standards

- SIP-010 fungible token (USDA)
- NFT-based vault ownership

## Core Mechanisms

### Vault Operations

1. **Collateralization Check**:
   ```
   Collateral Ratio = (BTC Collateral × Price) / Debt × 10000
   ```
2. **Stability Fee Accumulation**:
   ```clarity
   debt += debt × (block_height - last_update) × stability_fee / 10000
   ```
3. **Liquidation Process**:
   - Triggered at <150% ratio
   - 13% penalty on debt
   - Collateral auction mechanism

### Redemption Mechanism

- Direct USDA → BTC conversion
- 0.5% protocol fee
- Oracle-based pricing

## Usage Examples

### Create Vault

```clarity
(create-vault u1000000)  // 0.01 BTC collateral
```

### Mint Stablecoins

```clarity
(mint-stablecoin vault-id u5000000)  // Mint 5 USDA
```

### Repay Debt

```clarity
(repay-debt vault-id u1000000)  // Repay 1 USDA
```

### Liquidate Vault

```clarity
(liquidate-vault vault-id)
```

## Security Considerations

### Oracle Reliability

- Uses decentralized price feeds
- Fallback mechanism for price updates
- Maximum data staleness checks

### Liquidation Protection

- Multiple collateral ratio thresholds
- Time-delayed liquidation triggers
- Penalty-based economic security

### System Safeguards

- Emergency pause functionality
- Debt ceiling enforcement
- Collateral withdrawal limits

## Governance

### Adjustable Parameters

| Parameter           | Update Function              | Range      |
| ------------------- | ---------------------------- | ---------- |
| Stability Fee       | `update-stability-fee`       | 0-500bps   |
| Liquidation Penalty | `update-liquidation-penalty` | 100-200bps |
| Protocol Fee        | `update-protocol-fee`        | 0-100bps   |

### Governance Process

1. DAO proposal submission
2. Voting period (48h)
3. Parameter update execution
4. Time-lock enforcement
