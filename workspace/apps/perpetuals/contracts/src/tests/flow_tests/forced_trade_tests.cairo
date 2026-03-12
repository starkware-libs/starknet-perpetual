use core::num::traits::WideMul;
use perpetuals::core::components::snip::SNIP12MetadataImpl;
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils::constants::MAX_U128;
use starkware_utils_testing::test_utils::TokenTrait;


#[test]
fn test_successful_forced_trade_request() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Approve user_a for premium cost.
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.into() * quantum.into();
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Add and activate synthetic asset with lower price for simpler math
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 0,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000_u128);
    let synthetic_id = synthetic_info.asset_id;

    // Test:
    // user_a buys 10 synthetic, user_b sells 10 synthetic
    // Price is 1000, so 10 synthetic = 10000 collateral
    state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: 10,
            order_a_quote_amount: -10000,
            order_b_base_amount: -10,
            order_b_quote_amount: 10000,
            fee_amount: 0,
        );
}

#[test]
fn test_successful_forced_trade_after_timelock() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Add and activate synthetic asset
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 0,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000);

    // Fund users with enough collateral for trades
    state.facade.process_deposit(state.facade.deposit(user_a.account, user_a.position_id, 50000));
    state.facade.process_deposit(state.facade.deposit(user_b.account, user_b.position_id, 50000));

    let synthetic_id = synthetic_info.asset_id;

    // Fund user_a for premium cost
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state.facade.token_state.fund(recipient: user_a.account.address, amount: USER_INIT_BALANCE);
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    let (order_a, order_b) = state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: -10,
            order_a_quote_amount: 10000,
            order_b_base_amount: 10,
            order_b_quote_amount: -10000,
            fee_amount: 0,
        );

    // Wait for timelock
    state.facade.advance_time(FORCED_ACTION_TIMELOCK);

    // Test: Execute forced trade after timelock
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: user_b.account);
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_forced_trade_user_after_operator_executed() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Add and activate synthetic asset with lower price
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: MAX_U128,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000_u128);

    // Fund users with enough collateral
    state
        .facade
        .process_deposit(state.facade.deposit(user_a.account, user_a.position_id, 50000_u64));
    state
        .facade
        .process_deposit(state.facade.deposit(user_b.account, user_b.position_id, 50000_u64));

    let synthetic_id = synthetic_info.asset_id;

    // Fund user_a for premium cost
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state.facade.token_state.fund(recipient: user_a.account.address, amount: USER_INIT_BALANCE);
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    let (order_a, order_b) = state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: -10,
            order_a_quote_amount: 10000,
            order_b_base_amount: 10,
            order_b_quote_amount: -10000,
            fee_amount: 0,
        );

    // Operator executes forced trade first (allowed before timelock).
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: state.facade.operator);

    // After timelock the user tries to execute the same forced trade again.
    state.facade.advance_time(FORCED_ACTION_TIMELOCK);
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: user_b.account);
}

#[test]
fn test_successful_forced_trade_by_operator_before_timelock() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Add and activate synthetic asset with lower price
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: MAX_U128,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000_u128);

    // Fund users with enough collateral
    state
        .facade
        .process_deposit(state.facade.deposit(user_a.account, user_a.position_id, 50000_u64));
    state
        .facade
        .process_deposit(state.facade.deposit(user_b.account, user_b.position_id, 50000_u64));

    let synthetic_id = synthetic_info.asset_id;

    // Fund user_a for premium cost
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state.facade.token_state.fund(recipient: user_a.account.address, amount: USER_INIT_BALANCE);
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced trade - user_a sells 10 synthetic, user_b buys 10 synthetic
    // Price is 1000, so 10 synthetic = 10000 collateral
    let (order_a, order_b) = state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: -10,
            order_a_quote_amount: 10000,
            order_b_base_amount: 10,
            order_b_quote_amount: -10000,
            fee_amount: 0,
        );

    // Test: Operator can execute before timelock
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: state.facade.operator);
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_forced_trade_operator_after_user_executed() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Add and activate synthetic asset with lower price
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: MAX_U128,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000_u128);

    // Fund users with enough collateral
    state
        .facade
        .process_deposit(state.facade.deposit(user_a.account, user_a.position_id, 50000_u64));
    state
        .facade
        .process_deposit(state.facade.deposit(user_b.account, user_b.position_id, 50000_u64));

    let synthetic_id = synthetic_info.asset_id;

    // Fund user_a for premium cost
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state.facade.token_state.fund(recipient: user_a.account.address, amount: USER_INIT_BALANCE);
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced trade - user_a sells 10 synthetic, user_b buys 10 synthetic
    // Price is 1000, so 10 synthetic = 10000 collateral
    let (order_a, order_b) = state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: -10,
            order_a_quote_amount: 10000,
            order_b_base_amount: 10,
            order_b_quote_amount: -10000,
            fee_amount: 0,
        );

    // Non-operator user executes forced trade after timelock.
    state.facade.advance_time(FORCED_ACTION_TIMELOCK);
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: user_b.account);

    // Operator tries to execute the same forced trade again.
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: state.facade.operator);
}

#[test]
#[should_panic(expected: 'FORCED_WAIT_REQUIRED')]
fn test_forced_trade_before_timelock_non_operator() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Add and activate synthetic asset with lower price
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: MAX_U128,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000_u128);

    // Fund users with enough collateral
    state
        .facade
        .process_deposit(state.facade.deposit(user_a.account, user_a.position_id, 50000_u64));
    state
        .facade
        .process_deposit(state.facade.deposit(user_b.account, user_b.position_id, 50000_u64));

    let synthetic_id = synthetic_info.asset_id;

    // Fund user_a for premium cost
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state.facade.token_state.fund(recipient: user_a.account.address, amount: USER_INIT_BALANCE);
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    let (order_a, order_b) = state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: -10,
            order_a_quote_amount: 10000,
            order_b_base_amount: 10,
            order_b_quote_amount: -10000,
            fee_amount: 0,
        );

    // Test: Try to execute before timelock (non-operator)
    state.facade.forced_trade(user_a, user_b, order_a, order_b, caller: user_b.account);
}

#[test]
#[should_panic(expected: 'INSUFFICIENT_APPROVAL')]
fn test_forced_trade_request_insufficient_premium() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Add and activate synthetic asset with lower price
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: MAX_U128,
        },
        oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_info, 1000_u128);

    // Test insufficient approval instead of insufficient balance
    // The contract checks approval first, so this will fail with INSUFFICIENT_APPROVAL
    let quantum = state.facade.collateral_quantum;
    let premium_amount = PREMIUM_COST.wide_mul(quantum);
    let insufficient_approval = (PREMIUM_COST - 1).wide_mul(quantum);
    // Fund user with enough balance
    state.facade.token_state.fund(recipient: user_a.account.address, amount: premium_amount);
    // Approve insufficient amount (less than required premium)
    state
        .facade
        .token_state
        .approve(
            owner: user_a.account.address,
            spender: state.facade.perpetuals_contract,
            amount: insufficient_approval,
        );

    let synthetic_id = synthetic_info.asset_id;

    // Test:
    // user_a buys 10 synthetic, user_b sells 10 synthetic
    // Price is 1000, so 10 synthetic = 10000 collateral
    state
        .facade
        .forced_trade_request(
            user_a: user_a,
            user_b: user_b,
            base_asset_id: synthetic_id,
            order_a_base_amount: 10,
            order_a_quote_amount: -10000,
            order_b_base_amount: -10,
            order_b_quote_amount: 10000,
            fee_amount: 0,
        );
}
