use core::num::traits::{Bounded, WideMul};
use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use perpetuals::core::components::snip::SNIP12MetadataImpl;
use perpetuals::core::types::order::ForcedRedeemFromVault;
use perpetuals::tests::constants::*;
use perpetuals::tests::event_test_utils::{
    assert_forced_redeem_from_vault_event_with_expected,
    assert_forced_redeem_from_vault_request_event_with_expected,
};
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use perpetuals::tests::test_utils::assert_with_error;
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils_testing::test_utils::TokenTrait;
use super::perps_tests_facade::PerpsTestsFacadeTrait;


pub const MAX_U128: u128 = Bounded::<u128>::MAX;

#[test]
fn test_redeem_from_protocol_vault_redeem_to_same_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    let perps_usdc_balance_before_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let redeeming_user_usdc_balance_before_redeem = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);

    let redeeming_user_vault_share_balance_before_redeem = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);

    let vault_usdc_balance_before_redeem = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    let value_of_shares: u64 = 399;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );
    //     explicity check invariants
    // 1. perps USDC balance must not change

    let perps_usdc_balance_after_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    assert_with_error(
        perps_usdc_balance_before_vault_interaction == perps_usdc_balance_after_vault_interaction,
        format!(
            "perps usdc balance changed after vault interaction, before: {}, after: {}",
            perps_usdc_balance_before_vault_interaction,
            perps_usdc_balance_after_vault_interaction,
        ),
    );
    // 2. redeeming user position balance must increase by 399 USDC
    let redeeming_user_usdc_balance_after_vault_interaction = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);

    assert_with_error(
        redeeming_user_usdc_balance_after_vault_interaction == redeeming_user_usdc_balance_before_redeem
            + value_of_shares.into(),
        format!(
            "redeeming user collateral balance did not increase by {:?}, before: {:?}, after: {:?}",
            value_of_shares,
            redeeming_user_usdc_balance_before_redeem,
            redeeming_user_usdc_balance_after_vault_interaction,
        ),
    );

    let redeeming_user_vault_share_balance_after_redeem = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);
    // 3. redeeming user vault share balance must decrease by redeemed amount
    assert_with_error(
        redeeming_user_vault_share_balance_before_redeem
            - 400_i64.into() == redeeming_user_vault_share_balance_after_redeem,
        format!(
            "depositing user vault share balance did not decrease, before: {:?}, after: {:?}",
            redeeming_user_vault_share_balance_before_redeem,
            redeeming_user_vault_share_balance_after_redeem,
        ),
    );
    //4. vault usdc balance must decrease by 399
    let vault_usdc_balance_after_redeem = state
        .facade
        .get_position_collateral_balance(vault_user.position_id);

    assert_with_error(
        vault_usdc_balance_after_redeem == vault_usdc_balance_before_redeem - 399_i64.into(),
        format!(
            "vault usdc balance did not decrease by 399, before: {:?}, after: {:?}",
            vault_usdc_balance_before_redeem,
            vault_usdc_balance_after_redeem,
        ),
    );
}

