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
use snforge_std::TokenTrait;
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils_testing::test_utils::TokenTrait as StarknetTokenTrait;
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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
            other_collaterals: array![].span(),
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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
            other_collaterals: array![].span(),
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
            other_collaterals: array![].span(),
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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
            other_collaterals: array![].span(),
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
            other_collaterals: array![].span(),
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
            other_collaterals: array![].span(),
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
            other_collaterals: array![].span(),
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
            other_collaterals: ArrayTrait::<
                perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff,
            >::new()
                .span(),
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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
            other_collaterals: array![].span(),
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
            other_collaterals: array![].span(),
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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
#[should_panic(
    expected: "Spot Balance for asset: AssetId { value: 1448304433 } has gone negative. now: Balance { value: -400 }, was: Balance { value: 0 }, position: PositionId { value: 555 }",
)]
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

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
            other_collaterals: array![].span(),
        );
}

#[test]
fn test_forced_redeem_from_vault_request() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();
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
    state.facade.enable_escape_hatch();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);

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
    state.facade.enable_escape_hatch();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: state.facade.operator);

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
    state.facade.enable_escape_hatch();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_forced_redeem_from_vault_user_after_operator_already_redeemed_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: state.facade.operator);

    // Wait for timelock
    state.facade.advance_time(FORCED_ACTION_TIMELOCK + 1);

    // User tries to execute forced redeem after operator already did it (should fail)
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_forced_redeem_from_vault_operator_after_user_already_redeemed_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.enable_escape_hatch();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

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
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: redeeming_user.account);

    // Operator tries to execute forced redeem after user already did it (should fail)
    state.facade.forced_redeem_from_vault(user_order, vault_order, caller: state.facade.operator);
}
#[test]
fn test_redeem_from_protocol_vault_with_additional_spot_assets() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);

    // Add an active secondary spot asset (e.g., WBTC)
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'BTC', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let btc_asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);
    snforge_std::set_balance(target: vault_user.account.address, new_balance: 5000000, :token);

    let deposit_info_user_1 = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: btc_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 10,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);
    //vault has
    // 5000 USDC
    // 10 BTC * 10 * (1-0.1) = 900
    println!("Validated total value");
    // Register the vault's share asset
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.validate_total_value(vault_config.position_id, 5900);

    // Setup redeeming user
    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    println!("Depositing into vault")
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 1,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );
    println!("Deposited into vault");

    // Prepare redeem details
    let shares_to_burn = 650; // vault price is currently $1

    let redeeming_user_usdc_balance_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_usdc_balance_before = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);
    let redeeming_user_btc_balance_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, btc_asset_id);
    let vault_btc_balance_before = state
        .facade
        .get_position_asset_balance(vault_config.position_id, btc_asset_id);

    // We will withdraw some USDC and some BTC
    let value_of_shares: u64 = 650; // Expected pure USD value
    let actual_usdc_collateral = 550; // Requested physical USD
    // 550 USDC + 1 BTC @ 100

    let btc_withdrawal_diff: i64 = 1; // Withdrawal of 1 BTC
    let btc_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: btc_asset_id, diff: btc_withdrawal_diff,
        },
    ]
        .span();

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_burn,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_burn,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: shares_to_burn,
            actual_collateral_user: actual_usdc_collateral,
            other_collaterals: btc_collaterals,
        );

    let redeeming_user_usdc_balance_after = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_usdc_balance_after = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);
    let redeeming_user_btc_balance_after = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, btc_asset_id);
    let vault_btc_balance_after = state
        .facade
        .get_position_asset_balance(vault_config.position_id, btc_asset_id);

    // Validate final balances
    let actual_usdc_i64: i64 = actual_usdc_collateral.try_into().unwrap();
    let actual_usdc_balance = actual_usdc_i64.into();

    assert(
        redeeming_user_usdc_balance_after == redeeming_user_usdc_balance_before
            + actual_usdc_balance,
        'user missing usdc',
    );
    assert(
        vault_usdc_balance_after == vault_usdc_balance_before - actual_usdc_balance,
        'vault surplus usdc',
    );

    let btc_diff_balance: perpetuals::core::types::balance::Balance = btc_withdrawal_diff.into();
    assert(
        redeeming_user_btc_balance_after == redeeming_user_btc_balance_before + btc_diff_balance,
        'user missing btc',
    );
    assert(
        vault_btc_balance_after == vault_btc_balance_before - btc_diff_balance, 'vault surplus btc',
    );
}


