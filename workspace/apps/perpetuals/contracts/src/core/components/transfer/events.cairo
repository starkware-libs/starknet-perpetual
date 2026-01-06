use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::time::time::Timestamp;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct TransferRequest {
    #[key]
    pub recipient: PositionId,
    #[key]
    pub position_id: PositionId,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub transfer_request_hash: felt252,
    pub salt: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Transfer {
    #[key]
    pub recipient: PositionId,
    #[key]
    pub position_id: PositionId,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub transfer_request_hash: felt252,
    pub salt: felt252,
}

