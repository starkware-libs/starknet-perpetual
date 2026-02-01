use core::num::traits::Pow;
use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::TokenTrait;
use starknet::storage::{StoragePathEntry, StoragePointerWriteAccess};
use starkware_utils::constants::{HOUR, MAX_U128};
use starkware_utils::time::time::Timestamp;
use super::perps_tests_facade::PerpsTestsFacadeTrait;

#[test]
fn test_deleverage_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user_1 = state.new_user_with_position();
    let deleverager_user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: deleverager_user_1.account,
            position_id: deleverager_user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: deleverager_user_2.account,
            position_id: deleverager_user_2.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    // User willing to buy 2 synthetic assets for 168 (quote) + 20 (fee).
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -168,
            fee_amount: 20,
        );

    let order_deleverager_user_1 = state
        .facade
        .create_order(
            user: deleverager_user_1,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 50,
            fee_amount: 2,
        );

    let order_deleverager_user_2 = state
        .facade
        .create_order(
            user: deleverager_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 84,
            fee_amount: 2,
        );

    // Make trades.
    // User recieves 1 synthetic asset for 84 (quote) + 10 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user_1,
            base: 1,
            quote: -84,
            fee_a: 10,
            fee_b: 3,
        );

    // User recieves 1 synthetic asset for 84 (quote) + 10 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user_2,
            base: 1,
            quote: -84,
            fee_a: 10,
            fee_b: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -188 + 2 * 100 = 12                 2 * 100 * 0.01 = 2           6
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 12);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 7 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -202 + 2 * 100 = -2                 2 * 100 * 0.01 = 2          - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -2);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user_1,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 101,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -101 + 1 * 100 = -1                 1 * 100 * 0.01 = 1          - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -1);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 1);

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user_2,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 101,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 100 = 0                  0 * 100 * 0.01 = 0            -
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_deleverage_after_price_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Create orders.
    // User willing to buy 2 synthetic assets for 33 (quote) + 3 (fee).
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -33,
            fee_amount: 3,
        );
    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 30,
            fee_amount: 4,
        );

    // Make trades.
    // User recieves 2 synthetic asset for 3 (quote) + 3 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 2,
            quote: -33,
            fee_a: 3,
            fee_b: 4,
        );

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -36 + 2 * 20 = 4                    2 * 20 * 0.1 = 4               1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 4);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 4);

    state.facade.price_tick(asset_info: @synthetic_info, price: 10);

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -36 + 2 * 10 = -16                  2 * 10 * 0.1 = 2               -8
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -16);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 18,
        );

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:    -18 + 1 * 10 = -8                 1 * 10 * 0.1 = 1               -8
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -8);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 1);

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 18,
        );
    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 10 = 0                     0 * 10 * 0.1 = 0              0
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_deleverage_by_recieving_asset() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Create orders.
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 210,
            fee_amount: 0,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -210,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: -2,
            quote: 210,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:    210 - 2 * 100 = 10                 2 * 100 * 0.01 = 2           5
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 10);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: -6 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   198 - 2 * 100 = -2                 2 * 100 * 0.01 = 2           - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -2);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: 1,
            deleveraged_quote: -99,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     99 - 1 * 100 = -1                1 * 100 * 0.01 = 1           - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -1);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 1);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: 1,
            deleveraged_quote: -99,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 100 = 0                0 * 100 * 0.01 = 0              -
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_liquidate_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user_1 = state.new_user_with_position();
    let liquidator_user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: liquidator_user_1.account,
            position_id: liquidator_user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: liquidator_user_2.account,
            position_id: liquidator_user_2.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    // User willing to buy 3 synthetic assets for 285 (quote) + 20 (fee).
    let order_liquidated_user = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: 3,
            base_asset_id: asset_id,
            quote_amount: -285,
            fee_amount: 3,
        );

    let mut order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 50,
            fee_amount: 0,
        );

    // Make trade.
    // User recieves 2 synthetic asset for 190 (quote) + 2 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_1,
            base: 2,
            quote: -190,
            fee_a: 2,
            fee_b: 0,
        );

    // User recieves 1 synthetic asset for 95 (quote) + 0 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_2,
            base: 1,
            quote: -95,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:    -287 + 3 * 100 = 13                3 * 100 * 0.01 = 3           4.3
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 13);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:    -299 + 3 * 100 = 1                 3 * 100 * 0.01 = 3           0.3
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -101,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_1,
            liquidated_base: -1,
            liquidated_quote: 101,
            liquidated_insurance_fee: 1,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 10 = 1                  2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -201,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_2,
            liquidated_base: -2,
            liquidated_quote: 201,
            liquidated_insurance_fee: 2,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:        0 + 0 = 0                     0 * 100 * 0.01 = 0            0
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_liquidate_after_price_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 10);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user_1 = state.new_user_with_position();
    let liquidator_user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: liquidator_user_1.account,
            position_id: liquidator_user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: liquidator_user_2.account,
            position_id: liquidator_user_2.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    // User willing to sell 3 synthetic assets for 66 (quote) - 6 (fee).
    let order_liquidated_user = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: -3,
            base_asset_id: asset_id,
            quote_amount: 66,
            fee_amount: 6,
        );

    let mut order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -44,
            fee_amount: 4,
        );

    let mut order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -22,
            fee_amount: 2,
        );

    // Make trade.
    // User gives 2 synthetic asset for 44 (quote) - 2 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_1,
            base: -2,
            quote: 44,
            fee_a: 2,
            fee_b: 4,
        );

    // User recieves 1 synthetic asset for 22 (quote) - 1 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_2,
            base: -1,
            quote: 22,
            fee_a: 1,
            fee_b: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:     63 - 3 * 10 = 33                 |-3 * 10 * 0.1| = 3           12
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 33);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    state.facade.price_tick(asset_info: @synthetic_info, price: 20);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:     63 - 3 * 20 = 3                  |-3 * 20 * 0.1| = 6            0.5
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 3);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 6);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 41,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_1,
            liquidated_base: 2,
            liquidated_quote: -41,
            liquidated_insurance_fee: 1,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:      21 - 1 * 20 = 1                  |-1 * 20 * 0.1| = 2          0.5
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 20,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_2,
            liquidated_base: 1,
            liquidated_quote: -20,
            liquidated_insurance_fee: 0,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:        1 + 0 = 1                     0 * 100 * 0.01 = 0            -
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_flow_get_risk_factor() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10, 500, 1000].span(), first_tier_boundary: 2001, tier_size: 1000,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(asset_name: 'BTC', :risk_factor_data, oracles_len: 1);
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -10000,
            fee_amount: 0,
        );
    let order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -20,
            base_asset_id: asset_id,
            quote_amount: 20000,
            fee_amount: 0,
        );

    // Test:
    // No synthetic assets.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 0);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    // 2000 * 1%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 20);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // index = (3000 - 2001)/1000 = 1;
    // 3000 * 50%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 1500);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // index = (4000 - 2001)/1000 = 2;
    // 4000 * 100%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 4000);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 5,
            quote: -5000,
            fee_a: 0,
            fee_b: 0,
        );
    // index = (9000 - 2001)/1000 = 7 > 3; (last index)
    // 9000 * 100%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 9000);
}

