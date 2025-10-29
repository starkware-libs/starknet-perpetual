#[starknet::component]
pub mod VaultExcecutorComponent {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as OperatorNonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::vault::interface::{
        IVault, IVaultDispatcherTrait, IVaultLibraryDispatcher,
    };
    use perpetuals::core::components::vault::{errors, events};
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::position::PositionId;
    use perpetuals::core::types::price::Price;
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::signature::stark::{HashType, Signature};
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::Timestamp;

    #[storage]
    pub struct Storage {
        vault_logic_library: ClassHash,
        // vault position to contract address of tokenized vault contract.
        pub vault_positions_to_addresses: Map<PositionId, ContractAddress>,
        // vault position to vault position asset_id.
        // i.e. positions holding share of vault position, will have this asset_id in the position.
        pub vault_positions_to_assets: Map<PositionId, AssetId>,
        // Maps vault contract address to its vault position.
        // Ensures each vault contract is assigned to only one position.
        pub addresses_to_vault_positions: Map<ContractAddress, PositionId>,
        pub fulfilled_vault_requests: Map<HashType, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DepositIntoVault: events::DepositIntoVault,
        RedeemedFromVault: events::RedeemedFromVault,
        VaultRegistered: events::VaultRegistered,
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, vault_logic_library: ClassHash) {
            assert(self.vault_logic_library.read().is_zero(), errors::ALREADY_INITIALIZED);
            assert(vault_logic_library.is_non_zero(), 'ZERO');
            self.vault_logic_library.write(vault_logic_library);
        }
    }

    #[embeddable_as(VaultExcecutorComponentImpl)]
    impl VaultExcecutorComponent<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +RequestApprovalsComponent::HasComponent<TContractState>,
        +PositionsComponent::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        +RolesComponent::HasComponent<TContractState>,
    > of IVault<ComponentState<TContractState>> {
        fn deposit_into_vault(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            signature: Signature,
            position_id: PositionId,
            vault_position_id: PositionId,
            collateral_quantized_amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);

            IVaultLibraryDispatcher { class_hash: self.vault_logic_library.read() }
                .deposit_into_vault(
                    :operator_nonce,
                    :signature,
                    :position_id,
                    :vault_position_id,
                    :collateral_quantized_amount,
                    :expiration,
                    :salt,
                );
        }

        fn register_vault(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            signature: Signature,
            vault_position_id: PositionId,
            vault_contract_address: ContractAddress,
            vault_asset_id: AssetId,
            expiration: Timestamp,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);
            IVaultLibraryDispatcher { class_hash: self.vault_logic_library.read() }
                .register_vault(
                    :operator_nonce,
                    :signature,
                    :vault_position_id,
                    :vault_contract_address,
                    :vault_asset_id,
                    :expiration,
                );
        }

        fn redeem_from_vault(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            user_signature: Signature,
            position_id: PositionId,
            vault_owner_signature: Signature,
            vault_position_id: PositionId,
            number_of_shares: u64,
            minimum_received_total_amount: u64,
            vault_share_execution_price: Price,
            expiration: Timestamp,
            salt: felt252,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);

            IVaultLibraryDispatcher { class_hash: self.vault_logic_library.read() }
                .redeem_from_vault(
                    :operator_nonce,
                    :user_signature,
                    :position_id,
                    :vault_owner_signature,
                    :vault_position_id,
                    :number_of_shares,
                    :minimum_received_total_amount,
                    :vault_share_execution_price,
                    :expiration,
                    :salt,
                );
        }


        fn liquidate_vault_shares(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            vault_owner_signature: Signature,
            position_id: PositionId,
            vault_position_id: PositionId,
            number_of_shares: u64,
            vault_share_execution_price: Price,
            expiration: Timestamp,
            salt: felt252,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);

            IVaultLibraryDispatcher { class_hash: self.vault_logic_library.read() }
                .liquidate_vault_shares(
                    :operator_nonce,
                    :vault_owner_signature,
                    :position_id,
                    :vault_position_id,
                    :number_of_shares,
                    :vault_share_execution_price,
                    :expiration,
                    :salt,
                );
        }
    }
}