#[test]
fn test_redeem_from_protocol_vault_redeem_to_same_position_with_9pct_premium() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    let perps_usdc_balance_before_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let redeeming_user_usdc_balance_before_redeem = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);

    let redeeming_user_vault_share_balance_before_redeem = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);

    let vault_usdc_balance_before_redeem = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    const value_of_shares: u64 = 436;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );
    //     explicity check invariants
    // 1. perps USDC balance must not change

    let perps_usdc_balance_after_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    assert_with_error(
        perps_usdc_balance_before_vault_interaction == perps_usdc_balance_after_vault_interaction,
        format!(
            "perps usdc balance changed after vault interaction, before: {}, after: {}",
            perps_usdc_balance_before_vault_interaction,
            perps_usdc_balance_after_vault_interaction,
        ),
    );
    // 2. redeeming user position balance must increase by 399 USDC
    let redeeming_user_usdc_balance_after_vault_interaction = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);

    assert_with_error(
        redeeming_user_usdc_balance_after_vault_interaction == redeeming_user_usdc_balance_before_redeem
            + value_of_shares.into(),
        format!(
            "redeeming user collateral balance did not increase by {:?}, before: {:?}, after: {:?}",
            value_of_shares,
            redeeming_user_usdc_balance_before_redeem,
            redeeming_user_usdc_balance_after_vault_interaction,
        ),
    );

    let redeeming_user_vault_share_balance_after_redeem = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);
    // 3. redeeming user vault share balance must decrease by redeemed amount
    assert_with_error(
        redeeming_user_vault_share_balance_before_redeem
            - 400_i64.into() == redeeming_user_vault_share_balance_after_redeem,
        format!(
            "depositing user vault share balance did not decrease, before: {:?}, after: {:?}",
            redeeming_user_vault_share_balance_before_redeem,
            redeeming_user_vault_share_balance_after_redeem,
        ),
    );
    //4. vault usdc balance must decrease by 399
    let vault_usdc_balance_after_redeem = state
        .facade
        .get_position_collateral_balance(vault_user.position_id);

    assert_with_error(
        vault_usdc_balance_after_redeem == vault_usdc_balance_before_redeem
            - value_of_shares.into(),
        format!(
            "vault usdc balance did not decrease by {:?}, before: {:?}, after: {:?}",
            value_of_shares,
            vault_usdc_balance_before_redeem,
            vault_usdc_balance_after_redeem,
        ),
    );
}

#[test]
#[should_panic(expected: "Redeem value too high. requested=444, actual=400, number_of_shares=400")]
fn test_redeem_from_protocol_vault_redeem_to_same_position_is_rejected_with_11pct_premium() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );
    const value_of_shares: u64 = 444;
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );
}

#[test]
fn test_redeem_from_protocol_vault_impacts_price_as_expected() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_1000_shares_before_withdrawal = vault_config
        .deployed_vault
        .erc4626
        .preview_redeem(1000_u256);

    const value_of_shares: u64 = 439;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );

    let value_of_1000_shares_after_withdrawal = vault_config
        .deployed_vault
        .erc4626
        .preview_redeem(1000_u256);

    assert_with_error(
        value_of_1000_shares_after_withdrawal == value_of_1000_shares_before_withdrawal - 7,
        format!(
            "value of 1000 shares did not decrease after withdrawal, before: {}, after: {}",
            value_of_1000_shares_before_withdrawal,
            value_of_1000_shares_after_withdrawal,
        ),
    );
}

#[test]
#[should_panic(expected: "ILLEGAL_BASE_TO_QUOTE_RATIO position_id: PositionId { value: 555 }")]
fn test_redeem_from_protocol_vault_unfair__user_redeem() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares - 10,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares - 10,
        );
}

#[test]
#[should_panic(expected: "ILLEGAL_BASE_TO_QUOTE_RATIO position_id: PositionId { value: 333 }")]
fn test_redeem_from_protocol_vault_unfair__vault_redeem() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares - 10,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );
}


#[test]
#[should_panic(expected: "FULFILLMENT_EXCEEDED position_id: PositionId { value: 555 }")]
fn test_redeem_from_protocol_vault_over_fulfilled_user() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;

    //user is getting better price, but they are over filled

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares + 1000,
            actual_shares_user: 400 + 10,
            actual_collateral_user: value_of_shares + 1000,
        );
}

#[test]
#[should_panic(expected: "FULFILLMENT_EXCEEDED position_id: PositionId { value: 333 }")]
fn test_redeem_from_protocol_vault_over_fulfilled_vault() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;

    //vault is getting better price, but they are over filled

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400 + 10,
            value_of_shares_user: value_of_shares - 100,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400 + 10,
            actual_collateral_user: value_of_shares - 100,
        );
}