#[test]
fn test_transfer() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();
    let user_3 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Transfer.
    let mut transfer_info = state
        .facade
        .transfer_request(sender: user_1, recipient: user_2, amount: 40000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_1, recipient: user_3, amount: 20000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_2, recipient: user_3, amount: 10000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_2, recipient: user_1, amount: 5000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_1, recipient: user_2, amount: 30000);
    state.facade.transfer(:transfer_info);

    //                 COLLATERAL
    // User 1:           15,000
    // User 2:           55,000
    // User 3:           30,000

    // Withdraw.
    let mut withdraw_info = state.facade.withdraw_request(user: user_1, amount: 15000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_2, amount: 15000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_2, amount: 10000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_2, amount: 30000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_3, amount: 30000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_withdraw_with_owner() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create users.
    let user_1 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Withdraw.
    let mut withdraw_info = state.facade.withdraw_request(user: user_1, amount: 15000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
#[should_panic(expected: 'CALLER_IS_NOT_OWNER_ACCOUNT')]
fn test_withdraw_with_owner_fails_if_not_caller() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Withdraw.
    let mut withdraw_info = state
        .facade
        .withdraw_request_with_caller(
            user: user_1, asset_id: state.facade.collateral_id, amount: 15000, caller: user_2,
        );
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_transfer_withdraw_with_negative_collateral() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1, base_amount: 1, base_asset_id: asset_id, quote_amount: -5, fee_amount: 0,
        );

    let order_user_2 = state
        .facade
        .create_order(
            user: user_2, base_amount: -1, base_asset_id: asset_id, quote_amount: 5, fee_amount: 0,
        );

    // Make trade.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -5,
            fee_a: 0,
            fee_b: 0,
        );

    // Transfer.
    let transfer_info = state
        .facade
        .transfer_request(sender: user_1, recipient: user_2, amount: 20);
    state.facade.transfer(:transfer_info);

    //                    TV                                  TR                 TV / TR
    //         COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:      -25 + 1 * 100 = 75                 1 * 100 * 0.01 = 1          75
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 75);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 1);

    // Withdraw.
    let withdraw_info = state.facade.withdraw_request(user: user_1, amount: 70);
    state.facade.withdraw(:withdraw_info);

    //                    TV                                  TR                 TV / TR
    //         COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:      -95 + 1 * 100 = 5                  1 * 100 * 0.01 = 1          5
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 1);
}

#[test]
fn test_withdraw_spot_collateral() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom asset configuration.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, :token);

    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account,
            :asset_id,
            position_id: user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Withdraw.
    let mut withdraw_info = state.facade.withdraw_spot_request(:user, :asset_id, amount: 15000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_reduce_synthetic() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![30].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1, base_amount: 1, base_asset_id: asset_id, quote_amount: -95, fee_amount: 0,
        );

    let mut order_user_2 = state
        .facade
        .create_order(
            user: user_2, base_amount: -1, base_asset_id: asset_id, quote_amount: 95, fee_amount: 0,
        );

    // Make trade.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -95,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -95 + 1 * 100 = 5                 |1 * 100 * 0.03| = 3          1.6
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 3 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -98 + 1 * 100 = 2                 |1 * 100 * 0.03| = 3          0.6
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    assert(
        state.facade.is_liquidatable(position_id: user_1.position_id), 'user is not liquidatable',
    );

    state.facade.deactivate_synthetic(synthetic_id: asset_id);
    state
        .facade
        .reduce_asset_position(
            position_id_a: user_1.position_id,
            position_id_b: user_2.position_id,
            base_asset_id: asset_id,
            base_amount_a: -1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:                2 + 0 = 2                      |0 * 100 * 0.03| = 0            -
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 0);
}