#[test]
fn test_redeem_from_protocol_vault_with_multiple_additional_spot_assets() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);

    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };

    // Add BTC
    let btc_token = snforge_std::Token::STRK;
    let btc_erc20 = btc_token.contract_address();
    let btc_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'BTC',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: btc_erc20,
    );
    let btc_asset_id = btc_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @btc_asset_info, initial_price: 100);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: btc_token,
    );

    // Add ETH
    let eth_token = snforge_std::Token::ETH;
    let eth_erc20 = eth_token.contract_address();
    let eth_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: eth_erc20,
    );
    let eth_asset_id = eth_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @eth_asset_info, initial_price: 50);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: eth_token,
    );

    // Deposit BTC into Vault (from Vault Admin)
    let deposit_info_btc = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: btc_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 10,
        );
    state.facade.process_deposit(deposit_info: deposit_info_btc);

    // Deposit ETH into Vault (from Vault Admin)
    let deposit_info_eth = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: eth_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 20,
        );
    state.facade.process_deposit(deposit_info: deposit_info_eth);

    // Vault has
    // 5000 USDC
    // 10 BTC * 100 * (1-0.1) = 900
    // 20 ETH * 50 * (1-0.1) = 900
    // Total Value = 6800

    // Register the vault's share asset
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.validate_total_value(vault_config.position_id, 6800);

    // Setup redeeming user
    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 2000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 2000,
                    min_shares_to_receive: 1,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // Prepare redeem details
    // Value of vault shares = $1
    let shares_to_burn = 1000;

    let redeeming_user_usdc_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_usdc_before = state.facade.get_position_collateral_balance(vault_config.position_id);
    let redeeming_user_btc_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, btc_asset_id);
    let vault_btc_before = state
        .facade
        .get_position_asset_balance(vault_config.position_id, btc_asset_id);
    let redeeming_user_eth_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, eth_asset_id);
    let vault_eth_before = state
        .facade
        .get_position_asset_balance(vault_config.position_id, eth_asset_id);

    // We will withdraw some USDC, BTC, and ETH
    let value_of_shares: u64 = 1000;

    // 5 BTC @ $100 = $500
    // 4 ETH @ $50 = $200
    // 300 USDC = $300
    // Total = $1000
    let actual_usdc_collateral = 300;
    let btc_withdrawal_diff: i64 = 5;
    let eth_withdrawal_diff: i64 = 4;

    let mixed_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: btc_asset_id, diff: btc_withdrawal_diff,
        },
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: eth_asset_id, diff: eth_withdrawal_diff,
        },
    ]
        .span();

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_burn,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_burn,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: shares_to_burn,
            actual_collateral_user: actual_usdc_collateral,
            other_collaterals: mixed_collaterals,
        );

    let redeeming_user_usdc_after = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_usdc_after = state.facade.get_position_collateral_balance(vault_config.position_id);
    let redeeming_user_btc_after = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, btc_asset_id);
    let vault_btc_after = state
        .facade
        .get_position_asset_balance(vault_config.position_id, btc_asset_id);
    let redeeming_user_eth_after = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, eth_asset_id);
    let vault_eth_after = state
        .facade
        .get_position_asset_balance(vault_config.position_id, eth_asset_id);

    // Validate final balances
    let actual_usdc_i64: i64 = actual_usdc_collateral.try_into().unwrap();
    let actual_usdc_balance = actual_usdc_i64.into();

    assert(
        redeeming_user_usdc_after == redeeming_user_usdc_before + actual_usdc_balance,
        'user missing usdc',
    );
    assert(vault_usdc_after == vault_usdc_before - actual_usdc_balance, 'vault surplus usdc');

    let btc_diff_balance: perpetuals::core::types::balance::Balance = btc_withdrawal_diff.into();
    assert(
        redeeming_user_btc_after == redeeming_user_btc_before + btc_diff_balance,
        'user missing btc',
    );
    assert(vault_btc_after == vault_btc_before - btc_diff_balance, 'vault surplus btc');

    let eth_diff_balance: perpetuals::core::types::balance::Balance = eth_withdrawal_diff.into();
    assert(
        redeeming_user_eth_after == redeeming_user_eth_before + eth_diff_balance,
        'user missing eth',
    );
    assert(vault_eth_after == vault_eth_before - eth_diff_balance, 'vault surplus eth');
}

