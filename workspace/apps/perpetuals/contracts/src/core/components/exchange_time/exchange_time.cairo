/// # Exchange Time Component
///
/// The Exchange Time component provides a mechanism for managing the contract's exchange time.
/// It allows the operator to update the exchange time, which must be monotonically increasing
/// and not exceed the current block timestamp.
#[starknet::component]
pub mod ExchangeTimeComponent {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::exchange_time::constants::MAX_TIME_DRIFT;
    use perpetuals::core::components::exchange_time::errors::{
        ALREADY_INITIALIZED, NON_MONOTONIC_TIME, STALE_TIME, TIMESTAMP_TOO_OLD,
    };
    use perpetuals::core::components::exchange_time::interface::IExchangeTime;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::constants::WEEK;
    use starkware_utils::time::time::{Time, Timestamp};

    #[storage]
    pub struct Storage {
        exchange_time: Timestamp,
        last_time_of_exchange_time_update: Timestamp,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ExchangeTimeUpdated: ExchangeTimeUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ExchangeTimeUpdated {
        pub new_timestamp: Timestamp,
    }

    #[embeddable_as(ExchangeTimeImpl)]
    impl ExchangeTimeComponent<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
    > of IExchangeTime<ComponentState<TContractState>> {
        fn get_exchange_time(self: @ComponentState<TContractState>) -> Timestamp {
            self.exchange_time.read()
        }

        fn get_time_of_last_update(self: @ComponentState<TContractState>) -> Timestamp {
            self.last_time_of_exchange_time_update.read()
        }

        /// Updates the exchange time stored in the contract.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - Only the operator can call this function.
        /// - The operator_nonce must be valid.
        /// - The new exchange time must be strictly greater than the current exchange time
        ///   (monotonically increasing).
        /// - The new exchange time must not drift more than MAX_TIME_DRIFT seconds from the current
        ///   Starknet block timestamp (cannot be too far in the future).
        /// - The new exchange time must be larger than now - WEEK (cannot be more than a week in
        ///   the past).
        ///
        /// Execution:
        /// - Updates the exchange time storage.
        /// - Emits an ExchangeTimeUpdated event with the new timestamp.
        fn update_exchange_time(
            ref self: ComponentState<TContractState>, operator_nonce: u64, new_timestamp: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut operator_nonce_component = get_dep_component_mut!(ref self, OperatorNonce);
            operator_nonce_component.use_checked_nonce(:operator_nonce);

            // The new exchange time must be strictly greater than the current exchange time.
            let current_exchange_time = self.exchange_time.read();
            assert(new_timestamp > current_exchange_time, NON_MONOTONIC_TIME);

            let now = Time::now();
            // The new exchange time cannot be more than a day in the past.
            let min_acceptable_time = now.sub_delta(Time::seconds(WEEK));
            assert(new_timestamp > min_acceptable_time, TIMESTAMP_TOO_OLD);

            let acceptable_time = now.add(Time::seconds(MAX_TIME_DRIFT));
            assert(new_timestamp <= acceptable_time, STALE_TIME);

            self.exchange_time.write(new_timestamp);
            self.last_time_of_exchange_time_update.write(now);

            self.emit(ExchangeTimeUpdated { new_timestamp });
        }
    }
    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>) {
            assert(self.exchange_time.read() == Zero::zero(), ALREADY_INITIALIZED);

            let now = Time::now();
            self.exchange_time.write(now);
            self.last_time_of_exchange_time_update.write(now);
        }
    }
}
