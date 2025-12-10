use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::risk_factor::RiskFactor;
use starknet::ContractAddress;
use starkware_utils::signature::stark::PublicKey;
use starkware_utils::storage::iterable_map::{
    IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
};

#[starknet::interface]
pub trait IAssetsExternal<TContractState> {
    fn add_oracle_to_asset(
        ref self: TContractState,
        asset_id: AssetId,
        oracle_public_key: PublicKey,
        oracle_name: felt252,
        asset_name: felt252,
    );
    fn add_synthetic_asset(
        ref self: TContractState,
        asset_id: AssetId,
        risk_factor_tiers: Span<u16>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
    );
    fn add_vault_collateral_asset(
        ref self: TContractState,
        asset_id: AssetId,
        erc20_contract_address: ContractAddress,
        quantum: u64,
        risk_factor_tiers: Span<u16>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
    );
    fn deactivate_synthetic(ref self: TContractState, synthetic_id: AssetId);
    fn remove_oracle_from_asset(
        ref self: TContractState, asset_id: AssetId, oracle_public_key: PublicKey,
    );
    fn update_synthetic_quorum(ref self: TContractState, synthetic_id: AssetId, quorum: u8);

    // View functions
    fn get_risk_factor_tiers(self: @TContractState, asset_id: AssetId) -> Span<RiskFactor>;
}

#[starknet::contract]
pub(crate) mod AssetsManager {
    use core::num::traits::{Pow, Zero};
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::types::asset::synthetic::{
        AssetConfig, AssetType, SyntheticTrait, TimelyData,
    };
    use perpetuals::core::types::asset::{AssetId, AssetStatus};
    use perpetuals::core::types::risk_factor::{RiskFactor, RiskFactorTrait};
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::constants::{TWO_POW_128, TWO_POW_40};
    use starkware_utils::signature::stark::PublicKey;
    use starkware_utils::storage::iterable_map::{
        IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::storage::utils::SubFromStorage;
    use starkware_utils::time::time::TimeDelta;
    use crate::core::components::assets::errors::{
        ASSET_NAME_TOO_LONG, ASSET_REGISTERED_AS_COLLATERAL, INACTIVE_ASSET, INVALID_SAME_QUORUM,
        INVALID_ZERO_ASSET_ID, INVALID_ZERO_ASSET_NAME, INVALID_ZERO_ORACLE_NAME,
        INVALID_ZERO_PUBLIC_KEY, INVALID_ZERO_QUORUM, INVALID_ZERO_RESOLUTION_FACTOR,
        INVALID_ZERO_RF_FIRST_BOUNDRY, INVALID_ZERO_RF_TIERS_LEN, INVALID_ZERO_RF_TIER_SIZE,
        NOT_SYNTHETIC, ORACLE_ALREADY_EXISTS, ORACLE_NAME_TOO_LONG, ORACLE_NOT_EXISTS,
        SYNTHETIC_ALREADY_EXISTS, SYNTHETIC_NOT_ACTIVE, SYNTHETIC_NOT_EXISTS,
        UNSORTED_RISK_FACTOR_TIERS,
    };
    use crate::core::components::assets::events;
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_ASSETS;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::types::price::SN_PERPS_SCALE;
    use super::IAssetsExternal;

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        OracleAdded: events::OracleAdded,
        SyntheticAdded: events::SyntheticAdded,
        SyntheticChanged: events::SyntheticChanged,
        SpotAssetAdded: events::SpotAssetAdded,
        SyntheticAssetDeactivated: events::SyntheticAssetDeactivated,
        OracleRemoved: events::OracleRemoved,
        AssetQuorumUpdated: events::AssetQuorumUpdated,
    }