#[test]
fn test_redeem_from_protocol_vault_allows_redeem_when_improving_tv_tr() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );

    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 1000usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 2000 * 0.3 btc risk
    // total risk = 600
    // total value = 900 + 2000 - 2000 = 1000
    // TV/TR = 900/600 = 1.5 = healthy

    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 600);

    state.facade.price_tick(@synthetic_info, 500);
    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 500usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 1000 * 0.3 btc risk
    // total risk = 300
    // total value = 900 + 1000 - 2000 = -100
    // TV/TR = -100/300 = -0 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, -100);
    state.facade.validate_total_risk(redeeming_user.position_id, 300);

    let value_of_shares: u64 = 400;
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );

    //we sold 400 shares for $400
    // user now has
    // 600 x vault_shares @ 1usd - 10% risk = 540
    // 400 USD
    // 2 x BTC @ 500usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 1000 * 0.3 btc risk
    // total risk = 300
    // total value = 540 + 400 + 1000 - 2000 = -60
    // TV/TR = -60/300 = -0.2 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, -60);
    state.facade.validate_total_risk(redeeming_user.position_id, 300);
}

#[test]
#[should_panic(
    expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: PositionId { value: 555 } TV before 100, TR before 360, TV after 40, TR after 360",
)]
fn test_redeem_from_protocol_vault_fails_redeem_when_worsening_tv_tr_of_unhealthy_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );

    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 1000usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 2000 * 0.3 btc risk
    // total risk = 600
    // total value = 900 + 2000 - 2000 = 900
    // TV/TR = 900/600 = 1.5 = healthy

    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 600);

    state.facade.price_tick(@synthetic_info, 600);
    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 600usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 1200 * 0.3 btc risk
    // total risk = 360
    // total value = 900 + 1200 - 2000 = 100
    // TV/TR = 100/360 = 0.27 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, 100);
    state.facade.validate_total_risk(redeeming_user.position_id, 360);

    let value_of_shares: u64 = 300;
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
        );
}


#[test]
fn test_liquidate_vault_shares_succeeds_when_improving_tv_tr() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );

    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 1000usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 2000 * 0.3 btc risk
    // total risk = 600
    // total value = 900 + 2000 - 2000 = 900
    // TV/TR = 900/600 = 1.5 = healthy

    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 600);

    state.facade.price_tick(@synthetic_info, 600);
    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 600usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 1200 * 0.3 btc risk
    // total risk = 360
    // total value = 900 + 1200 - 2000 = 100
    // TV/TR = 100/360 = 0.27 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, 100);
    state.facade.validate_total_risk(redeeming_user.position_id, 360);

    state
        .facade
        .liquidate_shares(
            vault: vault_config,
            liquidated_user: redeeming_user,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 400,
            actual_shares_user: 400,
            actual_collateral_user: 400,
        );
}

#[test]
fn test_liquidate_vault_shares_succeeds_when_improving_tv_tr_starting_with_negative_tv() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );

    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 1000usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 2000 * 0.3 btc risk
    // total risk = 600
    // total value = 900 + 2000 - 2000 = 900
    // TV/TR = 900/600 = 1.5 = healthy

    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 600);

    state.facade.price_tick(@synthetic_info, 450);
    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 450usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 900 * 0.3 btc risk
    // total risk = 270
    // total value = 900 + 900 - 2000 = -200
    // TV/TR = -200/270 = -0.74 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, -200);
    state.facade.validate_total_risk(redeeming_user.position_id, 270);

    state
        .facade
        .liquidate_shares(
            vault: vault_config,
            liquidated_user: redeeming_user,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 361,
            actual_shares_user: 400,
            actual_collateral_user: 361,
        );
}

#[test]
#[should_panic(
    expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: PositionId { value: 555 } TV before -200, TR before 270, TV after -201, TR after 270",
)]
fn test_liquidate_vault_shares_fails_when_not_improving_tv_tr_starting_with_negative_tv() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );

    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 1000usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 2000 * 0.3 btc risk
    // total risk = 600
    // total value = 900 + 2000 - 2000 = 900
    // TV/TR = 900/600 = 1.5 = healthy

    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 600);

    state.facade.price_tick(@synthetic_info, 450);
    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 450usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 900 * 0.3 btc risk
    // total risk = 270
    // total value = 900 + 900 - 2000 = -200
    // TV/TR = -200/270 = -0.74 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, -200);
    state.facade.validate_total_risk(redeeming_user.position_id, 270);

    state
        .facade
        .liquidate_shares(
            vault: vault_config,
            liquidated_user: redeeming_user,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 359,
            actual_shares_user: 400,
            actual_collateral_user: 359,
        );
}


