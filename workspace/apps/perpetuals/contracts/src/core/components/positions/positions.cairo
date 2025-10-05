#[starknet::component]
pub(crate) mod Positions {
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternalTrait;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::positions::errors::{
        ALREADY_INITIALIZED, CALLER_IS_NOT_OWNER_ACCOUNT, INVALID_ZERO_OWNER_ACCOUNT,
        INVALID_ZERO_PUBLIC_KEY, NO_OWNER_ACCOUNT, POSITION_ALREADY_EXISTS, POSITION_DOESNT_EXIST,
        POSITION_HAS_OWNER_ACCOUNT, SAME_PUBLIC_KEY, SET_POSITION_OWNER_EXPIRED,
        SET_PUBLIC_KEY_EXPIRED,
    };
    use perpetuals::core::components::positions::events;
    use perpetuals::core::components::positions::interface::IPositions;
    use perpetuals::core::core::Core::SNIP12MetadataImpl;
    use perpetuals::core::types::asset::{Asset, AssetId};
    use perpetuals::core::types::balance::Balance;
    use perpetuals::core::types::funding::calculate_funding;
    use perpetuals::core::types::position::{
        POSITION_VERSION, Position, PositionData, PositionDiff, PositionId, PositionMutableTrait,
        PositionTrait, SyntheticBalance,
    };
    use perpetuals::core::types::set_owner_account::SetOwnerAccountArgs;
    use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
    use perpetuals::core::value_risk_calculator::{
        PositionState, PositionTVTR, calculate_position_tvtr, evaluate_position,
    };
    use starknet::storage::{
        Map, Mutable, StoragePath, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::signature::stark::{PublicKey, Signature};
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::storage::utils::AddToStorage;
    use starkware_utils::time::time::{Timestamp, validate_expiration};

    pub const FEE_POSITION: PositionId = PositionId { value: 0 };
    pub const INSURANCE_FUND_POSITION: PositionId = PositionId { value: 1 };


    #[storage]
    pub struct Storage {
        positions: Map<PositionId, Position>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        NewPosition: events::NewPosition,
        SetOwnerAccount: events::SetOwnerAccount,
        SetOwnerAccountRequest: events::SetOwnerAccountRequest,
        SetPublicKey: events::SetPublicKey,
        SetPublicKeyRequest: events::SetPublicKeyRequest,
    }

    #[embeddable_as(PositionsImpl)]
    impl Positions<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
    > of IPositions<ComponentState<TContractState>> {
        fn get_position_assets(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> PositionData {
            let position = self.get_position_snapshot(:position_id);
            let (provisional_delta, synthetics) = self
                .derive_funding_delta_and_unchanged_synthetics(
                    :position, position_diff: Default::default(),
                );
            let collateral_balance = self
                .get_collateral_provisional_balance(
                    :position, provisional_delta: Option::Some(provisional_delta),
                );

            PositionData { synthetics, collateral_balance }
        }

        /// This function is primarily used as a view function—knowing the total value and/or
        /// total risk without context is unnecessary.
        fn get_position_tv_tr(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> PositionTVTR {
            let position = self.get_position_snapshot(:position_id);
            let (provisional_delta, unchanged_synthetics) = self
                .derive_funding_delta_and_unchanged_synthetics(
                    :position, position_diff: Default::default(),
                );
            let collateral_balance = self
                .get_collateral_provisional_balance(
                    :position, provisional_delta: Option::Some(provisional_delta),
                );

            calculate_position_tvtr(:unchanged_synthetics, :collateral_balance)
        }

        /// This function is mostly used as view function - it's better to use the
        /// `calculate_position_tvtr_change` function as it gives all the information needed at the
        /// same cost.
        fn is_healthy(self: @ComponentState<TContractState>, position_id: PositionId) -> bool {
            let position = self.get_position_snapshot(:position_id);
            let position_state = self._get_position_state(:position);
            position_state == PositionState::Healthy
        }

        /// This function is mostly used as view function - it's better to use the
        /// `calculate_position_tvtr_change` function as it gives all the information needed at the
        /// same cost.
        fn is_liquidatable(self: @ComponentState<TContractState>, position_id: PositionId) -> bool {
            let position = self.get_position_snapshot(:position_id);
            let position_state = self._get_position_state(:position);
            position_state == PositionState::Liquidatable
                || position_state == PositionState::Deleveragable
        }

        /// This function is mostly used as view function - it's better to use the
        /// `calculate_position_tvtr_change` function as it gives all the information needed at the
        /// same cost.
        fn is_deleveragable(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> bool {
            let position = self.get_position_snapshot(:position_id);
            let position_state = self._get_position_state(:position);
            position_state == PositionState::Deleveragable
        }

        /// Adds a new position to the system.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The operator nonce must be valid.
        /// - The position does not exist.
        /// - The owner public key is non-zero.
        ///
        /// Execution:
        /// - Create a new position with the given `owner_public_key` and `owner_account`.
        /// - Emit a `NewPosition` event.
        ///
        /// The position can be initialized with `owner_account` that is zero (no owner account).
        /// This is to support the case where it doesn't have a L2 account.
        fn new_position(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            position_id: PositionId,
            owner_public_key: PublicKey,
            owner_account: ContractAddress,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut operator_nonce_component = get_dep_component_mut!(ref self, OperatorNonce);
            operator_nonce_component.use_checked_nonce(:operator_nonce);
            let mut position = self.positions.entry(position_id);
            assert(position.version.read().is_zero(), POSITION_ALREADY_EXISTS);
            assert(owner_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
            position.version.write(POSITION_VERSION);
            position.owner_public_key.write(owner_public_key);
            if owner_account.is_non_zero() {
                position.owner_account.write(Option::Some(owner_account));
            }
            self
                .emit(
                    events::NewPosition {
                        position_id: position_id,
                        owner_public_key: owner_public_key,
                        owner_account: owner_account,
                    },
                );
        }

        /// Registers a request to set the position's owner_account.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the caller is the new_owner_account.
        /// - Validates the request does not exist.
        ///
        /// Execution:
        /// - Registers the set owner account request.
        /// - Emits a `SetOwnerAccountRequest` event.
        fn set_owner_account_request(
            ref self: ComponentState<TContractState>,
            signature: Signature,
            position_id: PositionId,
            new_owner_account: ContractAddress,
            expiration: Timestamp,
        ) {
            let position = self.get_position_snapshot(:position_id);
            assert(position.get_owner_account().is_none(), POSITION_HAS_OWNER_ACCOUNT);
            assert(new_owner_account.is_non_zero(), INVALID_ZERO_OWNER_ACCOUNT);
            let public_key = position.get_owner_public_key();
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .register_approval(
                    owner_account: Option::Some(new_owner_account),
                    :public_key,
                    :signature,
                    args: SetOwnerAccountArgs {
                        position_id, public_key, new_owner_account, expiration,
                    },
                );
            self
                .emit(
                    events::SetOwnerAccountRequest {
                        position_id,
                        public_key,
                        new_owner_account,
                        expiration,
                        set_owner_account_hash: hash,
                    },
                );
        }


        /// Sets the owner of a position to a new account owner.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The caller must be the operator.
        /// - The operator nonce must be valid.
        /// - The expiration time has not passed.
        /// - The position has no account owner.
        /// - The signature is valid.
        fn set_owner_account(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            position_id: PositionId,
            new_owner_account: ContractAddress,
            expiration: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut operator_nonce_component = get_dep_component_mut!(ref self, OperatorNonce);
            operator_nonce_component.use_checked_nonce(:operator_nonce);
            validate_expiration(:expiration, err: SET_POSITION_OWNER_EXPIRED);
            let position = self.get_position_mut(:position_id);
            let public_key = position.get_owner_public_key();
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .consume_approved_request(
                    args: SetOwnerAccountArgs {
                        position_id, public_key, new_owner_account, expiration,
                    },
                    :public_key,
                );
            position.owner_account.write(Option::Some(new_owner_account));
            self
                .emit(
                    events::SetOwnerAccount {
                        position_id, public_key, new_owner_account, set_owner_account_hash: hash,
                    },
                );
        }

        /// Registers a request to set the position's public key.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the caller is the owner of the position.
        /// - Validates the request does not exist.
        ///
        /// Execution:
        /// - Registers the set public key request.
        /// - Emits a `SetPublicKeyRequest` event.
        fn set_public_key_request(
            ref self: ComponentState<TContractState>,
            signature: Signature,
            position_id: PositionId,
            new_public_key: PublicKey,
            expiration: Timestamp,
        ) {
            let position = self.get_position_snapshot(:position_id);
            let old_public_key = position.get_owner_public_key();
            assert(new_public_key != old_public_key, SAME_PUBLIC_KEY);
            let owner_account = position.get_owner_account();
            if let Option::Some(owner_account) = owner_account {
                assert(owner_account == get_caller_address(), CALLER_IS_NOT_OWNER_ACCOUNT);
            } else {
                panic_with_felt252(NO_OWNER_ACCOUNT);
            }
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .register_approval(
                    :owner_account,
                    public_key: new_public_key,
                    :signature,
                    args: SetPublicKeyArgs {
                        position_id, old_public_key, new_public_key, expiration,
                    },
                );
            self
                .emit(
                    events::SetPublicKeyRequest {
                        position_id,
                        new_public_key,
                        old_public_key,
                        expiration,
                        set_public_key_request_hash: hash,
                    },
                );
        }

        /// Sets the position's public key.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The operator nonce must be valid.
        /// - The expiration time has not passed.
        /// - The position has an owner account.
        /// - The request has been registered.
        fn set_public_key(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            position_id: PositionId,
            new_public_key: PublicKey,
            expiration: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut operator_nonce_component = get_dep_component_mut!(ref self, OperatorNonce);
            operator_nonce_component.use_checked_nonce(:operator_nonce);
            validate_expiration(:expiration, err: SET_PUBLIC_KEY_EXPIRED);
            let position = self.get_position_mut(:position_id);
            let old_public_key = position.get_owner_public_key();
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .consume_approved_request(
                    args: SetPublicKeyArgs {
                        position_id, old_public_key, new_public_key, expiration,
                    },
                    public_key: new_public_key,
                );
            position.owner_public_key.write(new_public_key);
            self
                .emit(
                    events::SetPublicKey {
                        position_id,
                        new_public_key,
                        old_public_key,
                        set_public_key_request_hash: hash,
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
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>,
            fee_position_owner_public_key: PublicKey,
            insurance_fund_position_owner_public_key: PublicKey,
        ) {
            // Checks that the component has not been initialized yet.
            let fee_position = self.positions.entry(FEE_POSITION);
            assert(fee_position.version.read().is_zero(), ALREADY_INITIALIZED);

            // Checks that the input public keys are non-zero.
            assert(fee_position_owner_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
            assert(insurance_fund_position_owner_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);

            // Create fee positions.
            fee_position.version.write(POSITION_VERSION);
            fee_position.owner_public_key.write(fee_position_owner_public_key);

            let insurance_fund_position = self.positions.entry(INSURANCE_FUND_POSITION);
            insurance_fund_position.version.write(POSITION_VERSION);
            insurance_fund_position
                .owner_public_key
                .write(insurance_fund_position_owner_public_key);
        }

        fn apply_diff(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            position_diff: PositionDiff,
        ) {
            let position_mut = self.get_position_mut(:position_id);
            position_mut.collateral_balance.add_and_write(position_diff.collateral_diff);

            if let Option::Some((synthetic_id, synthetic_diff)) = position_diff.synthetic_diff {
                self
                    ._update_synthetic_balance_and_funding(
                        position: position_mut, :synthetic_id, :synthetic_diff,
                    );
            };
        }

        fn get_position_snapshot(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Position> {
            let position = self.positions.entry(position_id);
            assert(position.version.read().is_non_zero(), POSITION_DOESNT_EXIST);
            position
        }

        /// Returns the position at the given `position_id`.
        /// The function asserts that the position exists and has a non-zero version.
        fn get_position_mut(
            ref self: ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            let mut position = self.positions.entry(position_id);
            assert(position.version.read().is_non_zero(), POSITION_DOESNT_EXIST);
            position
        }

        fn get_asset_balance(
            self: @ComponentState<TContractState>,
            position: StoragePath<Position>,
            asset_id: AssetId,
        ) -> Balance {
            if let Option::Some(asset) = position.assets_balance.read(asset_id) {
                asset.balance
            } else {
                0_i64.into()
            }
        }

        fn get_collateral_provisional_balance(
            self: @ComponentState<TContractState>,
            position: StoragePath<Position>,
            provisional_delta: Option<Balance>,
        ) -> Balance {
            let assets = get_dep_component!(self, Assets);
            let mut collateral_provisional_balance = position.collateral_balance.read();
            if let Option::Some(provisional_delta) = provisional_delta {
                return collateral_provisional_balance + provisional_delta;
            }

            for (synthetic_id, synthetic) in position.assets_balance {
                if synthetic.balance.is_zero() {
                    continue;
                }
                let global_funding_index = assets.get_funding_index_unsafe(synthetic_id);
                collateral_provisional_balance +=
                    calculate_funding(
                        old_funding_index: synthetic.funding_index,
                        new_funding_index: global_funding_index,
                        balance: synthetic.balance,
                    );
            }
            collateral_provisional_balance
        }
        /// Returns all assets from the position, excluding assets with zero balance
        /// and those included in `position_diff`.
        /// Also calculates the provisional funding delta for the position.
        fn derive_funding_delta_and_unchanged_synthetics(
            self: @ComponentState<TContractState>,
            position: StoragePath<Position>,
            position_diff: PositionDiff,
        ) -> (Balance, Span<Asset>) {
            let assets = get_dep_component!(self, Assets);
            let mut unchanged_synthetics = array![];

            let synthetic_diff_id = if let Option::Some((id, _)) = position_diff.synthetic_diff {
                id
            } else {
                Default::default()
            };
            let mut provisional_delta: Balance = 0_i64.into();

            for (synthetic_id, synthetic) in position.assets_balance {
                let balance = synthetic.balance;
                if balance.is_zero() {
                    continue;
                }
                let (price, funding_index) = assets
                    .get_price_and_funding_index(asset_id: synthetic_id);

                provisional_delta +=
                    calculate_funding(
                        old_funding_index: synthetic.funding_index,
                        new_funding_index: funding_index,
                        balance: synthetic.balance,
                    );
                if synthetic_diff_id == synthetic_id {
                    continue;
                }
                let risk_factor = assets.get_asset_risk_factor(synthetic_id, balance, price);
                unchanged_synthetics
                    .append(Asset { id: synthetic_id, balance, price, risk_factor });
            }

            (provisional_delta, unchanged_synthetics.span())
        }
    }

    #[generate_trait]
    impl PrivateImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        /// Updates the synthetic balance and handles the funding mechanism.
        /// This function adjusts the main collateral balance of a position by applying funding
        /// costs or earnings based on the difference between the global funding index and the
        /// current funding index.
        ///
        /// The main collateral balance is updated using the following formula:
        /// main_collateral_balance += assets_balance * (old_funding_index - new_funding_index).
        /// After the adjustment, the `funding_index` is set to `global_funding_index`.
        ///
        /// Example:
        /// main_collateral_balance = 1000;
        /// assets_balance = 50;
        /// old_funding_index = 200;
        /// new_funding_index = 210;
        ///
        /// new_synthetic_balance = 300;
        ///
        /// After the update:
        /// main_collateral_balance = 500; // 1000 + 50 * (200 - 210)
        /// assets_balance = 300;
        /// synthetic_funding_index = 210;
        ///
        fn _update_synthetic_balance_and_funding(
            ref self: ComponentState<TContractState>,
            position: StoragePath<Mutable<Position>>,
            synthetic_id: AssetId,
            synthetic_diff: Balance,
        ) {
            let assets = get_dep_component!(@self, Assets);
            let global_funding_index = assets.get_funding_index(:synthetic_id);

            // Adjusts the main collateral balance accordingly:
            let (collateral_funding, current_synthetic_balance) = if let Option::Some(synthetic) =
                position
                .assets_balance
                .read(synthetic_id) {
                let current_synthetic_balance = synthetic.balance;
                (
                    calculate_funding(
                        old_funding_index: synthetic.funding_index,
                        new_funding_index: global_funding_index,
                        balance: current_synthetic_balance,
                    ),
                    current_synthetic_balance,
                )
            } else {
                (0_i64.into(), 0_i64.into())
            };
            position.collateral_balance.add_and_write(collateral_funding);

            // Updates the synthetic balance and funding index:
            let synthetic_asset = SyntheticBalance {
                version: POSITION_VERSION,
                balance: current_synthetic_balance + synthetic_diff,
                funding_index: global_funding_index,
            };
            position.assets_balance.write(synthetic_id, synthetic_asset);
        }

        fn _get_position_state(
            self: @ComponentState<TContractState>, position: StoragePath<Position>,
        ) -> PositionState {
            let position_diff = Default::default();
            let (provisional_delta, unchanged_synthetics) = self
                .derive_funding_delta_and_unchanged_synthetics(:position, :position_diff);
            let collateral_balance = self
                .get_collateral_provisional_balance(
                    :position, provisional_delta: Option::Some(provisional_delta),
                );
            evaluate_position(:unchanged_synthetics, :collateral_balance)
        }
    }
}