    #[storage]
    #[allow(starknet::colliding_storage_paths)]
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
        src5: SRC5Component::Storage,
        num_of_active_synthetic_assets: usize,
        #[rename("synthetic_config")]
        asset_config: Map<AssetId, Option<AssetConfig>>,
        #[rename("synthetic_timely_data")]
        timely_data: IterableMap<AssetId, TimelyData>,
        risk_factor_tiers: Map<AssetId, Vec<RiskFactor>>,
        #[allow(starknet::colliding_storage_paths)]
        #[rename("risk_factor_tiers")]
        unchecked_access_risk_factor_tiers: Map<AssetId, Map<u64, RiskFactor>>,
        asset_oracle: Map<AssetId, Map<PublicKey, felt252>>,
        max_oracle_price_validity: TimeDelta,
        collateral_id: Option<AssetId>,
        max_price_interval: TimeDelta,
        max_funding_interval: TimeDelta,
        max_funding_rate: u32,
    }

    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl TypedComponent of ITypedComponent<ContractState> {
        fn component_type(ref self: ContractState) -> felt252 {
            EXTERNAL_COMPONENT_ASSETS
        }
    }

    #[abi(embed_v0)]
    impl AssetsManagerImpl of IAssetsExternal<ContractState> {
        /// Add oracle to a synthetic asset.
        fn add_oracle_to_asset(
            ref self: ContractState,
            asset_id: AssetId,
            oracle_public_key: PublicKey,
            oracle_name: felt252,
            asset_name: felt252,
        ) {
            let asset_config = self.asset_config.read(asset_id).expect(SYNTHETIC_NOT_EXISTS);
            assert(asset_config.status != AssetStatus::INACTIVE, INACTIVE_ASSET);

            // Validate the oracle does not exist.
            let asset_oracle_entry = self.asset_oracle.entry(asset_id).entry(oracle_public_key);
            let asset_oracle_data = asset_oracle_entry.read();
            assert(asset_oracle_data.is_zero(), ORACLE_ALREADY_EXISTS);

            assert(oracle_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
            assert(asset_name.is_non_zero(), INVALID_ZERO_ASSET_NAME);
            assert(oracle_name.is_non_zero(), INVALID_ZERO_ORACLE_NAME);

            // Validate the size of the oracle name.
            if let Option::Some(oracle_name) = oracle_name.try_into() {
                assert(oracle_name < TWO_POW_40, ORACLE_NAME_TOO_LONG);
            } else {
                panic_with_felt252(ORACLE_NAME_TOO_LONG);
            }

            // Validate the size of the asset name.
            assert(asset_name.into() < TWO_POW_128, ASSET_NAME_TOO_LONG);

            // Add the oracle to the asset.
            let shifted_asset_name = TWO_POW_40.into() * asset_name;
            asset_oracle_entry.write(shifted_asset_name + oracle_name);

            self.emit(events::OracleAdded { asset_id, asset_name, oracle_public_key, oracle_name });
        }

        fn add_synthetic_asset(
            ref self: ContractState,
            asset_id: AssetId,
            risk_factor_tiers: Span<u16>,
            risk_factor_first_tier_boundary: u128,
            risk_factor_tier_size: u128,
            quorum: u8,
            resolution_factor: u64,
        ) {
            self
                ._add_asset(
                    :asset_id,
                    :risk_factor_tiers,
                    :risk_factor_first_tier_boundary,
                    :risk_factor_tier_size,
                    :quorum,
                    :resolution_factor,
                    asset_type: AssetType::SYNTHETIC,
                    quantum: 0,
                    erc20_address: Option::None,
                );
        }

        fn add_vault_collateral_asset(
            ref self: ContractState,
            asset_id: AssetId,
            erc20_contract_address: ContractAddress,
            quantum: u64,
            risk_factor_tiers: Span<u16>,
            risk_factor_first_tier_boundary: u128,
            risk_factor_tier_size: u128,
            quorum: u8,
        ) {
            assert(quantum == 1, 'INVALID_SHARE_QUANTUM');
            let erc20Contract = IERC20MetadataDispatcher {
                contract_address: erc20_contract_address,
            };
            let underlying_decimals = erc20Contract.decimals();
            let underlying_resolution = 10_u128.pow(underlying_decimals.into());
            assert(underlying_resolution == SN_PERPS_SCALE, 'INVALID_UNDERLYING');
            let calculated_resolution: u64 = (10_u256.pow(underlying_decimals.into())
                / quantum.into())
                .try_into()
                .unwrap();
            assert(
                calculated_resolution == SN_PERPS_SCALE.try_into().unwrap(),
                'INVALID_SHARE_RESOLUTION',
            );
            self
                ._add_asset(
                    :asset_id,
                    :risk_factor_tiers,
                    :risk_factor_first_tier_boundary,
                    :risk_factor_tier_size,
                    :quorum,
                    resolution_factor: calculated_resolution,
                    asset_type: AssetType::VAULT_SHARE_COLLATERAL,
                    :quantum,
                    erc20_address: Option::Some(erc20_contract_address),
                );
        }

        fn deactivate_synthetic(ref self: ContractState, synthetic_id: AssetId) {
            let mut config = self.asset_config.read(synthetic_id).expect(SYNTHETIC_NOT_EXISTS);
            assert(config.status == AssetStatus::ACTIVE, SYNTHETIC_NOT_ACTIVE);
            assert(config.asset_type == AssetType::SYNTHETIC, NOT_SYNTHETIC);
            config.status = AssetStatus::INACTIVE;
            self.asset_config.entry(synthetic_id).write(Option::Some(config));
            self.num_of_active_synthetic_assets.sub_and_write(1);

            self.emit(events::SyntheticAssetDeactivated { asset_id: synthetic_id });
        }

        fn remove_oracle_from_asset(
            ref self: ContractState, asset_id: AssetId, oracle_public_key: PublicKey,
        ) {
            // Validate the oracle exists.
            let asset_oracle_entry = self.asset_oracle.entry(asset_id).entry(oracle_public_key);
            assert(asset_oracle_entry.read().is_non_zero(), ORACLE_NOT_EXISTS);
            asset_oracle_entry.write(Zero::zero());
            self.emit(events::OracleRemoved { asset_id, oracle_public_key });
        }

        fn update_synthetic_quorum(ref self: ContractState, synthetic_id: AssetId, quorum: u8) {
            let mut asset_config = self
                .asset_config
                .read(synthetic_id)
                .expect(SYNTHETIC_NOT_EXISTS);
            assert(asset_config.status != AssetStatus::INACTIVE, INACTIVE_ASSET);
            assert(quorum.is_non_zero(), INVALID_ZERO_QUORUM);
            let old_quorum = asset_config.quorum;
            assert(old_quorum != quorum, INVALID_SAME_QUORUM);
            asset_config.quorum = quorum;
            self.asset_config.write(synthetic_id, Option::Some(asset_config));
            self
                .emit(
                    events::AssetQuorumUpdated {
                        asset_id: synthetic_id, new_quorum: quorum, old_quorum,
                    },
                );
        }

        fn get_risk_factor_tiers(self: @ContractState, asset_id: AssetId) -> Span<RiskFactor> {
            let mut tiers = array![];
            let risk_factor_tiers = self.risk_factor_tiers.entry(asset_id);
            for i in 0..risk_factor_tiers.len() {
                tiers.append(risk_factor_tiers.at(i).read());
            }
            tiers.span()
        }
    }

    #[generate_trait]
    impl AssetsManagerInternalImpl of IAssetsManagerInternal {
        fn _add_asset(
            ref self: ContractState,
            asset_id: AssetId,
            risk_factor_tiers: Span<u16>,
            risk_factor_first_tier_boundary: u128,
            risk_factor_tier_size: u128,
            quorum: u8,
            resolution_factor: u64,
            asset_type: AssetType,
            quantum: u64,
            erc20_address: Option<ContractAddress>,
        ) {
            let asset_entry = self.asset_config.entry(asset_id);
            assert(asset_entry.read().is_none(), SYNTHETIC_ALREADY_EXISTS);
            if let Option::Some(collateral_id) = self.collateral_id.read() {
                assert(collateral_id != asset_id, ASSET_REGISTERED_AS_COLLATERAL);
            }

            assert(asset_id.is_non_zero(), INVALID_ZERO_ASSET_ID);
            assert(risk_factor_tiers.len().is_non_zero(), INVALID_ZERO_RF_TIERS_LEN);
            assert(risk_factor_first_tier_boundary.is_non_zero(), INVALID_ZERO_RF_FIRST_BOUNDRY);
            assert(risk_factor_tier_size.is_non_zero(), INVALID_ZERO_RF_TIER_SIZE);
            assert(quorum.is_non_zero(), INVALID_ZERO_QUORUM);
            assert(resolution_factor.is_non_zero(), INVALID_ZERO_RESOLUTION_FACTOR);

            let (asset_config, asset_added_event): (AssetConfig, Event) = match asset_type {
                AssetType::SYNTHETIC => {
                    (
                        SyntheticTrait::synthetic(
                            AssetStatus::PENDING,
                            risk_factor_first_tier_boundary,
                            risk_factor_tier_size,
                            quorum,
                            resolution_factor,
                        ),
                        Event::SyntheticAdded(
                            events::SyntheticAdded {
                                asset_id,
                                risk_factor_tiers,
                                risk_factor_first_tier_boundary,
                                risk_factor_tier_size,
                                resolution_factor,
                                quorum,
                            },
                        ),
                    )
                },
                AssetType::VAULT_SHARE_COLLATERAL => {
                    assert(risk_factor_tiers.len() == 1, 'INVALID_VAULT_RF_TIERS');

                    (
                        SyntheticTrait::vault_share(
                            AssetStatus::PENDING,
                            risk_factor_first_tier_boundary,
                            risk_factor_tier_size,
                            quorum,
                            resolution_factor,
                            quantum,
                            erc20_address.expect('MISSING_ERC20_ADDRESS_FOR_VAULT'),
                        ),
                        Event::SpotAssetAdded(
                            events::SpotAssetAdded {
                                asset_id,
                                risk_factor_tiers,
                                risk_factor_first_tier_boundary,
                                risk_factor_tier_size,
                                resolution_factor,
                                quorum,
                                contract_address: erc20_address.expect('MISSING_ERC20_ADDRESS'),
                            },
                        ),
                    )
                },
                AssetType::SPOT_COLLATERAL => {
                    assert(risk_factor_tiers.len() == 1, 'INVALID_SPOT_RF_TIERS');
                    (
                        SyntheticTrait::spot(
                            AssetStatus::PENDING,
                            risk_factor_first_tier_boundary,
                            risk_factor_tier_size,
                            quorum,
                            resolution_factor,
                            quantum,
                            erc20_address.expect('MISSING_ERC20_ADDRESS_FOR_SPOT'),
                        ),
                        Event::SpotAssetAdded(
                            events::SpotAssetAdded {
                                asset_id,
                                risk_factor_tiers,
                                risk_factor_first_tier_boundary,
                                risk_factor_tier_size,
                                resolution_factor,
                                quorum,
                                contract_address: erc20_address.expect('MISSING_ERC20_ADDRESS'),
                            },
                        ),
                    )
                },
            };

            asset_entry.write(Option::Some(asset_config));

            self.timely_data.write(asset_id, Default::default());

            let mut prev_risk_factor = 0_u16;
            for risk_factor in risk_factor_tiers {
                assert(prev_risk_factor < *risk_factor, UNSORTED_RISK_FACTOR_TIERS);
                self
                    .risk_factor_tiers
                    .entry(asset_id) // New function checks that `risk_factor` is lower than 1000.
                    .push(RiskFactorTrait::new(*risk_factor));
                prev_risk_factor = *risk_factor;
            }

            self.emit(asset_added_event);
        }
    }
}

