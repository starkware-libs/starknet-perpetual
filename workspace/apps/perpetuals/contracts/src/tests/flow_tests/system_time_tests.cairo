use perpetuals::core::components::system_time::interface::{
    ISystemTimeDispatcher, ISystemTimeDispatcherTrait,
};
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils::time::time::Time;

#[test]
#[should_panic(expected: 'STALE_TIME')]
fn test_system_time_cannot_drift_too_much() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let future_timestamp = Time::now().add(Time::seconds(360));
    let dispatcher = ISystemTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_system_time(operator_nonce: 1, new_timestamp: future_timestamp);
}

#[test]
#[should_panic(expected: 'NON_MONOTONIC_TIME')]
fn test_system_time_set_past_time() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let past_timestamp = Time::now().sub_delta(Time::seconds(1));
    let dispatcher = ISystemTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_system_time(operator_nonce: 1, new_timestamp: past_timestamp);
}

#[test]
#[should_panic(expected: 'NON_MONOTONIC_TIME')]
fn test_system_time_must_be_monotonically_increasing() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.advance_time(0);
}

#[test]
fn test_system_time_can_drift_a_bit() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.advance_time(1);

    let future_timestamp = Time::now().add(Time::seconds(100));
    let dispatcher = ISystemTimeDispatcher { contract_address: state.facade.perpetuals_contract };
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    dispatcher.update_system_time(2, future_timestamp);
}

