use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::{LimitOrder, Order};
use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::Timestamp;
use super::types::vault::ConvertPositionToVault;

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
        collateral_id: AssetId,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw(
        ref self: TContractState,
        operator_nonce: u64,
        collateral_id: AssetId,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer_request(
        ref self: TContractState,
        signature: Signature,
        asset_id: AssetId,
        recipient: PositionId,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
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
    fn clean_fulfillments(
        ref self: TContractState, orders: Span<Order>, public_keys: Span<felt252>,
    );
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
    fn deleverage_spot_asset(
        ref self: TContractState,
        operator_nonce: u64,
        deleveraged_position_id: PositionId,
        deleverager_position_id: PositionId,
        asset_id: AssetId,
        deleveraged_amount: i64,
        deleveraged_base_collateral_amount: i64,
    );
    fn reduce_asset_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id_a: PositionId,
        position_id_b: PositionId,
        base_asset_id: AssetId,
        base_amount_a: i64,
    );

    fn activate_vault(
        ref self: TContractState,
        operator_nonce: u64,
        order: ConvertPositionToVault,
        signature: Signature,
    );
    fn invest_in_vault(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        order: LimitOrder,
        correlation_id: felt252,
    );
    fn redeem_from_vault(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        order: LimitOrder,
        vault_approval: LimitOrder,
        vault_signature: Signature,
        actual_shares_user: i64,
        actual_collateral_user: i64,
    );

    fn liquidate_vault_shares(
        ref self: TContractState,
        operator_nonce: u64,
        liquidated_position_id: PositionId,
        vault_approval: LimitOrder,
        vault_signature: Signature,
        liquidated_asset_id: AssetId,
        actual_shares_user: i64,
        actual_collateral_user: i64,
    );
    fn forced_withdraw_request(
        ref self: TContractState,
        signature: Signature,
        collateral_id: AssetId,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn forced_withdraw(
        ref self: TContractState,
        collateral_id: AssetId,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn forced_trade_request(
        ref self: TContractState,
        signature_a: Signature,
        signature_b: Signature,
        order_a: Order,
        order_b: Order,
    );
    fn forced_trade(ref self: TContractState, operator_nonce: u64, order_a: Order, order_b: Order);
    fn forced_redeem_from_vault_request(
        ref self: TContractState,
        signature: Signature,
        vault_signature: Signature,
        order: LimitOrder,
        vault_approval: LimitOrder,
    );
    fn force_redeem_from_vault(
        ref self: TContractState,
        operator_nonce: u64,
        order: LimitOrder,
        vault_approval: LimitOrder,
    );
    fn apply_interests(
        ref self: TContractState,
        operator_nonce: u64,
        position_ids: Span<PositionId>,
        interest_amounts: Span<i64>,
    );
    fn liquidate_spot_asset(
        ref self: TContractState,
        operator_nonce: u64,
        liquidated_position_id: PositionId,
        liquidator_order: LimitOrder,
        liquidator_signature: Signature,
        actual_amount_spot_collateral: i64,
        actual_amount_base_collateral: i64,
        actual_liquidator_fee: u64,
        liquidated_fee_amount: u64,
    );

    fn enable_escape_hatch(ref self: TContractState);
    fn get_max_interest_rate_per_sec(self: @TContractState) -> u32;
    fn set_max_interest_rate_per_sec(ref self: TContractState, max_interest_rate_per_sec: u32);
}
