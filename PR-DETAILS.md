# Policy Risk Assessment and Premium Adjustment System

## Overview
Enhanced the Smart Crop Insurance contract with a comprehensive risk assessment system that enables dynamic premium calculations based on regional risk factors, historical data, and environmental conditions. This feature provides more accurate pricing by incorporating real-world risk indicators while maintaining the existing contract functionality.

## Technical Implementation

### New Data Structures
- **risk-assessments**: Maps region-crop combinations to risk levels (1-4), historical claims, success rates, and assessment periods
- **risk-factors**: Tracks regional environmental factors including weather volatility, climate trends, soil quality, and water availability  
- **Risk level constants**: LOW (1), MEDIUM (2), HIGH (3), EXTREME (4) with corresponding premium multipliers (80%, 100%, 130%, 160%)

### Key Functions Added
- `update-risk-assessment`: Owner-only function to set risk data for region/crop combinations
- `update-risk-factors`: Owner-only function to update environmental risk factors by region
- `calculate-risk-adjusted-premium`: Public function for dynamic premium calculation with risk factors
- `get-risk-assessment`, `get-risk-factors`, `get-risk-profile`: Read-only functions for risk data retrieval

### Premium Calculation Algorithm  
1. **Base Premium**: Standard 5% of coverage + duration factor
2. **Risk Level Multiplier**: 80% (low) to 160% (extreme risk)
3. **Environmental Adjustments**: Weather volatility (+50% max), climate trends (+30% max), soil quality discount (-20% max), water availability discount (-25% max)
4. **Composite Risk Score**: 0-100 scale combining all factors with historical performance data

## Testing & Validation
- ✅ Contract passes clarinet check (syntax validation)
- ✅ Comprehensive test suite with 25+ new test cases covering all risk assessment functions
- ✅ Integration tests verify compatibility with existing policy and claims workflows
- ✅ Error handling validation for authorization, input bounds, and edge cases
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Clarity v3 compliant with proper error constants and data type safety

## Value Proposition
- **Actuarial Accuracy**: Premiums now reflect real risk through data-driven assessment
- **Regional Adaptability**: Different pricing for varying geographic and environmental conditions
- **Historical Learning**: System improves over time by incorporating claims history
- **Operational Flexibility**: Risk parameters can be updated as conditions change
- **Farmer Benefits**: Lower premiums for low-risk regions and crops
- **Insurer Protection**: Higher premiums for high-risk scenarios ensure sustainability
