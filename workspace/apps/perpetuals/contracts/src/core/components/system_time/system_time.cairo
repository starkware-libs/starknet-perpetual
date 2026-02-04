/// # System Time Component
///
/// The System Time component provides a mechanism for managing the contract's system time.
/// It allows the operator to update the system time, which must be monotonically increasing
/// and not exceed the current block timestamp.
#[starknet::component]
pub mod SystemTimeComponent {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::system_time::constants::MAX_TIME_DRIFT;
    use perpetuals::core::components::system_time::errors::{NON_MONOTONIC_TIME, STALE_TIME};
    use perpetuals::core::components::system_time::interface::ISystemTime;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::time::time::{Time, Timestamp};

    #[storage]
    pub struct Storage {
        system_time: Timestamp,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TimeTick: TimeTick,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TimeTick {
        pub new_timestamp: Timestamp,
    }

    #[embeddable_as(SystemTimeImpl)]
    impl SystemTimeComponent<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
    > of ISystemTime<ComponentState<TContractState>> {
        /// Returns the current system time stored in the contract.
        fn get_system_time(self: @ComponentState<TContractState>) -> Timestamp {
            self.system_time.read()
        }

        /// Updates the system time stored in the contract.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - Only the operator can call this function.
        /// - The operator_nonce must be valid.
        /// - The new system time must be strictly greater than the current system time.
        /// - The new system time must not drift more than MAX_TIME_DRIFT seconds from the current Starknet block timestamp.
        ///
        /// Execution:
        /// - Updates the system time.
        fn update_system_time(
            ref self: ComponentState<TContractState>, operator_nonce: u64, new_timestamp: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut operator_nonce_component = get_dep_component_mut!(ref self, OperatorNonce);
            operator_nonce_component.use_checked_nonce(:operator_nonce);

            // The new system time must be strictly greater than the current system time.
            let current_system_time = self.system_time.read();
            assert(new_timestamp > current_system_time, NON_MONOTONIC_TIME);

            let now = Time::now();
            let acceptable_time = now.add(Time::seconds(MAX_TIME_DRIFT));
            assert(new_timestamp <= acceptable_time, STALE_TIME);

            self.system_time.write(new_timestamp);

            self.emit(TimeTick { new_timestamp });
        }
    }
}
