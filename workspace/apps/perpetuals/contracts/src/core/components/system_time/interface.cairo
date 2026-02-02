use starkware_utils::time::time::Timestamp;

#[starknet::interface]
pub trait ISystemTime<TContractState> {
    fn get_system_time(self: @TContractState) -> Timestamp;
    fn update_system_time(ref self: TContractState, operator_nonce: u64, new_timestamp: Timestamp);
}
