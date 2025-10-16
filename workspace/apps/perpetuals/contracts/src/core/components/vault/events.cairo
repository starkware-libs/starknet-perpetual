use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::Price;
use starknet::ContractAddress;
use starkware_utils::time::time::Timestamp;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DepositIntoVault {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub vault_position_id: PositionId,
    pub collateral_id: AssetId,
    pub quantized_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
    pub quantized_shares_amount: u64,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct VaultRegistered {
    #[key]
    pub vault_position_id: PositionId,
    #[key]
    pub vault_contract_address: ContractAddress,
    #[key]
    pub vault_asset_id: AssetId,
    pub expiration: Timestamp,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawFromVault {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub vault_position_id: PositionId,
    pub collateral_id: AssetId,
    pub quantized_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
    pub quantized_shares_amount: u64,
    pub price: Price,
}
