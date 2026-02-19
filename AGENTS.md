# AGENTS.md - Starknet Perpetual Protocol

## What is this?

**Starknet Perpetual** is a decentralized perpetual futures trading protocol on Starknet (Cairo 2.x):

- Trade synthetic assets (BTC-PERP, ETH-PERP) with leverage, no expiration
- Vault integration (ERC4626) for yield-bearing collateral
- Oracle-based pricing with funding rate mechanisms

**Full Documentation:** [docs/spec.md](docs/spec.md)

## Architecture

Component-based design in [`core.cairo`](workspace/apps/perpetuals/contracts/src/core/core.cairo):

```text
Core Contract
├── Assets Component      - Asset management, prices, funding
├── Positions Component   - Position tracking, balances
├── Deposit Component     - Two-phase deposit flow
├── Vault Component       - Protocol vault integration (deposit/withdraw vault shares)
├── Request Approvals     - User-signed requests
└── Access Control        - Operator, Roles, Pausable, Upgrades
```

Components expose public interfaces (`#[abi(embed_v0)]`) and internal traits. See [`core.cairo`](workspace/apps/perpetuals/contracts/src/core/core.cairo) for implementation patterns.

**Vault Integration:** Users can deposit collateral into `ProtocolVault` (ERC4626) to receive vault shares. The vault's total assets are calculated from the vault position's Total Value. Shares are traded as collateral within the perpetuals system, earning yield while used for trading.

```text
Protocol Vault (workspace/vault/src/protocol_vault.cairo)
└── ERC4626 Vault         - Yield-bearing collateral via vault shares
                            • Implements ERC4626 standard
                            • Total Assets is the perps vault position TV ( Total Value)
                            • Only perps contract can deposit/redeem
```

## Critical: TV/TR Risk Management

**Most important concept in the codebase.** Every position change must maintain position health.

**Formulas:**

- Total Value (TV) = Collateral + Σ(Asset Values)
- Total Risk (TR) = Σ(|Asset Value| × Risk Factor)

**Position States:**

- **Healthy**: `TV ≥ TR` ✅ Position is safe
- **Liquidatable**: `0 < TV < TR` ⚠️ Can be liquidated
- **Deleveragable**: `TV < 0` 🔴 Negative value, insurance fund intervenes

See [`value_risk_calculator.cairo`](workspace/apps/perpetuals/contracts/src/core/value_risk_calculator.cairo) for the implementation.

**Risk Factors:** Increase with position size (tiered) to prevent concentration risk.

**Healthier Validation:** Position changes must be "healthy or healthier" - if unhealthy after change, must improve TV/TR ratio AND reduce TR.

**Funding Mechanism:** Positions pay/receive funding to anchor synthetic prices to spot: `funding_delta = (old_index - new_index) × balance`

## Development Patterns

### Position Modification Pattern

All position changes follow: validate (pause/nonce/assets) → signature check → build diff → TV/TR validation → apply → emit event. See functions in `core.cairo` like `withdraw()`, `trade()`, `liquidate()`.

### Request-Execute Pattern

User operations use two phases to prevent frontrunning:

1. User signs request → registers on-chain (`withdraw_request()`, `transfer_request()`)
2. Operator executes with signature validation (`withdraw()`, `transfer()`)

### Enrichment Pipeline

Position diffs get enriched with prices and risk factors for TV/TR validation:

- `PositionDiff` → `enrich_asset()` → `AssetEnrichedPositionDiff` → `enrich_collateral()` → `PositionDiffEnriched`
- **Performance note:** Enrichment is expensive (especially funding). Only use when validating position health.

## Development Workflow

⚠️ **CRITICAL: Always run `scarb test` after any changes**

Before committing or considering work complete:

1. Run `scarb build` and `scarb --release build` to ensure code compiles in both modes
2. Run `scarb fmt -w` to format the code before testing and reviewing
3. Run `scarb test` to verify all tests pass
4. For position logic changes, run specific test suites:
   - `scarb test unit_tests` - Quick feedback
   - `scarb test flow_tests` - Full integration validation
   - `scarb test test_name` - Target specific functionality
5. Update the relevant sections in the [docs/spec.md](docs/spec.md)

**Running specific tests:** Use `snforge test <test_prefix>` instead of `scarb test` when targeting specific tests. It matches tests whose name starts with the given prefix and is significantly faster (skips recompilation of unrelated packages).

**Task timing:** When executing a plan with to-dos, track and report the time taken for each to-do and the total elapsed time. This helps evaluate task complexity.

## Testing

```text
src/tests/
├── unit_tests/              - Component-level tests
├── flow_tests/              - Integration tests
│   └── multi_trade_regression_tests.cairo - Regression suite
└── performance_tests/       - Gas optimization
```

**Run tests:**

```bash
scarb build                        # Compile (dev)
scarb --release build              # Compile (release)
scarb fmt -w                       # Format code
scarb test                         # All tests
snforge test test_my_function      # Fast, targeted test run
```

**When changing position logic:** Test TV/TR edge cases, funding application, and add regression tests.

## Quick Reference

### File Structure

```text
workspace/apps/perpetuals/contracts/src/core/
├── core.cairo                  - Main contract
├── interface.cairo             - ICore public interface
├── value_risk_calculator.cairo - TV/TR calculations ⭐
├── components/                 - Modular components (assets, positions, vault, etc.)
└── types/                      - Core types

workspace/vault/src/
└── protocol_vault.cairo        - ERC4626 vault for yield-bearing collateral
```

### Commands

```bash
scarb build              # Compile (dev)
scarb --release build    # Compile (release)
scarb test               # Run tests
```

### Key Constants

- `FEE_POSITION`: `PositionId { value: 0 }`
- `INSURANCE_FUND_POSITION`: `PositionId { value: 1 }`
- `EPSILON`: `1` (10^-6 USD for fair deleverage checks)

## Security

### Critical Invariants

1. Positions must be healthy or healthier after changes
2. Orders cannot exceed signed amounts (fulfillment tracking)
3. Funding must be applied before position updates
4. Prices must be validated and recent

### High-Risk Areas

Changes to these require extensive testing:

- `value_risk_calculator.cairo` - Core risk logic
- Funding application in positions component
- Risk factor calculations in assets component
- `protocol_vault.cairo` - Vault integration and ERC4626 hooks

### Operator Role

Executes signed user intents, processes deposits, performs liquidations, updates prices/funding. **Cannot steal funds** - only executes pre-signed user intents.

## Resources

### Cairo & Starknet Ecosystem

- **Cairo Book**: [https://www.starknet.io/cairo-book/](https://www.starknet.io/cairo-book/) - Official Cairo language guide and syntax reference
- **Starknet Foundry (snforge)**: [https://foundry-rs.github.io/starknet-foundry/](https://foundry-rs.github.io/starknet-foundry/) - Testing framework for Starknet smart contracts
- **Scarb**: [https://docs.swmansion.com/scarb/](https://docs.swmansion.com/scarb/) - Build toolchain and package manager for Cairo
- **Openzeppelin Cairo Contracts**: [https://docs.openzeppelin.com/contracts-cairo](https://docs.openzeppelin.com/contracts-cairo)

### Project Documentation

- **Protocol Spec**: [docs/spec.md](docs/spec.md) - Detailed technical specification

---

**Cairo:** 2.x (Edition 2024_07) | **Starknet:** 2.15.1 | **Last Updated:** 2025-01-15
