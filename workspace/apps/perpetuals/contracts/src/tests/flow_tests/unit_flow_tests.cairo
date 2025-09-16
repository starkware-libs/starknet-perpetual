use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils::constants::MAX_U128;

#[test]
fn test_deleverage_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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

    state.facade.price_tick(synthetic_info: @synthetic_info, price: 10);

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
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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

    state.facade.price_tick(synthetic_info: @synthetic_info, price: 20);

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
    let synthetic_info = SyntheticInfoTrait::new(
        asset_name: 'BTC', :risk_factor_data, oracles_len: 1,
    );
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
fn test_transfer_withdraw_with_negative_collateral() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = SyntheticInfoTrait::new(
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
fn test_reduce_synthetic() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![30].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = SyntheticInfoTrait::new(
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
        .reduce_inactive_asset_position(
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
    let synthetic_info = SyntheticInfoTrait::new(
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

    state.facade.price_tick(synthetic_info: @synthetic_info, price: 102);
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

    state.facade.price_tick(synthetic_info: @synthetic_info, price: 103);
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

    state.facade.price_tick(synthetic_info: @synthetic_info, price: 100);
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
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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
    let synthetic_info = SyntheticInfoTrait::new(
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
    state.facade.price_tick(synthetic_info: @synthetic_info, price: 100);

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
    let synthetic_info = SyntheticInfoTrait::new(
        asset_name: 'BTC', :risk_factor_data, oracles_len: 1,
    );
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



use perpetuals::core::core::Core::{InternalCoreFunctions, SNIP12MetadataImpl};
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait, Settlement};
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::PositionId;
use perpetuals::tests::constants::*;
use snforge_std::DeclareResultTrait;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use starknet::ContractAddress;
use starkware_utils::components::replaceability::interface::{
    IReplaceableDispatcher, IReplaceableDispatcherTrait, ImplementationData,
};
use starkware_utils::storage::iterable_map::*;
use starkware_utils::time::time::Timestamp;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

/// tx: 0x07b042c11b78c947b958f5559f40feac97866bc8b1ecc9ec62818f1a1b177586 (12 trades)
/// block number: 1844545
/// gas : 5940188809(L2)

#[test]
#[fork(
    url: "https://starknet-mainnet.blastapi.io/22f0d577-04d4-49c0-ad0d-77dd531b0351/rpc/v0_8",
    block_number: 1844544,
)]
fn test_profile() {
    let caller_address: ContractAddress =
        0x048ddc53f41523d2a6b40c3dff7f69f4bbac799cd8b2e3fc50d3de1d4119441f
        .try_into()
        .unwrap();

    let contract_address: ContractAddress =
        0x062da0780fae50d68cecaa5a051606dc21217ba290969b302db4dd99d2e9b470
        .try_into()
        .unwrap();
    let dispatcher = ICoreDispatcher { contract_address };

    // Replace class hash:
    let core_contract = (*snforge_std::declare("Core").unwrap().contract_class()).class_hash;

    let re = IReplaceableDispatcher { contract_address };
    let implementation_data = ImplementationData {
        impl_hash: core_contract, eic_data: Option::None, final: false,
    };
    let deployer: ContractAddress =
        0x0522e5ba327bfbd85138b29bde060a5340a460706b00ae2e10e6d2a16fbf8c57
        .try_into()
        .unwrap();
    cheat_caller_address_once(:contract_address, caller_address: deployer);
    re.add_new_implementation(:implementation_data);
    cheat_caller_address_once(:contract_address, caller_address: deployer);
    re.replace_to(:implementation_data);

    let trade_1 = Settlement {
        signature_a: array![
            0x71fedaf53734966afd09513c40f50036bb742c06eef36c41e2aaa0d74022f99,
            0x71be0b92594231bdf28698d9beec79f0a68daa103f5dc57347925c63f76643c,
        ]
            .span(),
        signature_b: array![
            0x60a98b1e87f6e434331dc3f194afbb1f9bfdcc24e6099533ee9a02efc765275,
            0x4ed771fdfb4e5941f8c5daafc698ca78644a19212262cca7235faa7390b4a98,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x19f1b.try_into().unwrap() },
            base_asset_id: 0x485950452d33000000000000000000.into(),
            base_amount: 0x3a98.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffb13ce231
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x50a71.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933e295.try_into().unwrap() },
            salt: 0x50a705a3.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x30d7e.try_into().unwrap() },
            base_asset_id: 0x485950452d33000000000000000000.into(),
            base_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffffffe599
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x11d0c058.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0xe983.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd405a.try_into().unwrap() },
            salt: 0x3a3590e6.into(),
        },
        actual_amount_base_a: 0xfa,
        actual_amount_quote_a: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff57554b
            .try_into()
            .unwrap(),
        actual_fee_a: 0xacb,
        actual_fee_b: 0x0,
    };

    let trade_2 = Settlement {
        signature_a: array![
            0x7ca1d5af750dad6cfc97ac20fe45ea2a4a7269e18fd8fe8fb9243b62fce6aa5,
            0x357038901909841f6ed4930a769442fa042033c1a89db6539ae0896fd875fcf,
        ]
            .span(),
        signature_b: array![
            0x453eaeac0fccb0084931b0dcfb88bc70cc9889158cb09a7bc6b2abc8ca3cd10,
            0x5cf4778b3fdf08ce858b98c1e836c4ed543319a00630da481ba29a75ffe0c10,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x31303.try_into().unwrap() },
            base_asset_id: 0x4554482d3400000000000000000000.into(),
            base_amount: 0x48a8.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffbe1cf7101
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x3cb8a9.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f115.try_into().unwrap() },
            salt: 0x5dca0f41.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x30d7e.try_into().unwrap() },
            base_asset_id: 0x4554482d3400000000000000000000.into(),
            base_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffffffef85
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x780e5830.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x6259a.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd406b.try_into().unwrap() },
            salt: 0x4dda9a9.into(),
        },
        actual_amount_base_a: 0x136,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff72e4389
            .try_into()
            .unwrap(),
        actual_fee_a: 0x820b,
        actual_fee_b: 0x0,
    };

    let trade_3 = Settlement {
        signature_a: array![
            0xb2d7c5904593c6c37a03015c803762f23525c89abaa21cf2c4bb6674563dc4,
            0x78e9490d089c20c2be23ec6d661682d804db8bb8ee0aa38a4ff04506b9d0228,
        ]
            .span(),
        signature_b: array![
            0x4a93a8c9c5b961732a64ae6e6d35eec73faad38117388a27aa445cbdbb89b71,
            0x415e7e909a133da5eacfdb255fea2868f0e96c46247a6717e69860fb3501e5f,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x30d7e.try_into().unwrap() },
            base_asset_id: 0x4254432d3600000000000000000000.into(),
            base_amount: 0xa3c.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffee0d90b1
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0xeb3d.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd406a.try_into().unwrap() },
            salt: 0x9b1f91a.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x31303.try_into().unwrap() },
            base_asset_id: 0x4254432d3600000000000000000000.into(),
            base_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffffff0237
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0xfdca.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0xf.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f12e.try_into().unwrap() },
            salt: 0x9756924.into(),
        },
        actual_amount_base_a: 0x438,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff89a1c61
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0x6d16,
    };

    let trade_4 = Settlement {
        signature_a: array![
            0x5736fc7eab84bd1e6abd49c56aee0549f1a673a457f8cae0492557374699664,
            0x75715f143a8fe53d3f34e683d114ea4e8e805bc08ddfc81e5520910a9a2cef0,
        ]
            .span(),
        signature_b: array![
            0x43eec775b9f5480933bd44cfcd348a2097ccd69dc5f1de9a1421ad66de26177,
            0x130cb5847bf80846c707e7535900c02809abdebf9362c58e9fc335ec05a2be1,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x5452554d502d310000000000000000.into(),
            base_amount: 0x2710.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffbf229f701
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x3bc784.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f223.try_into().unwrap() },
            salt: 0x3918958b.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x1f4.try_into().unwrap() },
            base_asset_id: 0x5452554d502d310000000000000000.into(),
            base_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffffff935f
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x5a46fe8d0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0xb8e351.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd402d.try_into().unwrap() },
            salt: 0x7ba67460.into(),
        },
        actual_amount_base_a: 0xfa,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff303df71
            .try_into()
            .unwrap(),
        actual_fee_a: 0xbf78,
        actual_fee_b: 0x0,
    };

    let trade_5 = Settlement {
        signature_a: array![
            0x07e41bed15c380c3108667edda28624032fbb3f4629abffbd20c4d9627d9339,
            0x2992d95aaaf842f5c4dd692530c99d2718d0fae9a1ae49057a0a9aee59c601d,
        ]
            .span(),
        signature_b: array![
            0x34424f9d844e76e6fa024371d174678944ae4c0651c00d6ce12d3be006894bf,
            0x72f359e6175463da2f97c0ef462828d046ad5008bba22d46993eaa9f2b2a83a,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x454e412d3000000000000000000000.into(),
            base_amount: 0x2710.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffcb0752cc1
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x30d185.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f2eb.try_into().unwrap() },
            salt: 0x1b37382b.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x30d7e.try_into().unwrap() },
            base_asset_id: 0x454e412d3000000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffe5d
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x11cc6328.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0xe94a.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd406a.try_into().unwrap() },
            salt: 0x6894e2cc.into(),
        },
        actual_amount_base_a: 0xfa,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff567dd5d
            .try_into()
            .unwrap(),
        actual_fee_a: 0x9c38,
        actual_fee_b: 0x0,
    };

    let trade_6 = Settlement {
        signature_a: array![
            0x0357f8bad89fac0d175a5e9c77b076345e82a96cec0ef19b477c1d14ff9df1f5,
            0x070395b018d69c8721a9da7dde732190070abee1007560205d34b6abb96e466,
        ]
            .span(),
        signature_b: array![
            0x144a30993fb087dc7704eeb4df2ec0dd7745c916515e8fef3b7cdbdf0902769,
            0x177266c9238757be2a12765c549d5297b44f5ed531e5d7a45964c459fcc1c21,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x1f4.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x96.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff385817
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x198f.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4012.try_into().unwrap() },
            salt: 0x328da974.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffddd21
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x222e0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x20.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f456.try_into().unwrap() },
            salt: 0x0ba3b07a.into(),
        },
        actual_amount_base_a: 0x96,
        actual_amount_quote_a: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff385817
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0xb80,
    };

    let trade_7 = Settlement {
        signature_a: array![
            0x01458cfe61f5710e270b2543ea2cba99ae90e7d0dbef931ff15276248818d82a,
            0x009e91b106564240139de5f1a23ecce57bc9986b0ee37a6f08cb7ca9ccf7fe58,
        ]
            .span(),
        signature_b: array![
            0x144a30993fb087dc7704eeb4df2ec0dd7745c916515e8fef3b7cdbdf0902769,
            0x177266c9238757be2a12765c549d5297b44f5ed531e5d7a45964c459fcc1c21,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x1f4.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x8c.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff45aea9
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x17da.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4012.try_into().unwrap() },
            salt: 0x5daac4c0.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffddd21
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x222e0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x20.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f456.try_into().unwrap() },
            salt: 0x0ba3b07a.into(),
        },
        actual_amount_base_a: 0x8c,
        actual_amount_quote_a: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff45aea9
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0xabb,
    };

    let trade_8 = Settlement {
        signature_a: array![
            0x0d8841227b8c16ed1702b780ff19dedc17f4dfe5e82f286798e8aa4113627e2,
            0x0641bb275fbd425eb1bb19ea8c04713a016625765898f14e433f77dee0bafdb1,
        ]
            .span(),
        signature_b: array![
            0x144a30993fb087dc7704eeb4df2ec0dd7745c916515e8fef3b7cdbdf0902769,
            0x177266c9238757be2a12765c549d5297b44f5ed531e5d7a45964c459fcc1c21,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x1f4.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x78.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff6052a9
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x1471.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4012.try_into().unwrap() },
            salt: 0x7a78a72e.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffddd21
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x222e0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x20.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f456.try_into().unwrap() },
            salt: 0x0ba3b07a.into(),
        },
        actual_amount_base_a: 0x78,
        actual_amount_quote_a: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffff6052a9
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0x932,
    };

    let trade_9 = Settlement {
        signature_a: array![
            0x39c797bc172b26b479d3fd9a1f49f48d347173a5609b39e95d52be7015c55ee,
            0x18fea8abc691a8ecc63a69ae487810beefda7c9a359760ff4d937683ebffede,
        ]
            .span(),
        signature_b: array![
            0x144a30993fb087dc7704eeb4df2ec0dd7745c916515e8fef3b7cdbdf0902769,
            0x177266c9238757be2a12765c549d5297b44f5ed531e5d7a45964c459fcc1c21,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x1a55c.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x3ca.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffaf555f7
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x0.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4de9.try_into().unwrap() },
            salt: 0xe33f4f60.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffddd21
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x222e0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x20.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f456.try_into().unwrap() },
            salt: 0x0ba3b07a.into(),
        },
        actual_amount_base_a: 0x3ca,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffaf555f7
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0x4a57,
    };

    let trade_10 = Settlement {
        signature_a: array![
            0x7c78d4aec7fa7050eae731e419a2b92073bc5cff23329037004fff22d8d0906,
            0x5ba95166f4cbc1db27d7a4133ee14b9acbe08aebc18b1e0ac410c4b945e7206,
        ]
            .span(),
        signature_b: array![
            0x144a30993fb087dc7704eeb4df2ec0dd7745c916515e8fef3b7cdbdf0902769,
            0x177266c9238757be2a12765c549d5297b44f5ed531e5d7a45964c459fcc1c21,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x186b0.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0xb392.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffff1113f777
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x1e9500.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd421e.try_into().unwrap() },
            salt: 0x795044b2.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x19cb3.try_into().unwrap() },
            base_asset_id: 0x424e422d3400000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffddd21
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x222e0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x20.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x6933f456.try_into().unwrap() },
            salt: 0x0ba3b07a.into(),
        },
        actual_amount_base_a: 0x3b6,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffb100163
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0x48ce,
    };

    let trade_11 = Settlement {
        signature_a: array![
            0xa948e156fc6da0325347f59945bd391b89c88f9331d6604d7cf7320457a754,
            0x2c33af82050d54489afa61a5e5be82103ce9add9af06807d1266aec9ac95da6,
        ]
            .span(),
        signature_b: array![
            0x4ba7bf04ebbbea4b71aa8a8cdd00744d4bdad1a04f274a1fb7b5ad6905e0b46,
            0x70840bc4c3080c29d9b7d8932f455f79fa33dd8f3fdf363eb5fe58a85b3fbbc,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x1f9.try_into().unwrap() },
            base_asset_id: 0x4144412d3100000000000000000000.into(),
            base_amount: 0x10e.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffe88adf9
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x300b.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4030.try_into().unwrap() },
            salt: 0x75290385.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x18829.try_into().unwrap() },
            base_asset_id: 0x4144412d3100000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffff98f
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x8f0d75c.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x0.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4dfe.try_into().unwrap() },
            salt: 0xe4cc404e.into(),
        },
        actual_amount_base_a: 0x10e,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffe89765d
            .try_into()
            .unwrap(),
        actual_fee_a: 0x17f8,
        actual_fee_b: 0x0,
    };

    let trade_12 = Settlement {
        signature_a: array![
            0x28d2e8fb1e9fde97bf6db1e432190486cfb2d7d1039993a2146cf24248573cf,
            0x7d5cc648ac7b183a0e9dad938fa60961cfc51312aba6d872d531ad23100bf5a,
        ]
            .span(),
        signature_b: array![
            0x486fa727c5fd8e06ea32675fa9a6f7d49540f2c78db8faaf43aa512823a7b19,
            0x1a355a412f62144fe9500ab42e07e2ad6892937abb689581b7fd613224b3399,
        ]
            .span(),
        order_a: Order {
            position_id: PositionId { value: 0x18829.try_into().unwrap() },
            base_asset_id: 0x5749462d3100000000000000000000.into(),
            base_amount: 0x69a.try_into().unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff71445a1
                .try_into()
                .unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x0.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4e07.try_into().unwrap() },
            salt: 0xd40cdf0b.into(),
        },
        order_b: Order {
            position_id: PositionId { value: 0x1f9.try_into().unwrap() },
            base_asset_id: 0x5749462d3100000000000000000000.into(),
            base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffe99
                .try_into()
                .unwrap(),
            quote_asset_id: 0x1.into(),
            quote_amount: 0x1e5c2b0.try_into().unwrap(),
            fee_asset_id: 0x1.into(),
            fee_amount: 0x3e2e.try_into().unwrap(),
            expiration: Timestamp { seconds: 0x68bd4032.try_into().unwrap() },
            salt: 0x2b1f3065.into(),
        },
        actual_amount_base_a: 0x168,
        actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffe198681
            .try_into()
            .unwrap(),
        actual_fee_a: 0x0,
        actual_fee_b: 0x1f22,
    };

    cheat_caller_address_once(:contract_address, :caller_address);

    let operator_nonce: u64 = 3486792;

    // let trade_result = dispatcher
    //     .trade(
    //         :operator_nonce,
    //         signature_a: trade_1.signature_a,
    //         signature_b: trade_1.signature_b,
    //         order_a: trade_1.order_a,
    //         order_b: trade_1.order_b,
    //         actual_amount_base_a: trade_1.actual_amount_base_a,
    //         actual_amount_quote_a: trade_1.actual_amount_quote_a,
    //         actual_fee_a: trade_1.actual_fee_a,
    //         actual_fee_b: trade_1.actual_fee_b,
    //     );

    // let trade_result = dispatcher
    //     .trade(
    //         operator_nonce: operator_nonce + 1,
    //         signature_a: trade_2.signature_a,
    //         signature_b: trade_2.signature_b,
    //         order_a: trade_2.order_a,
    //         order_b: trade_2.order_b,
    //         actual_amount_base_a: trade_2.actual_amount_base_a,
    //         actual_amount_quote_a: trade_2.actual_amount_quote_a,
    //         actual_fee_a: trade_2.actual_fee_a,
    //         actual_fee_b: trade_2.actual_fee_b,
    //     );

    let trades: Span<Settlement> = array![trade_1,
    trade_2,
    trade_3,
    trade_4,
    trade_5,
    trade_6,
    trade_7,
    trade_8,
    trade_9,
    trade_10,
    trade_11,
    trade_12,
    ].span();

    dispatcher.multi_trade(:operator_nonce, trades: trades);
    // let mut index = 0;

    // for _trade in trades {
    // cheat_caller_address_once(:contract_address, :caller_address);
    // let trade = *_trade;
    // let x = dispatcher.get_position_tv_tr(position_id: trade.order_a.position_id);
    // let y = dispatcher.get_position_tv_tr(position_id: trade.order_b.position_id);
    // let trade_result = dispatcher
    //     .trade(
    //         operator_nonce: operator_nonce + index,
    //         signature_a: trade.signature_a,
    //         signature_b: trade.signature_b,
    //         order_a: trade.order_a,
    //         order_b: trade.order_b,
    //         actual_amount_base_a: trade.actual_amount_base_a,
    //         actual_amount_quote_a: trade.actual_amount_quote_a,
    //         actual_fee_a: trade.actual_fee_a,
    //         actual_fee_b: trade.actual_fee_b,
    //     );
    // index = index + 1;
// }
}
