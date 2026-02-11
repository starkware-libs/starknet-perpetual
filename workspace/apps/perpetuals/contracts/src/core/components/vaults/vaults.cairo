use crate::core::types::asset::AssetId;
use crate::core::types::position::PositionId;
use super::types::VaultProtectionParams;
use starkware_utils::constants::DAY;


const STORAGE_VERSION: u8 = 1;
const CHECK_FREQUENCY: u64 = DAY;

#[starknet::interface]
pub trait IVaults<TContractState> {
    fn is_vault_position(ref self: TContractState, vault_position: PositionId) -> bool;
    fn is_vault_asset(ref self: TContractState, asset_id: AssetId) -> bool;
    fn force_reset_protection_limit(ref self: TContractState, vault_position: PositionId, percentage_basis_points: u32);
    fn update_vault_protection_limit(ref self: TContractState, vault_position: PositionId, limit: u32);
}

#[starknet::component]
pub mod Vaults {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit::InternalImpl as DepositInternal;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::components::vaults::types::{VaultConfig, VaultConfigTrait};
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::synthetic::AssetType;
    use perpetuals::core::types::position::{PositionId, PositionTrait};
    use starknet::storage::{
        Map, StorageAsPointer, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::math::abs::Abs;
    use starkware_utils::math::utils::mul_wide_and_floor_div;
    use starkware_utils::signature::stark::Signature;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::{validate_expiration, Time};
    use vault::interface::{IProtocolVaultDispatcher, IProtocolVaultDispatcherTrait};
    use crate::core::components::positions::interface::IPositions;
    use perpetuals::core::components::system_time::SystemTimeComponent;
    use crate::core::components::snip::SNIP12MetadataImpl;
    use crate::core::components::vaults::events;
    use crate::core::types::vault::ConvertPositionToVault;
    use crate::core::utils::validate_signature;
    use super::{CHECK_FREQUENCY, IVaults, STORAGE_VERSION, VaultProtectionParams};

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        VaultOpened: events::VaultOpened,
        VaultProtectionReset: events::VaultProtectionReset,
        PerVaultProtectionLimitUpdated: events::PerVaultProtectionLimitUpdated,
    }

    #[storage]
    pub struct Storage {
        registered_vaults_by_asset: Map<AssetId, VaultConfig>,
        registered_vaults_by_position: Map<PositionId, VaultConfig>,
        vault_protection_limit_overrides: Map<PositionId, u32>,
    }

