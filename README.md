# 🌾 Smart Crop Insurance Contract

> Automated crop insurance payouts powered by blockchain technology 🚀

## Overview

This smart contract implements an automated crop insurance system that helps protect farmers against adverse weather conditions. When rainfall exceeds predefined thresholds, the contract automatically triggers payouts to affected farmers.

## 🎯 Features

- 📝 Purchase insurance policies with customizable coverage
- 🌧️ Oracle-powered weather data integration  
- ⚡ Automatic claim processing
- 💸 Instant payouts when conditions are met

## 📋 Contract Functions

### For Farmers
- `purchase-insurance`: Buy a new insurance policy
- `claim-insurance`: Submit a claim when conditions are met
- `get-policy`: View policy details

### For Administrators
- `set-oracle-address`: Update the oracle provider
- `submit-weather-data`: Submit weather measurements (oracle only)

## 🚀 Getting Started

1. Deploy the contract to the Stacks blockchain
2. Set up the oracle address for weather data
3. Farmers can purchase insurance by specifying:
   - Premium amount (minimum 1M microSTX)
   - Rainfall threshold for automatic payouts

## ⚙️ Technical Details

- Policy duration: 24 hours (144 blocks)
- Payout multiplier: 3x premium amount
- Weather data submitted per block
```