#[test]
#[should_panic(
    expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: PositionId { value: 555 } TV before 100, TR before 360, TV after 40, TR after 360",
)]
fn test_liquidate_vault_shares_fails_when_worsening_tv_tr() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );

    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 1000usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 2000 * 0.3 btc risk
    // total risk = 600
    // total value = 900 + 2000 - 2000 = 900
    // TV/TR = 900/600 = 1.5 = healthy

    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 600);

    state.facade.price_tick(@synthetic_info, 600);
    //redeeming user has
    // 1000 x vault_shares @ 1usd - 10% risk = 900
    // 2 x BTC @ 600usd
    // - 2000 usd collateral cost of trade
    // 0 vault_share risk
    // 1200 * 0.3 btc risk
    // total risk = 360
    // total value = 900 + 1200 - 2000 = 100
    // TV/TR = 100/360 = 0.27 = unhealthy

    state.facade.validate_total_value(redeeming_user.position_id, 100);
    state.facade.validate_total_risk(redeeming_user.position_id, 360);

    state
        .facade
        .liquidate_shares(
            vault: vault_config,
            liquidated_user: redeeming_user,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 400,
            actual_shares_user: 400,
            actual_collateral_user: 300,
        );
}

#[test]
#[should_panic(expected: 'ONLY_PERPS_CAN_WITHDRAW')]
fn test_withdraw_cannot_be_called_except_by_perps_contract() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let receiving_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    let dispatcher: IERC4626Dispatcher = vault_config.deployed_vault.erc4626;
    dispatcher
        .withdraw(
            assets: 1000,
            receiver: receiving_user.account.address,
            owner: vault_config.deployed_vault.owning_account.address,
        );
}

#[test]
#[should_panic(expected: 'ONLY_PERPS_CAN_WITHDRAW')]
fn test_redeem_cannot_be_called_except_by_perps_contract() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let receiving_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    let dispatcher: IERC4626Dispatcher = vault_config.deployed_vault.erc4626;
    dispatcher
        .redeem(
            shares: 1000,
            receiver: receiving_user.account.address,
            owner: vault_config.deployed_vault.owning_account.address,
        );
}

#[test]
#[should_panic(expected: 'ASSET_BALANCE_NEGATIVE')]
fn test_redeem_vault_shares_negative() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let redeeming_user = state.new_user_with_position_id(555_u32.into());
    let user = state.new_user_with_position_id(111_u32.into());
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 400_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.process_deposit(state.facade.deposit(user.account, user.position_id, 10000_u64));
    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: user,
                    receiving_user: user,
                ),
        );

    // Redeeming user position before redeem:
    // 10000 x USDC @ 1usd
    // 0 x vault_shares @ 1usd
    // total value = 10000 + 0 = 10000
    // total risk = 0
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: 400,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 400,
            actual_shares_user: 400,
            actual_collateral_user: 400,
        );
}

