use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Deleverage {
    #[key]
    pub deleveraged_position_id: PositionId,
    #[key]
    pub deleverager_position_id: PositionId,
    pub base_asset_id: AssetId,
    pub deleveraged_base_amount: i64,
    pub quote_asset_id: AssetId,
    pub deleveraged_quote_amount: i64,
}

#[starknet::interface]
pub trait IDeleverageManager<TContractState> {
    fn deleverage(
        ref self: TContractState,
        deleveraged_position_id: PositionId,
        deleverager_position_id: PositionId,
        base_asset_id: AssetId,
        deleveraged_base_amount: i64,
        deleveraged_quote_amount: i64,
    );
    fn deleverage_spot_asset(
        ref self: TContractState,
        deleveraged_position_id: PositionId,
        deleverager_position_id: PositionId,
        asset_id: AssetId,
        deleveraged_amount: i64,
        deleveraged_base_collateral_amount: i64,
    );
}

#[starknet::contract]
pub(crate) mod DeleverageManager {
    use core::panic_with_felt252;
    use core::panics::panic_with_byte_array;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalImpl as AssetsInternal;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit as DepositComponent;
    use perpetuals::core::components::deposit::Deposit::InternalImpl as DepositInternal;
    use perpetuals::core::components::fulfillment::fulfillment::Fulfillement as FulfillmentComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalImpl as OperatorNonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::components::snip::SNIP12MetadataImpl;
    use perpetuals::core::components::system_time::SystemTimeComponent;
    use perpetuals::core::types::asset::synthetic::{AssetType, SyntheticTrait};
    use perpetuals::core::types::position::PositionId;
    use starknet::storage::{StorageAsPointer, StoragePath, StoragePathEntry};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalImpl as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use crate::core::components::assets::errors::NO_SUCH_ASSET;
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_DELEVERAGES;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::components::vaults::vaults::Vaults::InternalTrait as VaultsInternal;
    use crate::core::components::vaults::vaults::{Vaults as VaultsComponent};
    use crate::core::components::positions::interface::IPositions;
    use crate::core::errors::{NO_DELEVERAGE_VAULT_SHARES, position_not_deleveragable};
    use crate::core::types::position::{Position, PositionDiff};
    use crate::core::value_risk_calculator::{
        calculate_position_tvtr_before, calculate_position_tvtr_change,
        deleveraged_position_validations,
    };
    use super::{AssetId, Deleverage, IDeleverageManager};

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Deleverage: Deleverage,
        #[flat]
        FulfillmentEvent: FulfillmentComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        SystemTimeEvent: SystemTimeComponent::Event,
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
        pub positions: PositionsComponent::Storage,
        #[substorage(v0)]
        pub system_time: SystemTimeComponent::Storage,
        #[substorage(v0)]
        pub fulfillment_tracking: FulfillmentComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        pub vaults: VaultsComponent::Storage,
    }

    component!(path: FulfillmentComponent, storage: fulfillment_tracking, event: FulfillmentEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: PositionsComponent, storage: positions, event: PositionsEvent);
    component!(path: SystemTimeComponent, storage: system_time, event: SystemTimeEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );
    component!(path: VaultsComponent, storage: vaults, event: VaultsEvent);

    #[abi(embed_v0)]
    impl TypedComponent of ITypedComponent<ContractState> {
        fn component_type(ref self: ContractState) -> felt252 {
            EXTERNAL_COMPONENT_DELEVERAGES
        }
    }


    #[abi(embed_v0)]
    impl DeleverageManagerImpl of IDeleverageManager<ContractState> {
        /// Executes a deleverage of a user position with a deleverager position.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in base and quote.
        ///   - Ensures the sign of amounts in each position is consistent.
        /// - Verifies that the base asset is active.
        /// - validates the deleveraged position is deleveragable.
        ///
        /// Execution:
        /// - Update the position, based on `delevereged_base_asset`.
        /// - Adjust collateral balances based on `delevereged_quote_asset`.
        /// - Perform fundamental validation for both positions after the execution.
        fn deleverage(
            ref self: ContractState,
            deleveraged_position_id: PositionId,
            deleverager_position_id: PositionId,
            base_asset_id: AssetId,
            deleveraged_base_amount: i64,
            deleveraged_quote_amount: i64,
        ) {
            let deleveraged_position = self
                .positions
                .get_position_snapshot(position_id: deleveraged_position_id);
            let deleverager_position = self
                .positions
                .get_position_snapshot(position_id: deleverager_position_id);

            /// Validation:
            self.assets.validate_asset_active(asset_id: base_asset_id);
            self
                .positions
                ._validate_imposed_reduction_trade(
                    position_id_a: deleveraged_position_id,
                    position_id_b: deleverager_position_id,
                    position_a: deleveraged_position,
                    position_b: deleverager_position,
                    :base_asset_id,
                    base_amount_a: deleveraged_base_amount,
                    quote_amount_a: deleveraged_quote_amount,
                );

            /// Execution:
            self
                ._execute_deleverage(
                    :deleveraged_position_id,
                    :deleverager_position_id,
                    :deleveraged_position,
                    :deleverager_position,
                    asset_id: base_asset_id,
                    deleveraged_asset_amount: deleveraged_base_amount,
                    deleveraged_collateral_amount: deleveraged_quote_amount,
                );
        }
        fn deleverage_spot_asset(
            ref self: ContractState,
            deleveraged_position_id: PositionId,
            deleverager_position_id: PositionId,
            asset_id: AssetId,
            deleveraged_amount: i64,
            deleveraged_base_collateral_amount: i64,
        ) {
            let deleveraged_position = self
                .positions
                .get_position_snapshot(position_id: deleveraged_position_id);
            let deleverager_position = self
                .positions
                .get_position_snapshot(position_id: deleverager_position_id);

            /// Validation:
            self.assets.validate_asset_active(:asset_id);
            self
                .positions
                ._validate_imposed_reduction_trade(
                    position_id_a: deleveraged_position_id,
                    position_id_b: deleverager_position_id,
                    position_a: deleveraged_position,
                    position_b: deleverager_position,
                    base_asset_id: asset_id,
                    base_amount_a: deleveraged_amount,
                    quote_amount_a: deleveraged_base_collateral_amount,
                );

            /// Execution:
            self
                ._execute_deleverage(
                    :deleveraged_position_id,
                    :deleverager_position_id,
                    :deleveraged_position,
                    :deleverager_position,
                    :asset_id,
                    deleveraged_asset_amount: deleveraged_amount,
                    deleveraged_collateral_amount: deleveraged_base_collateral_amount,
                );
        }
    }

    #[generate_trait]
    pub impl InternalFunctions of DeleverageManagerFunctionsTrait {
        fn _validate_deleveraged_position(
            self: @ContractState,
            position_id: PositionId,
            position: StoragePath<Position>,
            position_diff: PositionDiff,
        ) {
            let (provisional_delta, unchanged_assets) = self
                .positions
                .derive_funding_delta_and_unchanged_assets(:position, :position_diff);

            let synthetic_enriched_position_diff = self
                .positions
                .enrich_asset(:position, :position_diff);
            let position_diff_enriched = self
                .positions
                .enrich_collateral(
                    :position,
                    position_diff: synthetic_enriched_position_diff,
                    provisional_delta: Option::Some(provisional_delta),
                );

            let (asset_id, _) = position_diff.asset_diff.expect(NO_SUCH_ASSET);
            let entry = self.assets.asset_config.entry(asset_id).as_ptr();
            match SyntheticTrait::get_asset_type(entry).expect(NO_SUCH_ASSET) {
                AssetType::SYNTHETIC => {
                    deleveraged_position_validations(
                        :position_id, :unchanged_assets, :position_diff_enriched,
                    );
                },
                AssetType::SPOT_COLLATERAL => {
                    if (!self.positions.is_deleveragable(:position_id)) {
                        let tvtr_before = calculate_position_tvtr_before(
                            :unchanged_assets, :position_diff_enriched,
                        );
                        let tvtr = calculate_position_tvtr_change(
                            :tvtr_before,
                            synthetic_enriched_position_diff: position_diff_enriched.into(),
                        );
                        let err = position_not_deleveragable(:position_id, :tvtr);
                        panic_with_byte_array(err: @err);
                    }
                    self
                        .positions
                        .validate_healthy_or_healthier_position(
                            :position_id,
                            :position,
                            :position_diff,
                            tvtr_before: Default::default(),
                        );
                },
                AssetType::VAULT_SHARE_COLLATERAL => {
                    panic_with_felt252(NO_DELEVERAGE_VAULT_SHARES);
                },
            }
        }

        fn _execute_deleverage(
            ref self: ContractState,
            deleveraged_position_id: PositionId,
            deleverager_position_id: PositionId,
            deleveraged_position: StoragePath<Position>,
            deleverager_position: StoragePath<Position>,
            asset_id: AssetId,
            deleveraged_asset_amount: i64,
            deleveraged_collateral_amount: i64,
        ) {
            let deleveraged_position_diff = PositionDiff {
                collateral_diff: deleveraged_collateral_amount.into(),
                asset_diff: Option::Some((asset_id, deleveraged_asset_amount.into())),
            };
            // Passing the negative of actual amounts to deleverager as it is linked to
            // deleveraged.
            let deleverager_position_diff = PositionDiff {
                collateral_diff: -deleveraged_collateral_amount.into(),
                asset_diff: Option::Some((asset_id, -deleveraged_asset_amount.into())),
            };

            /// Validations - Fundamentals:
            // The deleveraged position should be deleveragable before
            // and healthy or healthier after and the deleverage must be fair.

            // TODO: Add logic for spot asset is fair deleverage. Technical issue- we currently
            // check is fair deleverage in value_risk_calculator which is not a contract and does
            // not have any of the components of the perps contract (we would need the assets
            // component at the very least to get the asset type but could be more depending on the
            // validation logic).

            self
                ._validate_deleveraged_position(
                    position_id: deleveraged_position_id,
                    position: deleveraged_position,
                    position_diff: deleveraged_position_diff,
                );
            let tvtr = self
                .positions
                .validate_healthy_or_healthier_position(
                    position_id: deleverager_position_id,
                    position: deleverager_position,
                    position_diff: deleverager_position_diff,
                    tvtr_before: Default::default(),
                );
            self
                .positions
                .validate_against_vault_limits(
                    position_id: deleverager_position_id,
                    vault_protection_config: self.vaults.get_vault_protection_config(deleverager_position_id),
                    :tvtr,
                );

            // Apply diffs
            self
                .positions
                .apply_diff(
                    position_id: deleveraged_position_id, position_diff: deleveraged_position_diff,
                );
            self
                .positions
                .apply_diff(
                    position_id: deleverager_position_id, position_diff: deleverager_position_diff,
                );

            self
                .emit(
                    Deleverage {
                        deleveraged_position_id,
                        deleverager_position_id,
                        base_asset_id: asset_id,
                        deleveraged_base_amount: deleveraged_asset_amount,
                        quote_asset_id: self.assets.get_collateral_id(),
                        deleveraged_quote_amount: deleveraged_collateral_amount,
                    },
                )
        }
    }
}