/// The following test checks the transitions between healthy, liquidatable and deleveragable by
/// using funding tick and price tick.
/// We do so in the following way:
/// User is healthy -> Funding tick occurs -> User is liquidatable -> Funding tick occurs -> User is
/// deleveragable -> Price tick occurs -> User is liquidatable -> Price tick occurs -> User is
/// healthy -> Price tick occurs -> User is deleveragable -> Funding tick occurs -> User is healthy.
#[test]
fn test_status_change_healthy_liquidatable_deleveragable() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_support_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_support_user);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -195,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 195,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 2,
            quote: -195,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -195 + 2 * 100 = 5                 2 * 100 * 0.01 = 2           2.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 2 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    advance_time(10000);
    new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 100 = -3                 2 * 100 * 0.01 = 2         -1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    state.facade.price_tick(asset_info: @synthetic_info, price: 102);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 102 = 1                 2 * 102 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    state.facade.price_tick(asset_info: @synthetic_info, price: 103);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 103 = 3                 2 * 103 * 0.01 = 2           1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    // Create orders.
    order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 1,
            quote: -100,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -303 + 3 * 100 = 6                 3 * 103 * 0.01 = 3            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);

    state.facade.price_tick(asset_info: @synthetic_info, price: 100);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -303 + 3 * 100 = -3                 3 * 100 * 0.01 = 3          -1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    advance_time(10000);
    new_funding_index = FundingIndex { value: FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -294 + 3 * 100 = 6                 3 * 100 * 0.01 = 3            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);

    // Create orders.
    order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 1,
            quote: -100,
            fee_a: 0,
            fee_b: 0,
        );
}

#[test]
fn test_status_change_by_deposit() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();

    // Deposit to users.
    let mut deposit_info_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -195,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 195,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 2,
            quote: -195,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -195 + 2 * 100 = 5                 2 * 100 * 0.01 = 2           2.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 100 = -3                 2 * 100 * 0.01 = 2         -1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    deposit_info_user = state
        .facade
        .deposit(
            depositor: primary_user.account,
            position_id: primary_user.position_id,
            quantized_amount: 4,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5

    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    deposit_info_user = state
        .facade
        .deposit(
            depositor: primary_user.account,
            position_id: primary_user.position_id,
            quantized_amount: 1,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -198 + 2 * 100 = 2                 2 * 100 * 0.01 = 2            1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -98 + 1 * 100 = 2                  1 * 100 * 0.01 = 1            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 1);
}

#[test]
fn test_status_change_by_transfer() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);
    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();
    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -195,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 195,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 2,
            quote: -195,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -195 + 2 * 100 = 5                 2 * 100 * 0.01 = 2           2.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);
    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 100 = -3                 2 * 100 * 0.01 = 2         -1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    let mut transfer_info = state
        .facade
        .transfer_request(sender: support_user, recipient: primary_user, amount: 4);
    state.facade.transfer(:transfer_info);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    transfer_info = state
        .facade
        .transfer_request(sender: support_user, recipient: primary_user, amount: 1);
    state.facade.transfer(:transfer_info);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -198 + 2 * 100 = 2                 2 * 100 * 0.01 = 2            1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -98 + 1 * 100 = 2                  1 * 100 * 0.01 = 1            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 1);
}

#[test]
fn test_status_change_by_trade() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);
    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();
    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 6,
            base_asset_id: asset_id,
            quote_amount: -594,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -6,
            base_asset_id: asset_id,
            quote_amount: 594,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 6,
            quote: -594,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -594 + 6 * 100 = 6                 6 * 100 * 0.01 = 6            1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 6);
    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 2 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -606 + 6 * 100 = -6                 6 * 100 * 0.01 = 6          -1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 6);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 104,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -104,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 104,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -502 + 5 * 100 = -2                5 * 100 * 0.01 = 5          -0.4
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 5);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 102,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -102,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 102,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -400 + 4 * 100 = 0                 4 * 100 * 0.01 = 4            0
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 0);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 4);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -300 + 3 * 100 = 0                 3 * 100 * 0.01 = 3            0
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 0);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 101,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -101,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 101,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 199,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -199,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -2,
            quote: 199,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 100 = 0                 0 * 100 * 0.01 = 0            -
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 0);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 0);
}

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_late_funding() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    advance_time(100000);
    let mut new_funding_index = FundingIndex { value: FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );
}

