use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::vault::{ConvertPositionToVault, InvestInVault, RedeemFromVault};
use starknet::ContractAddress;
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Serde)]
pub struct Settlement {
    pub signature_a: Signature,
    pub signature_b: Signature,
    pub order_a: Order,
    pub order_b: Order,
    pub actual_amount_base_a: i64,
    pub actual_amount_quote_a: i64,
    pub actual_fee_a: u64,
    pub actual_fee_b: u64,
}

#[starknet::interface]
pub trait ICore<TContractState> {
    fn withdraw_request(
        ref self: TContractState,
        signature: Signature,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer_request(
        ref self: TContractState,
        signature: Signature,
        recipient: PositionId,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: PositionId,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn trade(
        ref self: TContractState,
        operator_nonce: u64,
        signature_a: Signature,
        signature_b: Signature,
        order_a: Order,
        order_b: Order,
        actual_amount_base_a: i64,
        actual_amount_quote_a: i64,
        actual_fee_a: u64,
        actual_fee_b: u64,
    );
    fn multi_trade(ref self: TContractState, operator_nonce: u64, trades: Span<Settlement>);
    fn liquidate(
        ref self: TContractState,
        operator_nonce: u64,
        liquidator_signature: Signature,
        liquidated_position_id: PositionId,
        liquidator_order: Order,
        actual_amount_base_liquidated: i64,
        actual_amount_quote_liquidated: i64,
        actual_liquidator_fee: u64,
        liquidated_fee_amount: u64,
    );
    fn deleverage(
        ref self: TContractState,
        operator_nonce: u64,
        deleveraged_position_id: PositionId,
        deleverager_position_id: PositionId,
        base_asset_id: AssetId,
        deleveraged_base_amount: i64,
        deleveraged_quote_amount: i64,
    );
    fn reduce_inactive_asset_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id_a: PositionId,
        position_id_b: PositionId,
        base_asset_id: AssetId,
        base_amount_a: i64,
    );

    fn invest_in_vault(
        ref self: TContractState, operator_nonce: u64, signature: Signature, order: InvestInVault,
    );

    fn redeem_from_vault(
        ref self: TContractState, operator_nonce: u64, signature: Signature, order: RedeemFromVault,
    );

    fn convert_position_to_vault(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        order: ConvertPositionToVault,
    );
}