#[test]
fn test_redeem_entirely_in_other_spot_assets() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);

    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };

    // Add BTC
    let btc_token = snforge_std::Token::STRK;
    let btc_erc20 = btc_token.contract_address();
    let btc_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'BTC',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: btc_erc20,
    );
    let btc_asset_id = btc_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @btc_asset_info, initial_price: 100);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: btc_token,
    );

    // Deposit BTC into Vault (from Vault Admin)
    let deposit_info_btc = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: btc_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 10,
        );
    state.facade.process_deposit(deposit_info: deposit_info_btc);

    // Vault has 5000 USDC and 10 BTC ($900 value) -> Total = 5900
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.validate_total_value(vault_config.position_id, 5900);

    // Setup redeeming user
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
                    min_shares_to_receive: 1,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let shares_to_burn = 400;

    let redeeming_user_usdc_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_usdc_before = state.facade.get_position_collateral_balance(vault_config.position_id);
    let redeeming_user_btc_before = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, btc_asset_id);
    let vault_btc_before = state
        .facade
        .get_position_asset_balance(vault_config.position_id, btc_asset_id);

    // We withdraw 4 BTC @ $100 = $400, leaving exactly 0 USDC needed from the vault.
    let value_of_shares: u64 = 400;
    let actual_usdc_collateral = 0;
    let btc_withdrawal_diff: i64 = 4;

    let mixed_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: btc_asset_id, diff: btc_withdrawal_diff,
        },
    ]
        .span();

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_burn,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_burn,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: shares_to_burn,
            actual_collateral_user: actual_usdc_collateral,
            other_collaterals: mixed_collaterals,
        );

    let redeeming_user_usdc_after = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_usdc_after = state.facade.get_position_collateral_balance(vault_config.position_id);
    let redeeming_user_btc_after = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, btc_asset_id);
    let vault_btc_after = state
        .facade
        .get_position_asset_balance(vault_config.position_id, btc_asset_id);

    assert(redeeming_user_usdc_after == redeeming_user_usdc_before, 'user should not receive usdc');
    assert(vault_usdc_after == vault_usdc_before, 'vault should not lose usdc');

    let btc_diff_balance: perpetuals::core::types::balance::Balance = btc_withdrawal_diff.into();
    assert(
        redeeming_user_btc_after == redeeming_user_btc_before + btc_diff_balance,
        'user missing btc',
    );
    assert(vault_btc_after == vault_btc_before - btc_diff_balance, 'vault surplus btc');
}

#[test]
#[should_panic(
    expected: "Spot Balance for asset: AssetId { value: 4346947 } has gone negative. now: Balance { value: -3 }, was: Balance { value: 2 }, position: PositionId { value: 101 }",
)]
fn test_redeem_fails_when_vault_lacks_requested_asset() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 20000_u64);
    state.facade.process_deposit(vault_init_deposit);

    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };

    // Add BTC
    let btc_token = snforge_std::Token::STRK;
    let btc_erc20 = btc_token.contract_address();
    let btc_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'BTC',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: btc_erc20,
    );
    let btc_asset_id = btc_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @btc_asset_info, initial_price: 100);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: btc_token,
    );

    // Deposit only 2 BTC into Vault
    let deposit_info_btc = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: btc_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 2,
        );
    state.facade.process_deposit(deposit_info: deposit_info_btc);

    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Setup redeeming user
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
                    min_shares_to_receive: 1,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // Try to withdraw 5 BTC, but the vault only has 2 BTC! This will trigger a negative value
    // error during spot diff apply
    let shares_to_burn = 500;
    let value_of_shares: u64 = 500;
    let actual_usdc_collateral = 0;
    let btc_withdrawal_diff: i64 = 5;

    let mixed_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: btc_asset_id, diff: btc_withdrawal_diff,
        },
    ]
        .span();

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_burn,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_burn,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: shares_to_burn,
            actual_collateral_user: actual_usdc_collateral,
            other_collaterals: mixed_collaterals,
        );
}