    #[embeddable_as(VaultsImpl)]
    impl VaultsComponent<
        TContractState,
        +HasComponent<TContractState>, 
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        impl SystemTime: SystemTimeComponent::HasComponent<TContractState>,
    > of IVaults<ComponentState<TContractState>> {
        fn is_vault_position(
            ref self: ComponentState<TContractState>, vault_position: PositionId,
        ) -> bool {
            let entry = (@self).registered_vaults_by_position.entry(vault_position).as_ptr();
            let is_vault_position = VaultConfigTrait::is_some(entry);
            return is_vault_position;
        }

        fn is_vault_asset(ref self: ComponentState<TContractState>, asset_id: AssetId) -> bool {
            return self.registered_vaults_by_asset.read(asset_id).version != 0;
        }

        fn force_reset_protection_limit(
            ref self: ComponentState<TContractState>,
            vault_position: PositionId,
            percentage_basis_points: u32,
        ) {
            get_dep_component!(@self, Roles).only_app_governor();

            let current_config = self.get_vault_config_for_position(:vault_position);
            let positions = get_dep_component!(@self, Positions);
            let position_tv_tr = positions.get_position_tv_tr(vault_position);
            let tv_at_check = position_tv_tr.total_value;
            let max_tv_loss = mul_wide_and_floor_div(
                tv_at_check.abs(), percentage_basis_points.into() * 10, 1000,
            )
                .unwrap();

            let updated_config = VaultConfig {
                version: current_config.version,
                asset_id: current_config.asset_id,
                position_id: current_config.position_id,
                last_tv_check: Time::now().into(),
                tv_at_check: tv_at_check,
                max_tv_loss: max_tv_loss,
            };

            self.registered_vaults_by_position.write(vault_position, updated_config);
            self.registered_vaults_by_asset.write(current_config.asset_id, updated_config);

            self
                .emit(
                    events::VaultProtectionReset {
                        vault_position_id: vault_position,
                        old_tv_at_check: current_config.tv_at_check,
                        old_max_tv_loss: current_config.max_tv_loss,
                        new_tv_at_check: updated_config.tv_at_check,
                        new_max_tv_loss: updated_config.max_tv_loss,
                    },
                );
        }

        fn update_vault_protection_limit(
            ref self: ComponentState<TContractState>, vault_position: PositionId, limit: u32,
        ) {
            get_dep_component!(@self, Roles).only_app_governor();
            assert(self.is_vault_position(vault_position), 'UNKNOWN_VAULT');
            let old_limit = self.vault_protection_limit_overrides.read(vault_position);
            self.vault_protection_limit_overrides.write(vault_position, limit);
            self
                .emit(
                    events::PerVaultProtectionLimitUpdated {
                        vault_position_id: vault_position,
                        old_limit: if old_limit == 0 {
                            5
                        } else {
                            old_limit
                        },
                        new_limit: if limit == 0 {
                            5
                        } else {
                            limit 
                        },
                    },
                );
        }   
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        impl SystemTime: SystemTimeComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_vault_config_for_position(
            ref self: ComponentState<TContractState>, vault_position: PositionId,
        ) -> VaultConfig {
            let vault_config = self.registered_vaults_by_position.read(vault_position);
            assert(vault_config.version != 0, 'UNKNOWN_VAULT');
            vault_config
        }

        fn get_vault_config_for_asset(
            ref self: ComponentState<TContractState>, vault_asset_id: AssetId,
        ) -> VaultConfig {
            let vault_config = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(vault_config.version != 0, 'UNKNOWN_VAULT');
            vault_config
        }

        fn get_vault_protection_config(
            ref self: ComponentState<TContractState>, vault_position: PositionId,
        ) -> Option<VaultProtectionParams> {
            if (!self.is_vault_position(vault_position)) {
                return Option::None;
            }

            let current_config = self.registered_vaults_by_position.read(vault_position);
            let current_time: u64 = Time::now().into();
            let last_check_time = current_config.last_tv_check;
            if (current_time - last_check_time >= CHECK_FREQUENCY) {    
                let positions = get_dep_component!(@self, Positions);
                let position_tv_tr = IPositions::get_position_tv_tr(positions, position_id: vault_position);
                let tv_at_check = position_tv_tr.total_value;

                let limit_from_storage = self.vault_protection_limit_overrides.read(vault_position);
                let limit = if limit_from_storage == 0 {
                    5
                } else {
                    limit_from_storage
                };

                let max_tv_loss = mul_wide_and_floor_div(tv_at_check.abs(), limit.into() * 10, 1000)
                    .unwrap();
                let updated_config = VaultConfig {
                    version: current_config.version,
                    asset_id: current_config.asset_id,
                    position_id: current_config.position_id,
                    last_tv_check: current_time,
                    tv_at_check: tv_at_check,
                    max_tv_loss: max_tv_loss,
                };
                self.registered_vaults_by_position.write(vault_position, updated_config);
                self.registered_vaults_by_asset.write(current_config.asset_id, updated_config);
                self.emit(
                    events::VaultProtectionReset {
                        vault_position_id: vault_position,
                        old_tv_at_check: current_config.tv_at_check,
                        old_max_tv_loss: current_config.max_tv_loss,
                        new_tv_at_check: updated_config.tv_at_check,
                        new_max_tv_loss: updated_config.max_tv_loss,
                    },
                );
                return Some(
                    VaultProtectionParams {
                        tv_at_check: updated_config.tv_at_check,
                        max_tv_loss: updated_config.max_tv_loss,
                    },
                );
            } else {
                return Some(
                    VaultProtectionParams {
                        tv_at_check: current_config.tv_at_check,
                        max_tv_loss: current_config.max_tv_loss,
                    },
                );
            }
        }

        fn activate_vault(
            ref self: ComponentState<TContractState>,
            order: ConvertPositionToVault,
            signature: Signature,
        ) {
            let vault_asset_id = order.vault_asset_id;
            let vault_position = order.position_to_convert;
            let expiration = order.expiration;
            validate_expiration(:expiration, err: 'ACTIVATE_ORDER_EXPIRED');

            let mut positions = get_dep_component_mut!(ref self, Positions);
            let assets = get_dep_component!(@self, Assets);
            let position_info = positions.get_position_snapshot(vault_position);

            /// Validations:

            validate_signature(
                public_key: position_info.get_owner_public_key(),
                message: order,
                signature: signature,
            );

            let existing_entry = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(existing_entry.version == 0, 'VAULT_ALREADY_ACTIVATED');

            let existing_position_entry = self.registered_vaults_by_position.read(vault_position);
            assert(existing_position_entry.version == 0, 'VAULT_ALREADY_ACTIVATED');

            let asset_config = assets.get_asset_config(vault_asset_id);

            assert(asset_config.asset_type == AssetType::VAULT_SHARE_COLLATERAL, 'NOT_VAULT_SHARE');

            let erc4626_dispatcher = IERC4626Dispatcher {
                contract_address: asset_config.token_contract.expect('NOT_ERC4626'),
            };

            let vault_dispatcher = IProtocolVaultDispatcher {
                contract_address: asset_config.token_contract.expect('NOT_ERC4626'),
            };
            assert(
                vault_dispatcher.get_owning_position_id() == vault_position.value,
                'VAULT_OWNERSHIP_MISMATCH',
            );

            assert(
                vault_dispatcher.get_perps_contract() == starknet::get_contract_address(),
                'VAULT_PERPS_CONTRACT_MISMATCH',
            );

            assert(
                erc4626_dispatcher
                    .asset() == assets
                    .get_base_collateral_token_contract()
                    .contract_address,
                'VAULT_ASSET_MISMATCH',
            );

            for (asset_id, balance_info) in position_info.asset_balances {
                if balance_info.balance.is_zero() {
                    continue;
                }
                let asset_config = assets.get_asset_config(asset_id);

                if (asset_config.asset_type == AssetType::VAULT_SHARE_COLLATERAL) {
                    panic_with_felt252('VAULT_CANNOT_HOLD_VAULT');
                }
            }

            self
                .registered_vaults_by_asset
                .write(
                    vault_asset_id,
                    VaultConfig {
                        version: STORAGE_VERSION,
                        asset_id: vault_asset_id,
                        position_id: vault_position.value,
                        last_tv_check: 0,
                        tv_at_check: 0,
                        max_tv_loss: 0,
                    },
                );

            self
                .registered_vaults_by_position
                .write(
                    vault_position,
                    VaultConfig {
                        version: STORAGE_VERSION,
                        asset_id: vault_asset_id,
                        position_id: vault_position.value,
                        last_tv_check: 0,
                        tv_at_check: 0,
                        max_tv_loss: 0,
                    },
                );

            self
                .emit(
                    Event::VaultOpened(
                        events::VaultOpened {
                            position_id: vault_position, asset_id: vault_asset_id,
                        },
                    ),
                )
        }
    }
}