#[test]
fn test_forced_redeem_from_vault_request() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let redeeming_user_usdc_balance_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let redeeming_user_vault_share_balance_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);

    let value_of_shares: u64 = 399;
    let shares_to_redeem: u64 = 400;

    // Approve premium cost for forced redeem
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state
        .facade
        .token_state
        .approve(
            owner: redeeming_user.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced redeem
    let (user_order, vault_order) = state
        .facade
        .forced_redeem_from_vault_request(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_redeem,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_redeem,
            value_of_shares_vault: value_of_shares,
        );

    // Check ForcedRedeemFromVaultRequest event
    let forced_redeem = ForcedRedeemFromVault { order: user_order, vault_approval: vault_order };
    let user_hash = forced_redeem.get_message_hash(redeeming_user.account.key_pair.public_key);
    let events_span = state
        .facade
        .event_info
        .get_events()
        .emitted_by(state.facade.perpetuals_contract)
        .events;
    let events_len: usize = events_span.len();
    let last_event = events_span[events_len - 1];
    assert_forced_redeem_from_vault_request_event_with_expected(
        spied_event: last_event,
        order_source_position: user_order.source_position,
        order_receive_position: user_order.receive_position,
        order_base_asset_id: user_order.base_asset_id,
        order_base_amount: user_order.base_amount,
        order_quote_asset_id: user_order.quote_asset_id,
        order_quote_amount: user_order.quote_amount,
        order_fee_asset_id: user_order.fee_asset_id,
        order_fee_amount: user_order.fee_amount,
        order_expiration: user_order.expiration,
        order_salt: user_order.salt,
        vault_approval_source_position: vault_order.source_position,
        vault_approval_receive_position: vault_order.receive_position,
        vault_approval_base_asset_id: vault_order.base_asset_id,
        vault_approval_base_amount: vault_order.base_amount,
        vault_approval_quote_asset_id: vault_order.quote_asset_id,
        vault_approval_quote_amount: vault_order.quote_amount,
        vault_approval_fee_asset_id: vault_order.fee_asset_id,
        vault_approval_fee_amount: vault_order.fee_amount,
        vault_approval_expiration: vault_order.expiration,
        vault_approval_salt: vault_order.salt,
        hash: user_hash,
    );

    // Check balances haven't changed yet (request only)
    assert_with_error(
        state
            .facade
            .get_position_collateral_balance(
                redeeming_user.position_id,
            ) == redeeming_user_usdc_balance_before,
        "User collateral balance should not change after request",
    );
    assert_with_error(
        state
            .facade
            .get_position_asset_balance(
                redeeming_user.position_id, vault_config.asset_id,
            ) == redeeming_user_vault_share_balance_before,
        "User vault share balance should not change after request",
    );
}

#[test]
fn test_forced_redeem_from_vault_after_timelock() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let redeeming_user_usdc_balance_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let redeeming_user_vault_share_balance_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);
    let vault_usdc_balance_before = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    let value_of_shares: u64 = 399;
    let shares_to_redeem: u64 = 400;

    // Approve premium cost for forced redeem
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state
        .facade
        .token_state
        .approve(
            owner: redeeming_user.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced redeem
    let (user_order, vault_order) = state
        .facade
        .forced_redeem_from_vault_request(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_redeem,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_redeem,
            value_of_shares_vault: value_of_shares,
        );

    // Wait for timelock
    state.facade.advance_time(FORCED_ACTION_TIMELOCK + 1);

    // Execute forced redeem
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);

    // Check ForcedRedeemFromVault event
    let events_span = state
        .facade
        .event_info
        .get_events()
        .emitted_by(state.facade.perpetuals_contract)
        .events;
    let events_len: usize = events_span.len();
    let last_event = events_span[events_len - 1];
    assert_forced_redeem_from_vault_event_with_expected(
        spied_event: last_event,
        order_source_position: user_order.source_position,
        order_receive_position: user_order.receive_position,
        order_base_asset_id: user_order.base_asset_id,
        order_base_amount: user_order.base_amount,
        order_quote_asset_id: user_order.quote_asset_id,
        order_quote_amount: user_order.quote_amount,
        order_fee_asset_id: user_order.fee_asset_id,
        order_fee_amount: user_order.fee_amount,
        order_expiration: user_order.expiration,
        order_salt: user_order.salt,
        vault_approval_source_position: vault_order.source_position,
        vault_approval_receive_position: vault_order.receive_position,
        vault_approval_base_asset_id: vault_order.base_asset_id,
        vault_approval_base_amount: vault_order.base_amount,
        vault_approval_quote_asset_id: vault_order.quote_asset_id,
        vault_approval_quote_amount: vault_order.quote_amount,
        vault_approval_fee_asset_id: vault_order.fee_asset_id,
        vault_approval_fee_amount: vault_order.fee_amount,
        vault_approval_expiration: vault_order.expiration,
        vault_approval_salt: vault_order.salt,
    );

    // Check balances after forced redeem
    let redeeming_user_usdc_balance_after = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let redeeming_user_vault_share_balance_after = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);
    let vault_usdc_balance_after = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    assert_with_error(
        redeeming_user_usdc_balance_after == redeeming_user_usdc_balance_before
            + value_of_shares.into(),
        "User collateral balance should increase by value_of_shares",
    );
    assert_with_error(
        redeeming_user_vault_share_balance_after == redeeming_user_vault_share_balance_before
            - shares_to_redeem.into(),
        "User vault share balance should decrease by shares_to_redeem",
    );
    assert_with_error(
        vault_usdc_balance_after == vault_usdc_balance_before - value_of_shares.into(),
        "Vault collateral balance should decrease by value_of_shares",
    );
}