#[test]
#[should_panic(
    expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: PositionId { value: 102 } TV before 900, TR before 900, TV after 500, TR after 900",
)]
fn test_redeem_fails_when_user_becomes_unhealthy_due_to_asset_haircut() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let trade_user = state.new_user_with_position();

    // Vault deposits 5000 USDC
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);

    // High risk factor: 50% haircut
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };

    // Add risky asset (e.g. DOGE)
    let doge_token = snforge_std::Token::STRK;
    let doge_erc20 = doge_token.contract_address();
    let doge_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'DGE',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: doge_erc20,
    );
    let doge_asset_id = doge_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @doge_asset_info, initial_price: 100);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: doge_token,
    );

    // Deposit 10 DOGE into Vault
    let deposit_info_doge = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: doge_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 10,
        );
    state.facade.process_deposit(deposit_info: deposit_info_doge);

    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Redeeming user deposits 1000 USDC and buys 1000 Vault Shares
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
                    min_shares_to_receive: 1,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // We add a synthetic asset to create TR. Let's add BTC synthetic with 90% risk!
    let risk_factor_tiers = RiskFactorTiers {
        tiers: array![900].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_btc_info = AssetInfoTrait::new(
        asset_name: 'sBTC', risk_factor_data: risk_factor_tiers, oracles_len: 1,
    );
    state.facade.add_active_synthetic(@synthetic_btc_info, initial_price: 1000);
    let sbtc_id = synthetic_btc_info.asset_id;

    // other user deposits $3000
    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 1,
            base_asset_id: sbtc_id,
            quote_amount: -1000,
            fee_amount: 0,
        );
    let other_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -1,
            base_asset_id: sbtc_id,
            quote_amount: 1000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_order,
            base: 1,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // TV = 900 (Shares) + 1000 (1 BTC * 1000 from trade) - 1000
    // = 900.
    // TR = 1 (BTC) * 1000 (Price) * 0.90 (Risk) = 900.
    // Initial State is Healthy: TV (900) = TR (900).
    state.facade.validate_total_value(redeeming_user.position_id, 900);
    state.facade.validate_total_risk(redeeming_user.position_id, 900);

    let doge_withdrawal_diff: i64 = 10;
    let mixed_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: doge_asset_id, diff: doge_withdrawal_diff,
        },
    ]
        .span();

    //user will lose 900 worth of share TV contribution
    // receive $1000 worth of DGE
    // which contributes $500 to TV
    // TV = TV_before - 900 + 500 = 500
    // TR = TR_before = 900
    // State is Unhealthy: TV (500) < TR (900).

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1000,
            value_of_shares_user: 1000,
            shares_to_burn_vault: 1000,
            value_of_shares_vault: 1000,
            actual_shares_user: 1000,
            actual_collateral_user: 0,
            other_collaterals: mixed_collaterals,
        );
}

