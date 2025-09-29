use starknet::ContractAddress;

#[starknet::interface]
pub trait IProtocolVault<TState> {
    fn redeem_with_price(
        ref self: TState, shares: u256, value_of_shares: u256, receiver: ContractAddress,
    ) -> u256;
    fn get_owning_position_id(ref self: TState) -> u32;
}