#[test]
#[should_panic(expected: 'INVALID_BASE_CHANGE')]
fn test_liquidate_change_sign() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 103);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let mut order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 3,
            base_asset_id: asset_id,
            quote_amount: -306,
            fee_amount: 0,
        );

    let mut order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -3,
            base_asset_id: asset_id,
            quote_amount: 305,
            fee_amount: 0,
        );

    // Make trade.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 3,
            quote: -305,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -305 + 3 * 103 = 3                  3 * 103 * 0.01 = 3.09        1.29
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 4);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    // Price tick.
    state.facade.price_tick(asset_info: @synthetic_info, price: 100);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -305 + 3 * 100 = -5                 3 * 100 * 0.01 = 3          -1.66

    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: -5);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    // Liquidate.
    order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: 5,
            base_asset_id: asset_id,
            quote_amount: -505,
            fee_amount: 0,
        );
    state
        .facade
        .liquidate(
            liquidated_user: user_1,
            liquidator_order: order_user_2,
            liquidated_base: -5,
            liquidated_quote: 505,
            liquidated_insurance_fee: 0,
            liquidator_fee: 0,
        );
}

#[test]
fn test_funding_index_rounding() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(asset_name: 'BTC', :risk_factor_data, oracles_len: 1);
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 1100,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 900);
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    let order_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    let order_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_1, order_info_b: order_2, base: 1, quote: -100, fee_a: 0, fee_b: 0,
        );

    // Collateral balance before is 1000 each.
    state.facade.validate_collateral_balance(user_1.position_id, 1000_i64.into());
    state.facade.validate_collateral_balance(user_2.position_id, 1000_i64.into());

    // funding tick of half
    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: FUNDING_SCALE / 2 };
    state
        .facade
        .funding_tick(
            funding_ticks: array![FundingTick { asset_id, funding_index: new_funding_index }]
                .span(),
        );

    /// Longer gets decremented by half, which rounds down to -1. Shorter gets incremented by half,
    /// which rounds down to 0.
    state.facade.validate_collateral_balance(user_1.position_id, 999_i64.into());
    state.facade.validate_collateral_balance(user_2.position_id, 1000_i64.into());

    // funding tick of minus half
    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: -FUNDING_SCALE / 2 };
    state
        .facade
        .funding_tick(
            funding_ticks: array![FundingTick { asset_id, funding_index: new_funding_index }]
                .span(),
        );

    /// Longer gets incremented by half, which rounds down to 0. Shorter gets decremented by half,
    /// which rounds down to -1.
    state.facade.validate_collateral_balance(user_1.position_id, 1000_i64.into());
    state.facade.validate_collateral_balance(user_2.position_id, 999_i64.into());
}

#[test]
#[should_panic(
    expected: "POSITION_IS_NOT_FAIR_DELEVERAGE position_id: PositionId { value: 101 } TV before -2, TR before 2, TV after 2, TR after 0",
)]
fn test_unfair_deleverage() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Create orders.
    // User willing to buy 2 synthetic assets for 168 (quote) + 20 (fee).
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -168,
            fee_amount: 20,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 168,
            fee_amount: 20,
        );

    // Make trades.
    // User recieves 2 synthetic asset for 168 (quote) + 20 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 2,
            quote: -168,
            fee_a: 20,
            fee_b: 20,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -188 + 2 * 100 = 12                 2 * 100 * 0.01 = 2           6
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 12);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 7 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -202 + 2 * 100 = -2                 2 * 100 * 0.01 = 2          - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -2);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -2,
            deleveraged_quote: 204,
        );
}

#[test]
fn test_spot_collateral_deposit_transfer_withdraw() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom spot collateral asset (not the base collateral).
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();
    snforge_std::set_balance(target: user_1.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: user_2.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral asset to user_1.
    let deposit_info_user_1 = state
        .facade
        .deposit_spot(
            depositor: user_1.account,
            :asset_id,
            position_id: user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Transfer partial amount from user_1 to user_2.
    let transfer_info = state
        .facade
        .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 40000);
    state.facade.transfer(:transfer_info);
    // Withdraw from user_1 (first withdrawal).
    let mut withdraw_info = state
        .facade
        .withdraw_spot_request(user: user_1, :asset_id, amount: 30000);
    state.facade.withdraw(withdraw_info: withdraw_info);

    // Withdraw from user_2 (second withdrawal).
    withdraw_info = state.facade.withdraw_spot_request(user: user_2, :asset_id, amount: 40000);
    state.facade.withdraw(withdraw_info: withdraw_info);

    // Verify final balances.
    let balance_user_1: i64 = state
        .facade
        .get_position_asset_balance(user_1.position_id, asset_id)
        .into();
    let balance_user_2: i64 = state
        .facade
        .get_position_asset_balance(user_2.position_id, asset_id)
        .into();

    // user_1: 100000 (deposit) - 40000 (transfer) - 30000 (withdraw) = 30000
    assert_eq!(balance_user_1, 30000_i64);
    // user_2: 40000 (transfer) - 40000 (withdraw) = 0
    assert_eq!(balance_user_2, 0_i64);
}

