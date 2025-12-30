use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::time::time::Timestamp;


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct VaultOpened {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub asset_id: AssetId,
}


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct InvestInVault {
    #[key]
    pub vault_position_id: PositionId,
    #[key]
    pub investing_position_id: PositionId,
    #[key]
    pub receiving_position_id: PositionId,
    #[key]
    pub vault_asset_id: AssetId,
    #[key]
    pub invested_asset_id: AssetId,
    pub shares_received: u64,
    pub user_investment: u64,
    pub correlation_id: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ForcedRedeemFromVaultRequest {
    #[key]
    pub order_source_position: PositionId,
    #[key]
    pub order_receive_position: PositionId,
    pub order_base_asset_id: AssetId,
    pub order_base_amount: i64,
    pub order_quote_asset_id: AssetId,
    pub order_quote_amount: i64,
    pub order_fee_asset_id: AssetId,
    pub order_fee_amount: u64,
    pub order_expiration: Timestamp,
    pub order_salt: felt252,
    #[key]
    pub vault_approval_source_position: PositionId,
    #[key]
    pub vault_approval_receive_position: PositionId,
    pub vault_approval_base_asset_id: AssetId,
    pub vault_approval_base_amount: i64,
    pub vault_approval_quote_asset_id: AssetId,
    pub vault_approval_quote_amount: i64,
    pub vault_approval_fee_asset_id: AssetId,
    pub vault_approval_fee_amount: u64,
    pub vault_approval_expiration: Timestamp,
    pub vault_approval_salt: felt252,
    #[key]
    pub hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ForcedRedeemFromVault {
    #[key]
    pub order_source_position: PositionId,
    #[key]
    pub order_receive_position: PositionId,
    pub order_base_asset_id: AssetId,
    pub order_base_amount: i64,
    pub order_quote_asset_id: AssetId,
    pub order_quote_amount: i64,
    pub order_fee_asset_id: AssetId,
    pub order_fee_amount: u64,
    pub order_expiration: Timestamp,
    pub order_salt: felt252,
    #[key]
    pub vault_approval_source_position: PositionId,
    #[key]
    pub vault_approval_receive_position: PositionId,
    pub vault_approval_base_asset_id: AssetId,
    pub vault_approval_base_amount: i64,
    pub vault_approval_quote_asset_id: AssetId,
    pub vault_approval_quote_amount: i64,
    pub vault_approval_fee_asset_id: AssetId,
    pub vault_approval_fee_amount: u64,
    pub vault_approval_expiration: Timestamp,
    pub vault_approval_salt: felt252,
}
