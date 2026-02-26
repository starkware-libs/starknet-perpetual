use perpetuals::core::components::exchange_time::interface::{
    IExchangeTimeDispatcher, IExchangeTimeDispatcherTrait,
};
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::start_cheat_block_timestamp_global;
use starkware_utils::constants::{DAY, WEEK};
use starkware_utils::time::time::Time;

#[test]
#[should_panic(expected: 'STALE_TIME')]
fn test_exchange_time_cannot_drift_too_much() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let future_timestamp = Time::now().add(Time::seconds(360));
    let dispatcher = IExchangeTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_exchange_time(operator_nonce: 0, new_timestamp: future_timestamp);
}

#[test]
#[should_panic(expected: 'NON_MONOTONIC_TIME')]
fn test_exchange_time_set_past_time() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let past_timestamp = Time::now().sub_delta(Time::seconds(1));
    let dispatcher = IExchangeTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_exchange_time(operator_nonce: 0, new_timestamp: past_timestamp);
}

#[test]
#[should_panic(expected: 'NON_MONOTONIC_TIME')]
fn test_exchange_time_must_be_monotonically_increasing() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.advance_time(0);
}

#[test]
fn test_exchange_time_can_drift_a_bit() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.advance_time(1);

    let future_timestamp = Time::now().add(Time::seconds(100));
    let dispatcher = IExchangeTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_exchange_time(1, future_timestamp);
}

#[test]
#[should_panic(expected: 'TIMESTAMP_TOO_OLD')]
fn test_update_exchange_time_cannot_be_more_than_week_in_past() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Advance block timestamp forward by 2 weeks
    let future_block_time = Time::now().add(Time::seconds(WEEK * 2));
    start_cheat_block_timestamp_global(future_block_time.into());

    // Try to update exchange time to a value that's more than a week in the past
    // (relative to the new block timestamp)
    let past_timestamp = future_block_time.sub_delta(Time::seconds(WEEK + 1));
    let dispatcher = IExchangeTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_exchange_time(operator_nonce: 0, new_timestamp: past_timestamp);
}

#[test]
#[should_panic(expected: 'TIMESTAMP_TOO_OLD')]
fn test_apply_interests_fails_when_last_exchange_update_more_than_day_in_past() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Advance block timestamp forward by 2 days (more than DAY limit)
    // This makes the stored exchange time 2 days old
    let future_block_time = Time::now().add(Time::seconds(DAY * 2));
    start_cheat_block_timestamp_global(future_block_time.into());

    // Update funding tick to pass funding validation (dummy funding tick)
    state.facade.funding_tick(funding_ticks: array![].span());

    // Try to apply interests with non-zero amount - should fail because exchange time is more than
    // a day old
    let position_interest_amounts = array![(user.position_id, 100)].span();
    state.facade.apply_interests(:position_interest_amounts);
}