#[test]
fn test_liquidate_spot_collateral_after_price_drop() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_user, amount: 9500);
    state.facade.transfer(:transfer_info);

    // Position state after transfer (at price = 100):
    // Balances:
    //   - Base collateral: -9500 (negative from transfer)
    //   - Spot collateral: 9800 units (at price 100)
    // Calculations:
    //   TV = base_collateral + spot_collateral * spot_price
    //      = -9500 + (9800 * 100) = -9500 + 980000 = 970500
    //   TR = |spot_collateral * spot_price| * risk_factor
    //      = |9800 * 100| * 0.1 = 980000 * 0.1 = 98000
    //   TV/TR = 970500 / 98000 = 9.9 (healthy, > 1)
    state
        .facade
        .validate_total_value(
            position_id: liquidated_user.position_id, expected_total_value: 970500,
        );
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 98000);

    // Price drop makes position liquidatable.
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // Position state after price drop (at price = 1):
    // Balances:
    //   - Base collateral: -9500 (unchanged)
    //   - Spot collateral: 9800 units (at new price 1)
    // Calculations:
    //   TV = base_collateral + spot_collateral * spot_price
    //      = -9500 + (9800 * 1) = -9500 + 9800 = 300
    //   TR = |spot_collateral * spot_price| * risk_factor
    //      = |9800 * 1| * 0.1 = 9800 * 0.1 = 980
    //   TV/TR = 300 / 980 = 0.306 (liquidatable, 0 < TV/TR < 1)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 300);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 980);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::None,
        );

    // Liquidate spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );

    // Position state after liquidation (at price = 1):
    // Liquidation changes:
    //   - Spot collateral: 9800 - 9500 = 300 units (transferred to liquidator)
    //   - Base collateral: -9500 + 9600 - 100(fee) = 0 (received from liquidator)
    // Balances:
    //   - Base collateral: 0
    //   - Spot collateral: 300 units (at price 1)
    // Calculations:
    //   TV = base_collateral + spot_collateral * spot_price
    //      = 0 + (300 * 1) = 300
    //   TR = |spot_collateral * spot_price| * risk_factor
    //      = |300 * 1| * 0.1 = 300 * 0.1 = 30
    //   TV/TR = 300 / 30 = 10 (healthy, > 1)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 300);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 30);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
fn test_liquidate_spot_collateral_multiple_steps() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user.
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_user, amount: 9500);
    state.facade.transfer(:transfer_info);

    // Price drop makes position liquidatable.
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // First liquidation step.
    let liquidator_order_info_1 = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 4750,
            quote_amount: -4800,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info_1,
            actual_amount_spot_collateral: -4750,
            actual_amount_base_collateral: 4800,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 50,
        );

    // Position still liquidatable.
    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'still liquidatable',
    );

    // Second liquidation step.
    let liquidator_order_info_2 = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 4750,
            quote_amount: -4800,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info_2,
            actual_amount_spot_collateral: -4750,
            actual_amount_base_collateral: 4800,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 50,
        );

    // Position now healthy.
    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
#[should_panic(expected: 'INVALID_ASSET_TYPE')]
fn test_liquidate_spot_not_spot_asset() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create synthetic asset (not spot).
    let synthetic_info = AssetInfoTrait::new(asset_name: 'BTC', :risk_factor_data, oracles_len: 1);
    let synthetic_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Try to liquidate synthetic asset as spot - should fail.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: synthetic_id,
            base_amount: 1,
            quote_amount: -100,
            fee_amount: 1,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -1,
            actual_amount_base_collateral: 100,
            actual_liquidator_fee: 1,
            liquidated_fee_amount: 1,
        );
}

#[test]
fn test_liquidate_spot_exact_position_amount() {
    // Test liquidating exactly the full spot collateral amount in the position.
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    // At price 100: TV = -9700 + 10000*100 = 990300, TR = 10000*100*0.1 = 100000, ratio = 9.9
    // (healthy)
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_user, amount: 9700);
    state.facade.transfer(:transfer_info);

    // Price drop makes position liquidatable.
    // At price 1: TV = -9700 + 10000*1 = 300, TR = 10000*1*0.1 = 1000, ratio = 0.3 (liquidatable)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order for EXACTLY the full spot asset amount.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 10000, // Exactly the full spot collateral balance
            quote_amount: -10000,
            fee_amount: 100,
            receive_position_id: Option::None,
        );

    // Liquidate exactly the full spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -10000, // Exactly the full amount
            actual_amount_base_collateral: 10000,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );

    // Position should have zero spot collateral now.
    state
        .facade
        .validate_asset_balance(
            position_id: liquidated_user.position_id,
            asset_id: asset_id,
            expected_balance: 0_i64.into(),
        );

    // Position state after liquidation:
    // TV = -9700 + 10000 - 100 = 200 (positive, healthy)
    // TR = 0 (no assets)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 200);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
