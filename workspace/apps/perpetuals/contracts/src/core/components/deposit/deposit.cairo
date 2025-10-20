#[starknet::component]
pub(crate) mod Deposit {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use core::pedersen::PedersenTrait;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::components::deposit::interface::{DepositStatus, IDeposit};
    use perpetuals::core::components::deposit::{errors, events};
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternalTrait;
    use perpetuals::core::types::asset::{AssetId, AssetType};
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
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternalTrait;
    use starkware_utils::signature::stark::HashType;
    use starkware_utils::time::time::{Time, TimeDelta};

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
            depositor: ContractAddress,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            // check recipient position exists
            get_dep_component!(@self, Positions).get_position_snapshot(:position_id);

            assert(quantized_amount.is_non_zero(), errors::ZERO_AMOUNT);
            let (asset_type, token_contract, quantum) = get_dep_component!(@self, Assets)
                .get_token_contract_and_quantum(:asset_id);
            let perps_address = get_contract_address();
            self._assert_depositor(:asset_type, :depositor, :perps_address);
            let deposit_hash = deposit_hash(
                token_address: token_contract.contract_address,
                :depositor,
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

            // For vault share deposits, the tokens are already in the contract (depositor ==
            // perps_address)
            // so we skip the transfer_from to avoid redundant self-transfer
            if asset_type != AssetType::VAULT_SHARE_COLLATERAL {
                assert(
                    token_contract
                        .transfer_from(
                            sender: depositor,
                            recipient: perps_address,
                            amount: unquantized_amount.into(),
                        ),
                    errors::TRANSFER_FAILED,
                );
            }
            self
                .emit(
                    events::Deposit {
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
            asset_id: AssetId,
            depositor: ContractAddress,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            let (asset_type, token_contract, quantum) = get_dep_component!(@self, Assets)
                .get_token_contract_and_quantum(:asset_id);
            let perps_address = get_contract_address();
            self._assert_depositor(:asset_type, :depositor, :perps_address);
            let deposit_hash = deposit_hash(
                token_address: token_contract.contract_address,
                :depositor,
                :position_id,
                :quantized_amount,
                :salt,
            );

            // Validate deposit can be canceled
            self._assert_cancelable(deposit_hash, self.cancel_delay.read());

            self
                ._cancel_deposit(
                    asset_id,
                    token_contract,
                    quantum,
                    depositor,
                    position_id,
                    quantized_amount,
                    salt,
                    deposit_hash,
                )
        }


        /// Reject deposit is called by the operator to cancel a deposit request which did not take
        /// place yet.
        ///
        /// Validations:
        /// - The deposit requested to cancel exists, is not canceled and is not processed.
        /// - The cancellation delay has passed.
        /// - Only the operator can call this function.
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        ///
        /// Execution:
        /// - Transfers the quantized amount back to the user.
        /// - Updates the deposit status to canceled.
        /// - Emits a DepositCanceled event.
        fn reject_deposit(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            asset_id: AssetId,
            depositor: ContractAddress,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);

            let (_asset_type, token_contract, quantum) = get_dep_component!(@self, Assets)
                .get_token_contract_and_quantum(:asset_id);
            let deposit_hash = deposit_hash(
                token_address: token_contract.contract_address,
                :depositor,
                :position_id,
                :quantized_amount,
                :salt,
            );

            // Validate deposit can be rejected (no timestamp check needed for operator)
            self._assert_cancelable(deposit_hash, Zero::zero());

            self
                ._cancel_deposit(
                    asset_id,
                    token_contract,
                    quantum,
                    depositor,
                    position_id,
                    quantized_amount,
                    salt,
                    deposit_hash,
                )
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

            let (asset_type, token_contract, quantum) = get_dep_component!(@self, Assets)
                .get_token_contract_and_quantum(:asset_id);
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

            let position_diff = match asset_type {
                AssetType::SPOT_COLLATERAL => PositionDiff {
                    collateral_diff: quantized_amount.into(), asset_diff: Option::None,
                },
                AssetType::VAULT_SHARE_COLLATERAL => PositionDiff {
                    collateral_diff: Zero::zero(),
                    asset_diff: Option::Some((asset_id, quantized_amount.into())),
                },
                AssetType::SYNTHETIC => { panic_with_felt252(errors::CANT_DEPOSIT_SYNTHETIC) },
            };

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
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, cancel_delay: TimeDelta) {
            assert(self.cancel_delay.read().is_zero(), errors::ALREADY_INITIALIZED);
            assert(cancel_delay.is_non_zero(), errors::INVALID_CANCEL_DELAY);
            self.cancel_delay.write(cancel_delay);
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
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        /// Cancels a deposit request and returns the tokens to the depositor.
        ///
        /// Arguments:
        /// - `cancel_delay`: The required delay before cancellation
        ///   - If zero: allows immediate cancellation (operator rejection)
        ///   - If positive: requires the delay to have passed (user cancellation)
        fn _cancel_deposit(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            token_contract: IERC20Dispatcher,
            quantum: u64,
            depositor: ContractAddress,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
            deposit_hash: HashType,
        ) {
            // Update deposit status
            self.registered_deposits.write(key: deposit_hash, value: DepositStatus::CANCELED);

            // Transfer tokens back to depositor
            let unquantized_amount = quantized_amount * quantum.into();
            assert(
                token_contract.transfer(recipient: depositor, amount: unquantized_amount.into()),
                errors::TRANSFER_FAILED,
            );
            self
                .emit(
                    events::DepositCanceled {
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

        /// Asserts that a deposit can be canceled based on its status and timing.
        ///
        /// Arguments:
        /// - `deposit_hash`: The hash of the deposit to validate
        /// - `cancel_delay`: The required delay before cancellation
        ///   - If zero: allows immediate cancellation (operator rejection)
        ///   - If positive: requires the delay to have passed (user cancellation)
        fn _assert_cancelable(
            self: @ComponentState<TContractState>, deposit_hash: HashType, cancel_delay: TimeDelta,
        ) {
            match self.get_deposit_status(deposit_hash) {
                DepositStatus::PENDING(deposit_timestamp) => {
                    if cancel_delay.is_non_zero() {
                        assert(
                            Time::now() > deposit_timestamp.add(cancel_delay),
                            errors::DEPOSIT_NOT_CANCELABLE,
                        );
                    }
                },
                DepositStatus::NOT_REGISTERED => panic_with_felt252(errors::DEPOSIT_NOT_REGISTERED),
                DepositStatus::PROCESSED => panic_with_felt252(errors::DEPOSIT_ALREADY_PROCESSED),
                DepositStatus::CANCELED => panic_with_felt252(errors::DEPOSIT_ALREADY_CANCELED),
            }
        }

        fn _assert_depositor(
            self: @ComponentState<TContractState>,
            asset_type: AssetType,
            depositor: ContractAddress,
            perps_address: ContractAddress,
        ) {
            match asset_type {
                AssetType::SPOT_COLLATERAL => {
                    assert(depositor == get_caller_address(), errors::DEPOSITOR_NOT_CALLER_ADDRESS);
                },
                AssetType::VAULT_SHARE_COLLATERAL => {
                    get_dep_component!(self, Roles).only_operator();
                    assert(depositor == perps_address, errors::DEPOSITOR_NOT_PERPS_ADDRESS);
                },
                AssetType::SYNTHETIC => { panic_with_felt252(errors::CANT_DEPOSIT_SYNTHETIC); },
            }
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

