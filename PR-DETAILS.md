# Smart Crop Insurance Contract

## Overview
Comprehensive decentralized crop insurance system that provides automated weather-based payouts to farmers. This smart contract enables farmers to purchase insurance policies for their crops and receive automatic compensation when weather conditions fall outside normal parameters, reducing risk and providing financial security.

## Technical Implementation
### Key Functions and Data Structures Added

#### Core Data Structures
- **Policy Management**: Complete policy lifecycle with farmer details, coverage amounts, premium calculations, and regional tracking
- **Weather Claims Processing**: Oracle-driven weather data submission with automated payout calculations
- **Regional Statistics**: Comprehensive tracking of policies, claims, and payouts by geographic region
- **Multi-Account Support**: Full support for multiple farmers, policies, and oracle management

#### Smart Contract Features
- **Policy Creation**: `create-policy` - Farmers can purchase crop insurance with customizable coverage, duration, and crop types
- **Weather-Based Claims**: `submit-weather-claim` - Oracle-submitted weather data triggers automatic payouts based on rainfall and temperature thresholds
- **Policy Renewal**: `renew-policy` - Existing policies can be extended with additional premium payments
- **Oracle Management**: `set-oracle` - Contract owner can designate trusted weather data providers
- **Comprehensive Analytics**: Multiple read-only functions for policy tracking, regional statistics, and payout eligibility checking

#### Advanced Logic
- **Dynamic Premium Calculation**: 5% of coverage amount plus duration-based fees
- **Weather Threshold System**: Payouts trigger when rainfall < 20% normal or temperature > 110% normal
- **Graduated Payout System**: Payout amounts scale with severity of weather conditions
- **Policy Status Tracking**: Active, expired, and claimed status management
- **Regional Aggregation**: Statistical tracking by geographic regions

## Testing & Validation
- ✅ Contract passes Clarity v3 syntax validation
- ✅ Comprehensive test suite with 20+ test cases covering all functionality
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Clarity v3 compliant with proper error handling and type safety
- ✅ Full coverage of policy creation, weather claims, renewals, and edge cases
- ✅ Oracle authorization and access control testing
- ✅ Regional statistics and multi-farmer scenario testing
