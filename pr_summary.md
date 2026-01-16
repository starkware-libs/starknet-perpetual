# PR Summary: Refactor Collateral Risk Calculation to Net Value Model

## Overview
This PR introduces a significant change to how Total Value (TV) and Total Risk (TR) are calculated for collateral assets, specifically Vault Shares. The logic shifts from a gross value/risk model to a "Net Value" (or Haircut) model.

## Key Changes

### Core Logic (`value_risk_calculator.cairo`)
- **New Calculation Standard**:
  - **Previous Behavior**: Collateral assets contributed their full market value to Total Value, and their calculated risk to Total Risk.
  - **New Behavior**: Collateral assets now contribute their **Risk-Adjusted Value** (Market Value - Risk) to Total Value. Their contribution to Total Risk is now **0**.
- **Impact**: This effectively treats collateral risk as a deduction from equity (haircut) rather than a liability component.

### Components
- **Vaults (`vaults_contract.cairo`)**:
  - Updated panic messages in `liquidate_vault_shares` and `redeem_from_vault` to reference `value_of_shares_sold` as the risk-adjusted value.
  - Removed `risk_of_shares_sold` from panic data as it is now internalized in the value.

### Testing (`procotol_vault_redeem_tests.cairo`, `vault_share_tv_tr_impact_tests.cairo`)
- **Assertion Updates**: All tests involving vault shares were updated to assert the new TV/TR values:
  - TV is lower (reduced by the risk factor).
  - TR is lower (collateral risk removed).
- **Scenario Hardening**:
  - Modified liquidation tests (`test_liquidate_vault_shares_fails_when_worsening_tv_tr`, `test_liquidate_vault_shares_succeeds_when_improving_tv_tr`) to test scenarios where the user has **Positive Total Value** (Solvent) but is still **Unhealthy** (TV < TR).
  - Previously, these tests relied on Negative TV scenarios. The new tests confirm that liquidation logic holds even when the user is solvent.
- **Error Message Alignment**: Updated `should_panic` expectations to match the new "Illegal transition" format.

## Motivation
This change aligns the protocol's risk assessment for collateral with standard "haircut" models, simplifying the Total Risk metric to focus primarily on position liabilities while treating collateral quality as a valuation adjustment.