fn test_liquidate_to_empty_position() {
    // Test liquidating to an empty position.
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    // At price 100: TV = -10000 + 10000*100 = 990000, TR = 10000*100*0.1 = 100000, ratio = 9.9
    // (healthy)
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_user, amount: 10000);
    state.facade.transfer(:transfer_info);

    // Price drop makes position liquidatable.
    // At price 1: TV = -10000 + 10000*1 = 0, TR = 10000*1*0.1 = 1000, (liquidatable)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order for EXACTLY the full spot asset amount.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 10000, // Exactly the full spot collateral balance
            quote_amount: -10000,
            fee_amount: 100,
            receive_position_id: Option::None,
        );

    // Liquidate exactly the full spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -10000, // Exactly the full amount
            actual_amount_base_collateral: 10000,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 0,
        );

    // Position should have zero spot collateral now.
    state
        .facade
        .validate_asset_balance(
            position_id: liquidated_user.position_id,
            asset_id: asset_id,
            expected_balance: 0_i64.into(),
        );

    // Position state after liquidation:
    // TV = -10000 + 10000 - 100 = 0
    // TR = 0 (no assets)
    // TV = TR = 0 (healthy)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
#[should_panic(expected: 'INVALID_QUOTE_FEE_AMOUNT')]
fn test_liquidate_spot_very_small_amount() {
    // Test liquidating a very small amount fails due to invalid quote/fee ratio validation.
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 2000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_user, amount: 1900);
    state.facade.transfer(:transfer_info);

    // Price drop makes position liquidatable.
    // At price 1: TV = -1900 + 2000*1 = 100, TR = 2000*1*0.1 = 200, ratio = 0.5 (liquidatable)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order for a VERY SMALL amount (1 unit) with high fee.
    // This should FAIL because fee (100) > collateral received (2), making TV worse
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 1, // Very small amount
            quote_amount: -2,
            fee_amount: 1,
            receive_position_id: Option::None,
        );

    // This should pass: TV_before = 100, TV_after = -1900 + 2 - 1 + 1999*1 = 100
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -1, // Very small amount
            actual_amount_base_collateral: 2,
            actual_liquidator_fee: 1,
            liquidated_fee_amount: 1 // Large fee makes it worse!
        );

    // This should fail: TV_before = 100, TR_before = 199.9
    // TV_after = -1900 + 2 - 2 + 1998*1 = 98, TR_after = 1998*1*0.1 = 199.8
    // TV_after / TR_after = 98 / 199.8 = 0.4905 < TV_before / TR_before = 100 / 199.9 = 0.5005
    // This is not healthier.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -1,
            actual_amount_base_collateral: 2,
            actual_liquidator_fee: 2,
            liquidated_fee_amount: 2,
        );
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_liquidate_spot_deleveragable_position() {
    // Test that liquidating a deleveragable position (TV < 0) fails validation.
    // This is expected behavior - the "healthy or healthier" validation correctly rejects this.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 2000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create LARGE negative base collateral for liquidated user via transfer.
    // This will make TV negative after price drop (deleveragable state).
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_user, amount: 3000);
    state.facade.transfer(:transfer_info);

    // Price drop makes position deleveragable (TV < 0).
    // At price 1: TV = -3000 + 2000*1 = -1000 (deleveragable!)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // Verify position has negative TV (deleveragable state).
    state
        .facade
        .validate_total_value(
            position_id: liquidated_user.position_id, expected_total_value: -1000,
        );

    // Create liquidator order.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 2000,
            quote_amount: -2000,
            fee_amount: 10,
            receive_position_id: Option::None,
        );

    // This should FAIL because TR is zero and position not healthy.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -2000,
            actual_amount_base_collateral: 2000,
            actual_liquidator_fee: 10,
            liquidated_fee_amount: 10,
        );
}

#[test]
#[should_panic(expected: 'INVALID_ASSET_TYPE')]
fn test_liquidate_spot_for_vault_share_asset() {
    // Test that liquidate_spot_asset fails when trying to liquidate a vault share asset.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create vault.
    let vault_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Try to liquidate vault share asset using liquidate_spot_asset - should fail.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: vault_config.asset_id,
            base_amount: 100,
            quote_amount: -100,
            fee_amount: 1,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -100,
            actual_amount_base_collateral: 100,
            actual_liquidator_fee: 1,
            liquidated_fee_amount: 1,
        );
}

