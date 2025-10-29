#[starknet::component]
pub mod FulfillmentComponent {
    use core::panics::panic_with_byte_array;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::types::position::PositionId;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::math::abs::Abs;
    use starkware_utils::signature::stark::HashType;

    #[storage]
    pub struct Storage {
        // Order hash to fulfilled absolute base amount.
        fulfillment: Map<HashType, u64>,
    }

    pub fn fulfillment_exceeded_err(position_id: PositionId) -> ByteArray {
        format!("FULFILLMENT_EXCEEDED position_id: {:?}", position_id)
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn update_fulfillment(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            hash: HashType,
            order_base_amount: i64,
            actual_base_amount: i64,
        ) {
            let fulfillment_entry = self.fulfillment.entry(hash);
            let total_amount = fulfillment_entry.read() + actual_base_amount.abs();
            if (total_amount > order_base_amount.abs()) {
                let err = @fulfillment_exceeded_err(:position_id);
                panic_with_byte_array(:err);
            }
            fulfillment_entry.write(total_amount);
        }
    }
}