#[test]
fn test_redeem_from_vault_with_interest_different_receiver_and_other_collaterals() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let withdrawing_user = state.new_user_with_position();
    let receiving_user = state.new_user_with_position();

    let risk_factor_tiers_doge = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let doge_token = snforge_std::Token::STRK;
    let doge_erc20 = doge_token.contract_address();
    let doge_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'DGE',
        risk_factor_data: risk_factor_tiers_doge,
        oracles_len: 1,
        erc20_contract_address: doge_erc20,
    );
    let doge_asset_id = doge_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @doge_asset_info, initial_price: 100);

    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 500000, token: doge_token,
    );

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let deposit_info_doge = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: doge_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 10,
        );
    state.facade.process_deposit(deposit_info: deposit_info_doge);

    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(withdrawing_user.account, withdrawing_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(receiving_user.account, receiving_user.position_id, 10_000_u64),
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
                    depositing_user: withdrawing_user,
                    receiving_user: withdrawing_user,
                ),
        );

    state.facade.advance_time(seconds: starkware_utils::constants::HOUR);

    let sender_collateral_before = state
        .facade
        .get_position_collateral_balance(withdrawing_user.position_id);
    let receiver_collateral_before = state
        .facade
        .get_position_collateral_balance(receiving_user.position_id);
    let vault_collateral_before = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    let receiver_doge_before = state
        .facade
        .get_position_asset_balance(receiving_user.position_id, doge_asset_id);
    let vault_doge_before = state
        .facade
        .get_position_asset_balance(vault_config.position_id, doge_asset_id);

    let interest_vault: i64 = 3;
    let interest_sender: i64 = -2;
    let interest_receiver: i64 = 4;
    let value_of_shares: u64 = 399;

    let doge_withdrawal_diff: i64 = 2;
    let doge_value = 200;
    let usdc_value = value_of_shares - doge_value; // 199

    let mixed_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: doge_asset_id, diff: doge_withdrawal_diff,
        },
    ]
        .span();

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: withdrawing_user,
            receiving_user: receiving_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: usdc_value,
            interest_amount_vault_position: interest_vault,
            interest_amount_sender: interest_sender,
            interest_amount_receiver: interest_receiver,
            other_collaterals: mixed_collaterals,
        );

    // Sender gets only interest (shares burned, no collateral from redeem)
    state
        .facade
        .validate_collateral_balance(
            position_id: withdrawing_user.position_id,
            expected_balance: sender_collateral_before + interest_sender.into(),
        );

    // Receiver gets USDC from redeem + interest
    state
        .facade
        .validate_collateral_balance(
            position_id: receiving_user.position_id,
            expected_balance: receiver_collateral_before
                + usdc_value.into()
                + interest_receiver.into(),
        );

    // Receiver gets DOGE from redeem
    state
        .facade
        .validate_asset_balance(
            position_id: receiving_user.position_id,
            asset_id: doge_asset_id,
            expected_balance: receiver_doge_before + doge_withdrawal_diff.into(),
        );

    // Vault loses USDC, gains interest
    state
        .facade
        .validate_collateral_balance(
            position_id: vault_config.position_id,
            expected_balance: vault_collateral_before - usdc_value.into() + interest_vault.into(),
        );

    // Vault loses DOGE
    state
        .facade
        .validate_asset_balance(
            position_id: vault_config.position_id,
            asset_id: doge_asset_id,
            expected_balance: vault_doge_before - doge_withdrawal_diff.into(),
        );
}

#[test]
#[should_panic(expected: "ILLEGAL_BASE_TO_QUOTE_RATIO position_id: PositionId { value: 102 }")]
fn test_redeem_from_protocol_vault_with_multiple_additional_spot_assets_not_enough_value() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);

    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };

    // Add BTC
    let btc_token = snforge_std::Token::STRK;
    let btc_erc20 = btc_token.contract_address();
    let btc_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'BTC',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: btc_erc20,
    );
    let btc_asset_id = btc_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @btc_asset_info, initial_price: 100);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: btc_token,
    );

    // Add ETH
    let eth_token = snforge_std::Token::ETH;
    let eth_erc20 = eth_token.contract_address();
    let eth_asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: eth_erc20,
    );
    let eth_asset_id = eth_asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @eth_asset_info, initial_price: 50);
    snforge_std::set_balance(
        target: vault_user.account.address, new_balance: 5000000, token: eth_token,
    );

    // Deposit BTC into Vault (from Vault Admin)
    let deposit_info_btc = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: btc_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 10,
        );
    state.facade.process_deposit(deposit_info: deposit_info_btc);

    // Deposit ETH into Vault (from Vault Admin)
    let deposit_info_eth = state
        .facade
        .deposit_spot(
            depositor: vault_user.account,
            asset_id: eth_asset_id,
            position_id: vault_user.position_id,
            quantized_amount: 20,
        );
    state.facade.process_deposit(deposit_info: deposit_info_eth);

    // Vault has
    // 5000 USDC
    // 10 BTC * 100 * (1-0.1) = 900
    // 20 ETH * 50 * (1-0.1) = 900
    // Total Value = 6800

    // Register the vault's share asset
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.validate_total_value(vault_config.position_id, 6800);

    // Setup redeeming user
    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 2000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 2000,
                    min_shares_to_receive: 1,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let shares_to_burn = 1000;
    let value_of_shares: u64 = 1000;
    let actual_usdc_collateral = 300;
    let btc_withdrawal_diff: i64 = 2;
    let eth_withdrawal_diff: i64 = 1;

    let mixed_collaterals = array![
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: btc_asset_id, diff: btc_withdrawal_diff,
        },
        perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff {
            asset_id: eth_asset_id, diff: eth_withdrawal_diff,
        },
    ]
        .span();

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_burn,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_burn,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: shares_to_burn,
            actual_collateral_user: actual_usdc_collateral,
            other_collaterals: mixed_collaterals,
        );
}