#[test]
fn test_liquidate_spot_with_different_source_and_receive_positions() {
    // Test that spot liquidation works when the liquidator order has different
    // source_position (paying base collateral) and receive_position (receiving spot assets).
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_source_user = state.new_user_with_position(); // Pays base collateral
    let liquidator_receive_user = state.new_user_with_position(); // Receives spot collateral
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator source position.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_source_user.account,
            position_id: liquidator_source_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    let transfer_info = state
        .facade
        .transfer_request(sender: liquidated_user, recipient: liquidator_source_user, amount: 9500);
    state.facade.transfer(:transfer_info);

    // Position state after transfer (at price = 100):
    // TV = -9500 + (9800 * 100) = 970500
    // TR = 9800 * 100 * 0.1 = 98000
    // TV/TR = 9.9 (healthy)
    state
        .facade
        .validate_total_value(
            position_id: liquidated_user.position_id, expected_total_value: 970500,
        );
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 98000);

    // Price drop makes position liquidatable.
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // Position state after price drop (at price = 1):
    // TV = -9500 + (9800 * 1) = 300
    // TR = 9800 * 1 * 0.1 = 980
    // TV/TR = 0.306 (liquidatable)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 300);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 980);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order with different source and receive positions.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_source_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::Some(liquidator_receive_user.position_id),
        );

    // Record balances before liquidation.
    let source_balance_before: i64 = state
        .facade
        .get_position_collateral_balance(liquidator_source_user.position_id)
        .into();
    let receive_spot_balance_before: i64 = state
        .facade
        .get_position_asset_balance(liquidator_receive_user.position_id, asset_id)
        .into();

    // Liquidate spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );

    // Verify source position paid base collateral.
    // source_balance: 200000 - 9600 - 100 (fee) = 190300
    let source_balance_after: i64 = state
        .facade
        .get_position_collateral_balance(liquidator_source_user.position_id)
        .into();
    assert_eq!(source_balance_after, source_balance_before - 9600 - 100);

    // Verify receive position got spot collateral.
    // receive_spot_balance: 0 + 9500 = 9500
    let receive_spot_balance_after: i64 = state
        .facade
        .get_position_asset_balance(liquidator_receive_user.position_id, asset_id)
        .into();
    assert_eq!(receive_spot_balance_after, receive_spot_balance_before + 9500);

    // Verify liquidated position state after liquidation (at price = 1):
    // Spot collateral: 9800 - 9500 = 300
    // Base collateral: -9500 + 9600 - 100(fee) = 0
    // TV = 0 + (300 * 1) = 300
    // TR = 300 * 1 * 0.1 = 30
    // TV/TR = 10 (healthy)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 300);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 30);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
#[should_panic(expected: ('INVALID_INTEREST_RATE',))]
fn test_apply_interest_to_position_with_zero_balance() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    let BALANCE = 10_000;

    // Deposit some collateral
    let deposit_info = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: BALANCE,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    // Test uninitialized positions.
    snforge_std::interact_with_state(
        state.facade.perpetuals_contract,
        || {
            let mut state = perpetuals::core::core::Core::contract_state_for_testing();

            state
                .positions
                .positions
                .entry(user_1.position_id)
                .last_interest_applied_time
                .write(Timestamp { seconds: 0 });
            state
                .positions
                .positions
                .entry(user_2.position_id)
                .last_interest_applied_time
                .write(Timestamp { seconds: 0 });
        },
    );

    // Apply zero interest to position with balance (first time, timestamp is zero)
    let position_ids = array![user_1.position_id].span();
    let interest_amounts = array![0].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);

    // Advance time by 1 hour
    advance_time(seconds: HOUR);

    let position_ids = array![user_1.position_id, user_2.position_id].span();
    let interest_amounts = array![100, 100].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);
}

#[test]
fn test_apply_interest_to_multiple_positions() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Deposit collateral to both users
    let deposit_info_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 10_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_a);

    let deposit_info_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 5_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_b);

    // Advance time by 1 hour
    advance_time(seconds: HOUR);

    // Calculate valid interest amounts for both positions
    let balance_a: u128 = 10_000;
    let balance_b: u128 = 5_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed_a: u128 = (balance_a * time_diff * max_rate) / scale;
    let max_allowed_b: u128 = (balance_b * time_diff * max_rate) / scale;

    // Apply valid interest to both positions
    let interest_a: i64 = (max_allowed_a / 2).try_into().unwrap();
    let interest_b: i64 = (max_allowed_b / 2).try_into().unwrap();
    let position_ids = array![user_a.position_id, user_b.position_id].span();
    let interest_amounts = array![interest_a, interest_b].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);

    // Validate balances
    let expected_balance_a: i64 = 10_000 + interest_a;
    let expected_balance_b: i64 = 5_000 + interest_b;
    state.facade.validate_collateral_balance(user_a.position_id, expected_balance_a.into());
    state.facade.validate_collateral_balance(user_b.position_id, expected_balance_b.into());
}

#[test]
#[should_panic(expected: ('INVALID_INTEREST_RATE',))]
fn test_apply_interest_exceeds_max_rate() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Advance time by 1 hour
    advance_time(seconds: HOUR);

    // Calculate max allowed interest
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;

    // Try to apply interest that exceeds max rate
    let invalid_interest: i64 = (max_allowed + 1).try_into().unwrap();
    let position_ids = array![user.position_id].span();
    let interest_amounts = array![invalid_interest].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);
}

#[test]
#[should_panic(expected: ('INVALID_INTEREST_RATE',))]
fn test_apply_non_zero_interest_to_zero_balance() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Don't deposit anything, pnl is zero.

    // Try to apply non-zero interest to zero balance (first time)
    let position_ids = array![user.position_id].span();
    let interest_amounts = array![100_i64].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);
}

#[test]
fn test_apply_negative_interest() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Advance time by 1 hour
    advance_time(seconds: HOUR);

    // Calculate valid interest amount (negative)
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;

    // Apply valid negative interest
    let valid_interest: i64 = -(max_allowed / 2).try_into().unwrap();
    let position_ids = array![user.position_id].span();
    let interest_amounts = array![valid_interest].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);

    // Balance should decrease
    let expected_balance: i64 = 10_000 + valid_interest;
    state.facade.validate_collateral_balance(user.position_id, expected_balance.into());
}

