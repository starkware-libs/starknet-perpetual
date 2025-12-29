use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::time::time::Timestamp;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub withdraw_request_hash: felt252,
    pub salt: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Withdraw {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub withdraw_request_hash: felt252,
    pub salt: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ForcedWithdrawRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub forced_withdraw_request_hash: felt252,
    pub salt: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ForcedWithdraw {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub forced_withdraw_request_hash: felt252,
    pub salt: felt252,
}
