use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::LimitOrder;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::vault::ConvertPositionToVault;
use starkware_utils::signature::stark::Signature;


#[starknet::interface]
pub trait IVaultExternal<TContractState> {
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
}

#[starknet::contract]
pub(crate) mod VaultsManagerRefactored {
    use AssetsComponent::InternalTrait;
    use core::num::traits::{WideMul, Zero};
    use core::panics::panic_with_byte_array;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit as DepositComponent;
    use perpetuals::core::components::deposit::Deposit::InternalImpl as DepositInternal;
    use perpetuals::core::components::fulfillment::fulfillment::Fulfillement as FulfillmentComponent;
    use perpetuals::core::components::fulfillment::interface::IFulfillment;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::components::vaults::types::VaultConfig;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::synthetic::AssetConfig;
    use perpetuals::core::types::position::{PositionId, PositionTrait};
    use perpetuals::core::types::price::PriceMulTrait;
    use perpetuals::core::types::risk_factor::RiskFactorMulTrait;
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::math::abs::Abs;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::Time;
    use vault::interface::{IProtocolVaultDispatcher, IProtocolVaultDispatcherTrait};
    use crate::core::components::deposit::deposit_manager::IDepositExternalDispatcherTrait;
    use crate::core::components::external_components::external_component_manager::ExternalComponents as ExternalComponentsComponent;
    use crate::core::components::external_components::external_component_manager::ExternalComponents::InternalImpl as ExternalComponentsInternal;
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_VAULT;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::components::positions::interface::IPositions;
    use crate::core::components::snip::SNIP12MetadataImpl;
    use crate::core::components::vaults::events;
    use crate::core::components::vaults::vaults::Vaults::InternalTrait as VaultsInternal;
    use crate::core::components::vaults::vaults::{IVaults, Vaults as VaultsComponent};
    use crate::core::errors::order_expired_err;
    use crate::core::types::order::ValidateableOrderTrait;
    use crate::core::types::position::PositionDiff;
    use crate::core::utils::{validate_signature, validate_trade};
    use super::{ConvertPositionToVault, IVaultExternal, LimitOrder, Signature};


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        InvestInVault: events::InvestInVault,
        #[flat]
        FulfillmentEvent: FulfillmentComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        PositionsEvent: PositionsComponent::Event,
        #[flat]
        DepositEvent: DepositComponent::Event,
        #[flat]
        RequestApprovalsEvent: RequestApprovalsComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        VaultsEvent: VaultsComponent::Event,
        #[flat]
        ExternalComponentsEvent: ExternalComponentsComponent::Event,
    }

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        operator_nonce: OperatorNonceComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub deposits: DepositComponent::Storage,
        #[substorage(v0)]
        pub positions: PositionsComponent::Storage,
        #[substorage(v0)]
        pub fulfillment_tracking: FulfillmentComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        pub vaults: VaultsComponent::Storage,
        #[substorage(v0)]
        pub external_components: ExternalComponentsComponent::Storage,
    }

    component!(path: FulfillmentComponent, storage: fulfillment_tracking, event: FulfillmentEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: PositionsComponent, storage: positions, event: PositionsEvent);
    component!(path: DepositComponent, storage: deposits, event: DepositEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );

    component!(path: VaultsComponent, storage: vaults, event: VaultsEvent);

    component!(
        path: ExternalComponentsComponent,
        storage: external_components,
        event: ExternalComponentsEvent,
    );


    #[abi(embed_v0)]
    impl TypedComponent of ITypedComponent<ContractState> {
        fn component_type(ref self: ContractState) -> felt252 {
            EXTERNAL_COMPONENT_VAULT
        }
    }

    #[abi(embed_v0)]
    impl VaultsImpl of IVaultExternal<ContractState> {
        fn activate_vault(
            ref self: ContractState,
            operator_nonce: u64,
            order: ConvertPositionToVault,
            signature: Signature,
        ) {}

        fn invest_in_vault(
            ref self: ContractState,
            operator_nonce: u64,
            signature: Signature,
            order: LimitOrder,
            correlation_id: felt252,
        ) {}
        fn redeem_from_vault(
            ref self: ContractState,
            operator_nonce: u64,
            signature: Span<felt252>,
            order: LimitOrder,
            vault_approval: LimitOrder,
            vault_signature: Span<felt252>,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {
            let (
                vault_config,
                vault_asset,
                vault_position_id,
                redeeming_position_id,
                receiving_position_id,
            ) =
                self
                ._get_vault_redeem_context(:order);
            self._validate_redeem_amounts(:actual_shares_user, :actual_collateral_user);
            self
                ._validate_redeem_trade(
                    :order,
                    :vault_approval,
                    :vault_asset,
                    :actual_shares_user,
                    :actual_collateral_user,
                );
            let (vault_position, redeeming_position) = self
                ._get_redeem_positions(:vault_position_id, :redeeming_position_id);
            self
                ._validate_and_update_redeem_fulfillments(
                    :order,
                    :vault_approval,
                    :signature,
                    :vault_signature,
                    :vault_position,
                    :redeeming_position,
                    :vault_position_id,
                    :redeeming_position_id,
                    :actual_shares_user,
                );
            let (
                vault_dispatcher,
                vault_erc4626_dispatcher,
                vault_erc20_dispatcher,
                pnl_collateral_dispatcher,
                perps_contract_balance_before,
            ) =
                self
                ._setup_vault_dispatchers(:vault_asset);
            let unquantized_amount_to_burn = self
                ._approve_redeem_transfers(
                    :vault_asset,
                    :vault_erc20_dispatcher,
                    :pnl_collateral_dispatcher,
                    :actual_shares_user,
                    :actual_collateral_user,
                );
            self
                ._validate_redeem_value(
                    :vault_erc4626_dispatcher, :unquantized_amount_to_burn, :actual_collateral_user,
                );
            self
                ._execute_vault_redeem(
                    :vault_dispatcher, :unquantized_amount_to_burn, :actual_collateral_user,
                );
            let (vault_position_diff, redeeming_position_diff, receiving_position_diff) = self
                ._create_redeem_position_diffs(
                    :vault_config,
                    :actual_shares_user,
                    :actual_collateral_user,
                    :redeeming_position_id,
                    :receiving_position_id,
                );
            self
                ._validate_and_apply_vault_position_diff(
                    :vault_position_id, :vault_position, :vault_position_diff,
                );
            self._validate_redeem_asset_balances(:vault_position, :redeeming_position, :order);
            self
                ._validate_and_apply_redeeming_position_diff(
                    :redeeming_position_id,
                    :redeeming_position,
                    :redeeming_position_diff,
                    :actual_collateral_user,
                    :order,
                );
            self._apply_receiving_position_diff(:receiving_position_id, :receiving_position_diff);
            self
                ._verify_collateral_balance(
                    :pnl_collateral_dispatcher, :perps_contract_balance_before,
                );
        }

        fn liquidate_vault_shares(
            ref self: ContractState,
            operator_nonce: u64,
            liquidated_position_id: PositionId,
            vault_approval: LimitOrder,
            vault_signature: Span<felt252>,
            liquidated_asset_id: AssetId,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {}
    }

    #[generate_trait]
    pub impl InternalFunctions of VaultsFunctionsTrait {
        fn _execute_redeem(
            ref self: ContractState,
            order: LimitOrder,
            vault_approval: LimitOrder,
            vault_signature: Signature,
            actual_shares_user: i64,
            actual_collateral_user: i64,
            validate_user_order: bool,
            user_signature: Signature,
        ) {}

        fn _get_vault_redeem_context(
            ref self: ContractState, order: LimitOrder,
        ) -> (VaultConfig, AssetConfig, PositionId, PositionId, PositionId) {
            let vault_config = self.vaults.get_vault_config_for_asset(order.base_asset_id);
            let vault_asset = self.assets.get_asset_config(vault_config.asset_id);
            let vault_position_id: PositionId = vault_config.position_id.into();
            let redeeming_position_id = order.source_position;
            let receiving_position_id = order.receive_position;
            (
                vault_config,
                vault_asset,
                vault_position_id,
                redeeming_position_id,
                receiving_position_id,
            )
        }

        fn _validate_redeem_amounts(
            ref self: ContractState, actual_shares_user: i64, actual_collateral_user: i64,
        ) {
            if (actual_shares_user >= 0) {
                let err = format!("INVALID_ACTUAL_SHARES_AMOUNT: {}", actual_shares_user);
                panic_with_byte_array(err: @err);
            }
            if (actual_collateral_user < 0) {
                let err = format!("INVALID_ACTUAL_COLLATERAL_AMOUNT: {}", actual_collateral_user);
                panic_with_byte_array(err: @err);
            }
        }

        fn _validate_redeem_trade(
            ref self: ContractState,
            order: LimitOrder,
            vault_approval: LimitOrder,
            vault_asset: AssetConfig,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {
            validate_trade(
                order_a: order,
                order_b: vault_approval,
                actual_amount_base_a: actual_shares_user,
                actual_amount_quote_a: actual_collateral_user,
                actual_fee_a: 0_u64,
                actual_fee_b: 0_u64,
                asset: Some(vault_asset),
                collateral_id: self.assets.get_collateral_id(),
            );
        }

        fn _get_redeem_positions(
            ref self: ContractState,
            vault_position_id: PositionId,
            redeeming_position_id: PositionId,
        ) -> (
            starknet::storage::StoragePath<perpetuals::core::types::position::Position>,
            starknet::storage::StoragePath<perpetuals::core::types::position::Position>,
        ) {
            let vault_position = self.positions.get_position_snapshot(vault_position_id);
            let redeeming_position = self.positions.get_position_snapshot(redeeming_position_id);
            (vault_position, redeeming_position)
        }

        fn _validate_and_update_redeem_fulfillments(
            ref self: ContractState,
            order: LimitOrder,
            vault_approval: LimitOrder,
            signature: Span<felt252>,
            vault_signature: Span<felt252>,
            vault_position: starknet::storage::StoragePath<
                perpetuals::core::types::position::Position,
            >,
            redeeming_position: starknet::storage::StoragePath<
                perpetuals::core::types::position::Position,
            >,
            vault_position_id: PositionId,
            redeeming_position_id: PositionId,
            actual_shares_user: i64,
        ) {
            let order_hash = validate_signature(
                public_key: redeeming_position.get_owner_public_key(), message: order, :signature,
            );
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: redeeming_position_id,
                    hash: order_hash,
                    order_base_amount: order.base_amount.try_into().unwrap(),
                    actual_base_amount: actual_shares_user.try_into().unwrap(),
                );
            let vault_order_hash = validate_signature(
                public_key: vault_position.get_owner_public_key(),
                message: vault_approval,
                signature: vault_signature,
            );
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: vault_position_id,
                    hash: vault_order_hash,
                    order_base_amount: vault_approval.base_amount.try_into().unwrap(),
                    actual_base_amount: -actual_shares_user.try_into().unwrap(),
                );
        }

        fn _setup_vault_dispatchers(
            ref self: ContractState, vault_asset: AssetConfig,
        ) -> (
            IProtocolVaultDispatcher, IERC4626Dispatcher, IERC20Dispatcher, IERC20Dispatcher, u256,
        ) {
            let vault_dispatcher = IProtocolVaultDispatcher {
                contract_address: vault_asset.token_contract.expect('NOT_ERC20'),
            };
            let vault_erc4626_dispatcher = IERC4626Dispatcher {
                contract_address: vault_asset.token_contract.expect('NOT_ERC4626'),
            };
            let vault_erc20_dispatcher = IERC20Dispatcher {
                contract_address: vault_asset.token_contract.expect('NOT_ERC20'),
            };
            let pnl_collateral_dispatcher = self.assets.get_base_collateral_token_contract();
            let perps_contract_balance_before = pnl_collateral_dispatcher
                .balance_of(starknet::get_contract_address());
            (
                vault_dispatcher,
                vault_erc4626_dispatcher,
                vault_erc20_dispatcher,
                pnl_collateral_dispatcher,
                perps_contract_balance_before,
            )
        }

        fn _approve_redeem_transfers(
            ref self: ContractState,
            vault_asset: AssetConfig,
            vault_erc20_dispatcher: IERC20Dispatcher,
            pnl_collateral_dispatcher: IERC20Dispatcher,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) -> u256 {
            let amount_to_burn = actual_shares_user;
            let value_to_receive = actual_collateral_user;
            let unquantized_amount_to_burn_u128 = amount_to_burn
                .abs()
                .wide_mul(vault_asset.quantum);
            let unquantized_amount_to_burn: u256 = unquantized_amount_to_burn_u128.into();
            pnl_collateral_dispatcher
                .approve(
                    spender: vault_asset.token_contract.expect('NOT_ERC20'),
                    amount: value_to_receive.abs().into(),
                );
            vault_erc20_dispatcher
                .approve(
                    spender: vault_asset.token_contract.expect('NOT_ERC20'),
                    amount: unquantized_amount_to_burn.into(),
                );
            unquantized_amount_to_burn
        }

        fn _validate_redeem_value(
            ref self: ContractState,
            vault_erc4626_dispatcher: IERC4626Dispatcher,
            unquantized_amount_to_burn: u256,
            actual_collateral_user: i64,
        ) {
            let value_of_shares_from_er4626 = vault_erc4626_dispatcher
                .preview_redeem(unquantized_amount_to_burn.into());
            let max_value = ((value_of_shares_from_er4626 * 1100) / 1000);
            let value_to_receive = actual_collateral_user.abs().into();
            if (value_to_receive > max_value) {
                let err = format!(
                    "Redeem value too high. requested={}, actual={}, number_of_shares={}",
                    actual_collateral_user.abs(),
                    value_of_shares_from_er4626,
                    unquantized_amount_to_burn,
                );
                panic_with_byte_array(err: @err);
            }
        }

        fn _execute_vault_redeem(
            ref self: ContractState,
            vault_dispatcher: IProtocolVaultDispatcher,
            unquantized_amount_to_burn: u256,
            actual_collateral_user: i64,
        ) {
            let value_to_receive = actual_collateral_user.abs().into();
            let burn_result = vault_dispatcher
                .redeem_with_price(
                    shares: unquantized_amount_to_burn.into(), value_of_shares: value_to_receive,
                );
            if (burn_result != value_to_receive) {
                let err = format!(
                    "UNFAIR_REDEEM: expected {:?}, got {:?}", actual_collateral_user, burn_result,
                );
                panic_with_byte_array(err: @err);
            }
        }

        fn _create_redeem_position_diffs(
            ref self: ContractState,
            vault_config: VaultConfig,
            actual_shares_user: i64,
            actual_collateral_user: i64,
            redeeming_position_id: PositionId,
            receiving_position_id: PositionId,
        ) -> (PositionDiff, PositionDiff, Option<PositionDiff>) {
            let amount_to_burn = actual_shares_user;
            let value_to_receive = actual_collateral_user;
            let vault_position_diff = PositionDiff {
                collateral_diff: -value_to_receive.into(), asset_diff: None,
            };
            let (redeeming_position_diff, receiving_position_diff) =
                if (receiving_position_id == redeeming_position_id) {
                (
                    PositionDiff {
                        collateral_diff: value_to_receive.into(),
                        asset_diff: Some((vault_config.asset_id, amount_to_burn.into())),
                    },
                    None,
                )
            } else {
                (
                    PositionDiff {
                        asset_diff: Some((vault_config.asset_id, amount_to_burn.into())),
                        collateral_diff: 0_i64.into(),
                    },
                    Some(
                        PositionDiff { collateral_diff: value_to_receive.into(), asset_diff: None },
                    ),
                )
            };
            (vault_position_diff, redeeming_position_diff, receiving_position_diff)
        }

        fn _validate_and_apply_vault_position_diff(
            ref self: ContractState,
            vault_position_id: PositionId,
            vault_position: starknet::storage::StoragePath<
                perpetuals::core::types::position::Position,
            >,
            vault_position_diff: PositionDiff,
        ) {
            self
                .positions
                .validate_healthy_or_healthier_position(
                    position_id: vault_position_id,
                    position: vault_position,
                    position_diff: vault_position_diff,
                    tvtr_before: Default::default(),
                );
            self
                .positions
                .apply_diff(position_id: vault_position_id, position_diff: vault_position_diff);
        }

        fn _validate_redeem_asset_balances(
            ref self: ContractState,
            vault_position: starknet::storage::StoragePath<
                perpetuals::core::types::position::Position,
            >,
            redeeming_position: starknet::storage::StoragePath<
                perpetuals::core::types::position::Position,
            >,
            order: LimitOrder,
        ) {
            self
                .positions
                .validate_asset_balance_is_not_negative(
                    position: vault_position, asset_id: self.assets.get_collateral_id(),
                );
            self
                .positions
                .validate_asset_balance_is_not_negative(
                    position: redeeming_position, asset_id: order.base_asset_id,
                );
        }

        fn _validate_and_apply_redeeming_position_diff(
            ref self: ContractState,
            redeeming_position_id: PositionId,
            redeeming_position: starknet::storage::StoragePath<
                perpetuals::core::types::position::Position,
            >,
            redeeming_position_diff: PositionDiff,
            actual_collateral_user: i64,
            order: LimitOrder,
        ) {
            if (self.positions.is_liquidatable(redeeming_position_id)) {
                let (asset_id, qty) = redeeming_position_diff.asset_diff.unwrap();
                let price = self.assets.get_asset_price(asset_id);
                let risk_factor = self.assets.get_asset_risk_factor(asset_id, 1_i64.into(), price);
                let value_of_shares_sold: u128 = price
                    .mul(qty)
                    .abs()
                    .try_into()
                    .expect('REDEEM_VAULT_SHARES_OVERFLOW');
                let risk_of_shares_sold: u128 = risk_factor.mul(value_of_shares_sold);
                let collateral_received: u128 = actual_collateral_user.abs().try_into().unwrap();
                if (collateral_received < value_of_shares_sold - risk_of_shares_sold) {
                    let err = format!(
                        "Illegal transition value_of_shares_sold={}, risk_of_shares_sold={}, collateral_received={}",
                        value_of_shares_sold,
                        risk_of_shares_sold,
                        collateral_received,
                    );
                    panic_with_byte_array(err: @err);
                }
            } else {
                self
                    .positions
                    .validate_healthy_or_healthier_position(
                        position_id: redeeming_position_id,
                        position: redeeming_position,
                        position_diff: redeeming_position_diff,
                        tvtr_before: Default::default(),
                    );
            }
            self
                .positions
                .apply_diff(
                    position_id: redeeming_position_id, position_diff: redeeming_position_diff,
                );
        }

        fn _apply_receiving_position_diff(
            ref self: ContractState,
            receiving_position_id: PositionId,
            receiving_position_diff: Option<PositionDiff>,
        ) {
            if let Option::Some(position_diff) = receiving_position_diff {
                self
                    .positions
                    .apply_diff(position_id: receiving_position_id, position_diff: position_diff);
            }
        }

        fn _verify_collateral_balance(
            ref self: ContractState,
            pnl_collateral_dispatcher: IERC20Dispatcher,
            perps_contract_balance_before: u256,
        ) {
            let new_perps_contract_balance = pnl_collateral_dispatcher
                .balance_of(starknet::get_contract_address());
            assert(
                new_perps_contract_balance == perps_contract_balance_before,
                'COLLATERAL_NOT_RETURNED',
            );
        }
    }
}
