use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::Price;
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

    fn transfer_spot(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: PositionId,
        asset_id: AssetId,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );

    fn transfer_spot_request(
        ref self: TContractState,
        signature: Signature,
        recipient: PositionId,
        asset_id: AssetId,
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

    /// Transfer into vault is called by the operator after a user deposited an amount he want to
    /// deposit into the vault. flow:
    /// 1. the operator calls the deposit of the vault contract
    /// 2. the vault contracts calculates the amount of shares to mint (total assets (=TV of the
    /// vault position) / # of shares) and mints the vault shares to the perps contract and transer
    /// the underlying asset to the perps contract as well
    /// 3. call the perps transfer function (require signature and a change in the flow to allow
    /// transfer without a transfer_request) to transfer the assets from the user position to the
    /// vault position
    /// 4. call the deposit function of the perps contract to deposit the vault
    /// shares to the user
    fn deposit_into_vault(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        vault_position_id: PositionId,
        collateral_id: AssetId,
        quantized_amount: u64,
        expiration: Timestamp,
        salt: felt252,
        signature: Signature,
    );

    /// Withdraw from vault is called by the operator to let the user "cash out" his vault shares
    /// from the vault position into his position. flow:
    /// 1. the operator calls the withdraw_from_vault function
    /// 2. the perps contract transfers the assets (vault_share_execution_price * number_of_shares)
    /// from the vault position to the vault contract
    /// 3. calls the redeemEx function of the vault contract (a version where the price of a vault
    /// share is dicateded by the operator) which burns the vault shares and transfers the assets
    /// from the vault contract to the perps contract
    /// 4. calls the perps transfer function (require signature and a change in the flow to allow
    /// transfer without a transfer_request) to transfer the assets from the vault position to the
    /// user position
    fn withdraw_from_vault(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        vault_position_id: PositionId,
        collateral_id: AssetId,
        number_of_shares: u64,
        minimum_quantized_amount: u64,
        vault_share_execution_price: Price,
        expiration: Timestamp,
        salt: felt252,
        user_signature: Signature,
        vault_owner_signature: Signature,
    );

    fn liquidate_vault_shares(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        vault_position_id: PositionId,
        collateral_id: AssetId,
        number_of_shares: u64,
        vault_share_execution_price: Price,
        expiration: Timestamp,
        salt: felt252,
        vault_owner_signature: Signature,
    );

    fn register_vault(
        ref self: TContractState,
        operator_nonce: u64,
        vault_position_id: PositionId,
        vault_contract_address: ContractAddress,
        vault_asset_id: AssetId,
        signature: Signature,
    );
}
