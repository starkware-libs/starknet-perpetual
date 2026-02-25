use starkware_utils::time::time::Timestamp;

#[starknet::interface]
pub trait IExchangeTime<TContractState> {
    fn get_exchange_time(self: @TContractState) -> Timestamp;
    fn update_exchange_time(
        ref self: TContractState, operator_nonce: u64, new_timestamp: Timestamp,
    );
}
