use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::Price;
use starknet::ContractAddress;
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::Timestamp;


#[starknet::interface]
pub trait IVault<TContractState> {
    fn deposit_into_vault(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        position_id: PositionId,
        vault_position_id: PositionId,
        quantized_amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn register_vault(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        vault_position_id: PositionId,
        vault_contract_address: ContractAddress,
        vault_asset_id: AssetId,
        expiration: Timestamp,
    );
    fn withdraw_from_vault(
        ref self: TContractState,
        operator_nonce: u64,
        user_signature: Signature,
        position_id: PositionId,
        vault_owner_signature: Signature,
        vault_position_id: PositionId,
        number_of_shares: u64,
        minimum_received_total_amount: u64,
        vault_share_execution_price: Price,
        expiration: Timestamp,
        salt: felt252,
    );
}
