#[starknet::component]
pub(crate) mod Deposit {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use core::pedersen::PedersenTrait;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::interface::{DepositStatus, IDeposit};
    use perpetuals::core::components::deposit::{errors, events};
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternalTrait;
    use perpetuals::core::types::position::{PositionDiff, PositionId};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::signature::stark::HashType;
    use starkware_utils::time::time::{Time, TimeDelta};
    use crate::core::types::asset::AssetId;

    #[storage]
    pub struct Storage {
        registered_deposits: Map<HashType, DepositStatus>,
        cancel_delay: TimeDelta,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Deposit: events::Deposit,
        DepositCanceled: events::DepositCanceled,
        DepositProcessed: events::DepositProcessed,
    }


    #[embeddable_as(DepositImpl)]
    impl Deposit<
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
    > of IDeposit<ComponentState<TContractState>> {
        /// Deposit is called by the user to add a deposit request.
        ///
        /// Validations:
        /// - The quantized amount must be greater than 0.
        /// - The deposit requested does not exists.
        ///
        /// Execution:
        /// - Transfers the quantized amount from the user to the contract.
        /// - Registers the deposit request.
        /// - Updates the deposit status to pending.
        /// - Emits a Deposit event.
        fn deposit(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            // check recipient position exists
            get_dep_component_mut!(ref self, Positions).get_position_snapshot(:position_id);

            assert(quantized_amount.is_non_zero(), errors::ZERO_AMOUNT);
            let caller_address = get_caller_address();
            let assets = get_dep_component!(@self, Assets);

            let (token_contract, quantum) = if (asset_id == assets.get_collateral_id()) {
                (assets.get_collateral_token_contract(), assets.get_collateral_quantum())
            } else {
                let asset_config = assets.get_asset_config(asset_id);
                (assets.get_asset_erc20_contract(asset_id), asset_config.quantum)
            };

            let deposit_hash = deposit_hash(
                token_address: token_contract.contract_address,
                depositor: caller_address,
                :position_id,
                :quantized_amount,
                :salt,
            );
            assert(
                self.get_deposit_status(:deposit_hash) == DepositStatus::NOT_REGISTERED,
                errors::DEPOSIT_ALREADY_REGISTERED,
            );
            self
                .registered_deposits
                .write(key: deposit_hash, value: DepositStatus::PENDING(Time::now()));
            let unquantized_amount = quantized_amount * quantum.into();
            token_contract
                .transfer_from(
                    sender: caller_address,
                    recipient: get_contract_address(),
                    amount: unquantized_amount.into(),
                );
            self
                .emit(
                    events::Deposit {
                        position_id,
                        depositing_address: caller_address,
                        collateral_id: asset_id,
                        quantized_amount,
                        unquantized_amount,
                        deposit_request_hash: deposit_hash,
                        salt,
                    },
                );
        }

        /// Cancel deposit is called by the user to cancel a deposit request which did not take
        /// place yet.
        ///
        /// Validations:
        /// - The deposit requested to cancel exists, is not canceled and is not processed.
        /// - The cancellation delay has passed.
        ///
        /// Execution:
        /// - Transfers the quantized amount back to the user.
        /// - Updates the deposit status to canceled.
        /// - Emits a DepositCanceled event.
        fn cancel_deposit(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            let caller_address = get_caller_address();
            let assets = get_dep_component!(@self, Assets);
            let token_contract = assets.get_collateral_token_contract();
            let deposit_hash = deposit_hash(
                token_address: token_contract.contract_address,
                depositor: caller_address,
                :position_id,
                :quantized_amount,
                :salt,
            );

            // Validations
            match self.get_deposit_status(:deposit_hash) {
                DepositStatus::PENDING(deposit_timestamp) => assert(
                    Time::now() > deposit_timestamp.add(self.cancel_delay.read()),
                    errors::DEPOSIT_NOT_CANCELABLE,
                ),
                DepositStatus::NOT_REGISTERED => panic_with_felt252(errors::DEPOSIT_NOT_REGISTERED),
                DepositStatus::PROCESSED => panic_with_felt252(errors::DEPOSIT_ALREADY_PROCESSED),
                DepositStatus::CANCELED => panic_with_felt252(errors::DEPOSIT_ALREADY_CANCELED),
            }

            self.registered_deposits.write(key: deposit_hash, value: DepositStatus::CANCELED);

            let quantum = assets.get_collateral_quantum();
            let unquantized_amount = quantized_amount * quantum.into();
            token_contract.transfer(recipient: caller_address, amount: unquantized_amount.into());
            self
                .emit(
                    events::DepositCanceled {
                        position_id,
                        depositing_address: caller_address,
                        collateral_id: assets.get_collateral_id(),
                        quantized_amount,
                        unquantized_amount,
                        deposit_request_hash: deposit_hash,
                        salt,
                    },
                );
        }

        /// Process deposit a collateral amount from the 'depositing_address' to a given position.
        ///
        /// Validations:
        /// - Only the operator can call this function.
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The `expiration` time has not passed.
        /// - The collateral asset exists in the system.
        /// - The collateral asset is active.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - The deposit message has not been fulfilled.
        /// - A fact was registered for the deposit message.
        /// - If position exists, validate the owner_public_key and owner_account are the same.
        ///
        /// Execution:
        /// - Transfer the collateral `amount` to the position from the pending deposits.
        /// - Update the position's collateral balance.
        /// - Mark the deposit message as fulfilled.
        fn process_deposit(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            asset_id: AssetId,
            depositor: ContractAddress,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);
            let assets = get_dep_component!(@self, Assets);
            let (token_contract, quantum, position_diff) = if (asset_id == assets
                .get_collateral_id()) {
                let position_diff = PositionDiff {
                    base_collateral_diff: quantized_amount.into(),
                    synthetic_diff: Option::None,
                    non_base_collateral_diff: Option::None,
                };
                (
                    assets.get_collateral_token_contract(),
                    assets.get_collateral_quantum(),
                    position_diff,
                )
            } else {
                let asset_config = assets.get_asset_config(asset_id);
                let position_diff = PositionDiff {
                    base_collateral_diff: 0_i64.into(),
                    synthetic_diff: Option::None,
                    non_base_collateral_diff: Option::Some((asset_id, quantized_amount.into())),
                };
                (assets.get_asset_erc20_contract(asset_id), asset_config.quantum, position_diff)
            };

            let deposit_hash = deposit_hash(
                token_address: token_contract.contract_address,
                :depositor,
                :position_id,
                :quantized_amount,
                :salt,
            );
            let deposit_status = self.get_deposit_status(:deposit_hash);
            match deposit_status {
                DepositStatus::NOT_REGISTERED => {
                    panic_with_felt252(errors::DEPOSIT_NOT_REGISTERED)
                },
                DepositStatus::PROCESSED => {
                    panic_with_felt252(errors::DEPOSIT_ALREADY_PROCESSED)
                },
                DepositStatus::CANCELED => { panic_with_felt252(errors::DEPOSIT_ALREADY_CANCELED) },
                DepositStatus::PENDING(_) => {},
            }
            let unquantized_amount = quantized_amount * quantum.into();
            self.registered_deposits.write(deposit_hash, DepositStatus::PROCESSED);
            let mut positions = get_dep_component_mut!(ref self, Positions);
            positions.apply_diff(:position_id, :position_diff);
            self
                .emit(
                    events::DepositProcessed {
                        position_id,
                        depositing_address: depositor,
                        collateral_id: asset_id,
                        quantized_amount,
                        unquantized_amount,
                        deposit_request_hash: deposit_hash,
                        salt,
                    },
                );
        }

        fn get_deposit_status(
            self: @ComponentState<TContractState>, deposit_hash: HashType,
        ) -> DepositStatus {
            self.registered_deposits.read(deposit_hash)
        }

        fn get_cancel_delay(self: @ComponentState<TContractState>) -> TimeDelta {
            self.cancel_delay.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, cancel_delay: TimeDelta) {
            assert(self.cancel_delay.read().is_zero(), errors::ALREADY_INITIALIZED);
            assert(cancel_delay.is_non_zero(), errors::INVALID_CANCEL_DELAY);
            self.cancel_delay.write(cancel_delay);
        }
    }

    pub fn deposit_hash(
        token_address: ContractAddress,
        depositor: ContractAddress,
        position_id: PositionId,
        quantized_amount: u64,
        salt: felt252,
    ) -> HashType {
        PedersenTrait::new(base: token_address.into())
            .update_with(value: depositor)
            .update_with(value: position_id)
            .update_with(value: quantized_amount)
            .update_with(value: salt)
            .finalize()
    }
}

