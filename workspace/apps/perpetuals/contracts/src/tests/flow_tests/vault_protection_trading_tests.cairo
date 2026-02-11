use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils::constants::MAX_U128;
use super::perps_tests_facade::PerpsTestsFacadeTrait;


#[test]
#[should_panic(
    expected: "Vault Protection Limit Exceeded, tv_at_last_check: 10000, tv_after_operation: 5000, max_allowed_loss : 500",
)]
fn test_trading_loss_activates_protection() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let trader_user = state.new_user_with_position();

    // 1. Setup Vault
    // Deposit 100k USDC
    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 10000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);

    // 2. Setup Trader
    // Deposit 100k USDC
    state
        .facade
        .process_deposit(
            state.facade.deposit(trader_user.account, trader_user.position_id, 10000_u64),
        );

    // 3. Establish Baseline
    // Advance 24h+ to allow baseline check
    state.facade.advance_time(86401);
    state.facade.funding_tick(array![].span());

    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.price_tick(@synthetic_info, 100);

    // 4. Executing Trade
    // Trader Longs 100 BTC, Vault Shorts 100 BTC (via matching)
    let order_trader = state
        .facade
        .create_order(
            user: trader_user,
            base_amount: 100,
            base_asset_id: asset_id,
            quote_amount: -10000,
            fee_amount: 0,
        );

    let order_vault = state
        .facade
        .create_order(
            user: vault_user,
            base_amount: -100,
            base_asset_id: asset_id,
            quote_amount: 10000,
            fee_amount: 0,
        );

    state.facade.trade(order_trader, order_vault, 100, -10000, 0, 0);

    // now the opposite, but price is now 150 per BTC (short vault make loss of 100 * 50 = 5000)
    let order_trader_inverse = state
        .facade
        .create_order(
            user: trader_user,
            base_amount: -100,
            base_asset_id: asset_id,
            quote_amount: 15000,
            fee_amount: 0,
        );

    let order_vault_inverse = state
        .facade
        .create_order(
            user: vault_user,
            base_amount: 100,
            base_asset_id: asset_id,
            quote_amount: -15000,
            fee_amount: 0,
        );

    state.facade.trade(order_trader_inverse, order_vault_inverse, -100, 15000, 0, 0);
}

#[test]
fn test_trading_loss_within_limit() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let trader_user = state.new_user_with_position();

    // 1. Setup Vault
    // Deposit 100k USDC
    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 10000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);

    // 2. Setup Trader
    // Deposit 100k USDC
    state
        .facade
        .process_deposit(
            state.facade.deposit(trader_user.account, trader_user.position_id, 10000_u64),
        );

    // 3. Establish Baseline
    // Advance 24h+ to allow baseline check
    state.facade.advance_time(86401);
    state.facade.funding_tick(array![].span());

    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.price_tick(@synthetic_info, 100);

    // 4. Executing Trade
    // Trader Longs 100 BTC, Vault Shorts 100 BTC (via matching)
    let order_trader = state
        .facade
        .create_order(
            user: trader_user,
            base_amount: 100,
            base_asset_id: asset_id,
            quote_amount: -10000,
            fee_amount: 0,
        );

    let order_vault = state
        .facade
        .create_order(
            user: vault_user,
            base_amount: -100,
            base_asset_id: asset_id,
            quote_amount: 10000,
            fee_amount: 0,
        );

    state.facade.trade(order_trader, order_vault, 100, -10000, 0, 0);

    // now the opposite, but price is now 150 per BTC (short vault make loss of 10 * 50 = 500)
    let order_trader_inverse = state
        .facade
        .create_order(
            user: trader_user,
            base_amount: -100,
            base_asset_id: asset_id,
            quote_amount: 10100,
            fee_amount: 0,
        );

    let order_vault_inverse = state
        .facade
        .create_order(
            user: vault_user,
            base_amount: 100,
            base_asset_id: asset_id,
            quote_amount: -10100,
            fee_amount: 0,
        );

    state.facade.trade(order_trader_inverse, order_vault_inverse, -100, 10100, 0, 0);
}