#[test]
fn test_apply_interest_sequential_updates() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Advance time by 1 hour
    advance_time(seconds: HOUR);

    // Calculate and apply first interest
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;
    let interest_1: i64 = (max_allowed / 2).try_into().unwrap();
    let position_ids = array![user.position_id].span();
    let interest_amounts = array![interest_1].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);

    let balance_after_first: i64 = 10_000 + interest_1;
    state.facade.validate_collateral_balance(user.position_id, balance_after_first.into());

    // Advance time by another hour
    advance_time(seconds: HOUR);

    // Calculate and apply second interest (based on new balance)
    let new_balance: u128 = balance_after_first.try_into().unwrap();
    let max_allowed_2: u128 = (new_balance * time_diff * max_rate) / scale;
    let interest_2: i64 = (max_allowed_2 / 2).try_into().unwrap();
    let interest_amounts = array![interest_2].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);

    let expected_final_balance: i64 = balance_after_first + interest_2;
    state.facade.validate_collateral_balance(user.position_id, expected_final_balance.into());
}

#[test]
#[should_panic(expected: ('INVALID_INTEREST_RATE',))]
fn test_apply_interest_twice_without_advancing_time() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Calculate and apply first interest
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;
    let interest_1: i64 = (max_allowed / 2).try_into().unwrap();

    let position_ids = array![user.position_id].span();
    let interest_amounts = array![interest_1].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);

    // Since time hasn't advanced, time_diff will be 0, so max_allowed_change will be 0
    // Any non-zero interest should fail with INVALID_INTEREST_RATE
    let interest_amounts = array![interest_1].span();
    state.facade.apply_interests(:position_ids, :interest_amounts);
}

#[test]
#[should_panic(expected: 'INVALID_BASE_CHANGE')]
fn test_withdraw_spot_collateral_negative_balance() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create user.
    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, :token);

    // Deposit base collateral (USDC) to ensure position stays healthy.
    // This ensures the position health validation passes and we hit the specific
    // spot balance validation we're testing.
    let deposit_info_base = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 200000);
    state.facade.process_deposit(deposit_info: deposit_info_base);

    // Deposit 1000 units of spot collateral to user.
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account,
            :asset_id,
            position_id: user.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Verify user has 1000 units of spot collateral.
    state
        .facade
        .validate_asset_balance(
            position_id: user.position_id, asset_id: asset_id, expected_balance: 1000_i64.into(),
        );

    // Attempt to withdraw 1500 units (more than available) - should panic with
    // INVALID_BASE_CHANGE.
    // The position has enough base collateral to stay healthy, so the validation
    // should fail specifically on the spot balance check.
    let withdraw_info = state.facade.withdraw_spot_request(:user, :asset_id, amount: 1500);
    state.facade.withdraw(:withdraw_info);
}

#[test]
#[should_panic(expected: 'NOT_TRANSFERABLE_ASSET')]
fn test_transfer_synthetic_asset_fails() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users - give user_1 plenty of collateral to stay healthy.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders to give user_1 a small synthetic position.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -1000,
            fee_amount: 0,
        );

    let order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -10,
            base_asset_id: asset_id,
            quote_amount: 1000,
            fee_amount: 0,
        );

    // Make trade.
    // User 1 position: collateral = 99000, synthetic = 10
    // TV = 99000 + 10*100 = 100000, TR = 10*100*0.01 = 10, TV/TR = 10000 (very healthy)
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 10,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // Verify user_1 is very healthy before attempting transfer.
    state
        .facade
        .validate_total_value(position_id: user_1.position_id, expected_total_value: 100000);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 10);

    // Try to transfer synthetic asset - should fail with NOT_TRANSFERABLE_ASSET
    // before any health checks.
    state
        .facade
        .transfer(
            transfer_info: state
                .facade
                .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 5),
        );
}

#[test]
#[should_panic(expected: 'INVALID_BASE_CHANGE')]
fn test_transfer_spot_collateral_negative_balance_fails() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();
    snforge_std::set_balance(target: user_1.account.address, new_balance: 5000000, :token);

    // User 1 deposits plenty of base collateral to ensure position stays healthy.
    let deposit_info_base = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_base);

    // User 1 deposits only 1000 units of spot collateral.
    let deposit_info_spot = state
        .facade
        .deposit_spot(
            depositor: user_1.account,
            :asset_id,
            position_id: user_1.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_spot);

    // Position before transfer:
    // Base collateral: 200000
    // Spot collateral: 1000 (at price 100, value = 100000, with 0.01 risk factor, TR = 1000)
    // TV = 200000 + 100000 = 300000, TR = 1000, TV/TR = 300 (very healthy)

    // If we could transfer 1500 spot collateral (which we can't):
    // Base collateral: 200000 (unchanged)
    // Spot collateral: -500 (invalid!)
    // But hypothetically, TV = 200000 + (-500*100) = 150000, TR = 500*100*0.01 = 500
    // TV/TR = 300 (still very healthy if this were allowed)

    // Try to transfer more spot collateral than user_1 has - should fail with INVALID_BASE_CHANGE
    // before health check because balance would go negative.
    state
        .facade
        .transfer(
            transfer_info: state
                .facade
                .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 1500),
        );
}