#[test]
fn test_forced_redeem_from_vault_by_operator_before_timelock() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let redeeming_user_usdc_balance_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let redeeming_user_vault_share_balance_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);

    let value_of_shares: u64 = 399;
    let shares_to_redeem: u64 = 400;

    // Approve premium cost for forced redeem
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state
        .facade
        .token_state
        .approve(
            owner: redeeming_user.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced redeem
    let (user_order, vault_order) = state
        .facade
        .forced_redeem_from_vault_request(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_redeem,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_redeem,
            value_of_shares_vault: value_of_shares,
        );

    // Operator executes forced redeem before timelock (allowed)
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: state.facade.operator);

    // Check balances after forced redeem
    let redeeming_user_usdc_balance_after = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let redeeming_user_vault_share_balance_after = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);

    assert_with_error(
        redeeming_user_usdc_balance_after == redeeming_user_usdc_balance_before
            + value_of_shares.into(),
        "User collateral balance should increase by value_of_shares",
    );
    assert_with_error(
        redeeming_user_vault_share_balance_after == redeeming_user_vault_share_balance_before
            - shares_to_redeem.into(),
        "User vault share balance should decrease by shares_to_redeem",
    );
}

#[test]
#[should_panic(expected: 'FORCED_WAIT_REQUIRED')]
fn test_forced_redeem_from_vault_user_before_timelock_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;
    let shares_to_redeem: u64 = 400;

    // Approve premium cost for forced redeem
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state
        .facade
        .token_state
        .approve(
            owner: redeeming_user.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced redeem
    let (user_order, vault_order) = state
        .facade
        .forced_redeem_from_vault_request(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_redeem,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_redeem,
            value_of_shares_vault: value_of_shares,
        );

    // Try to execute forced redeem before timelock (should fail)
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_forced_redeem_from_vault_user_after_operator_already_redeemed_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;
    let shares_to_redeem: u64 = 400;

    // Approve premium cost for forced redeem
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state
        .facade
        .token_state
        .approve(
            owner: redeeming_user.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced redeem
    let (user_order, vault_order) = state
        .facade
        .forced_redeem_from_vault_request(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_redeem,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_redeem,
            value_of_shares_vault: value_of_shares,
        );

    // Operator executes forced redeem before timelock (allowed)
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: state.facade.operator);

    // Wait for timelock
    state.facade.advance_time(FORCED_ACTION_TIMELOCK + 1);

    // User tries to execute forced redeem after operator already did it (should fail)
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_forced_redeem_from_vault_operator_after_user_already_redeemed_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let value_of_shares: u64 = 399;
    let shares_to_redeem: u64 = 400;

    // Approve premium cost for forced redeem
    let premium_cost: u64 = PREMIUM_COST;
    let quantum: u64 = state.facade.collateral_quantum;
    let premium_amount: u128 = premium_cost.wide_mul(quantum);
    state
        .facade
        .token_state
        .approve(
            owner: redeeming_user.account.address,
            spender: state.facade.perpetuals_contract,
            amount: premium_amount,
        );

    // Request forced redeem
    let (user_order, vault_order) = state
        .facade
        .forced_redeem_from_vault_request(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_redeem,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_redeem,
            value_of_shares_vault: value_of_shares,
        );

    // Wait for timelock
    state.facade.advance_time(FORCED_ACTION_TIMELOCK + 1);

    // User executes forced redeem after timelock
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);

    // Operator tries to execute forced redeem after user already did it (should fail)
    state.facade.force_redeem_from_vault(user_order, vault_order, caller: state.facade.operator);
}
