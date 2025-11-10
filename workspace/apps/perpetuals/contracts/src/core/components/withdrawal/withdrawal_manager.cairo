use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::Timestamp;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub withdraw_request_hash: felt252,
    pub salt: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Withdraw {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    #[key]
    pub withdraw_request_hash: felt252,
    pub salt: felt252,
}

#[starknet::interface]
pub trait IWithdrawalManager<TContractState> {
    fn withdraw_request(
        ref self: TContractState,
        signature: Signature,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
}

#[starknet::contract]
pub(crate) mod WithdrawalManager {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::IERC20DispatcherTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalImpl as AssetsInternal;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit::InternalImpl as DepositInternal;
    use perpetuals::core::components::fulfillment::fulfillment::Fulfillement as FulfillmentComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalImpl as OperatorNonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::types::position::{PositionId, PositionTrait};
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerReadAccess;
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalImpl as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::validate_expiration;
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_WITHDRAWALS;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::components::snip::SNIP12MetadataImpl;
    use crate::core::errors::{INVALID_ZERO_AMOUNT, WITHDRAW_EXPIRED};
    use crate::core::types::position::PositionDiff;
    use crate::core::types::withdraw::WithdrawArgs;
    use super::{IWithdrawalManager, Signature, Timestamp, Withdraw, WithdrawRequest};

    impl SnipImpl = SNIP12MetadataImpl;

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Withdraw: Withdraw,
        WithdrawRequest: WithdrawRequest,
        #[flat]
        FulfillmentEvent: FulfillmentComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        PositionsEvent: PositionsComponent::Event,
        #[flat]
        RequestApprovalsEvent: RequestApprovalsComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
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
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub positions: PositionsComponent::Storage,
        #[substorage(v0)]
        pub fulfillment_tracking: FulfillmentComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
    }

    component!(path: FulfillmentComponent, storage: fulfillment_tracking, event: FulfillmentEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: PositionsComponent, storage: positions, event: PositionsEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );

    #[abi(embed_v0)]
    impl TypedComponent of ITypedComponent<ContractState> {
        fn component_type(ref self: ContractState) -> felt252 {
            EXTERNAL_COMPONENT_WITHDRAWALS
        }
    }

    #[abi(embed_v0)]
    impl WithdrawalManagerImpl of IWithdrawalManager<ContractState> {
        fn withdraw_request(
            ref self: ContractState,
            signature: Signature,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            let position = self.positions.get_position_snapshot(:position_id);
            let collateral_id = self.assets.get_collateral_id();
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            let owner_account = if (position.owner_protection_enabled.read()) {
                position.get_owner_account()
            } else {
                Option::None
            };
            let hash = self
                .request_approvals
                .register_approval(
                    owner_account: owner_account,
                    public_key: position.get_owner_public_key(),
                    :signature,
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                );
            self
                .emit(
                    WithdrawRequest {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        withdraw_request_hash: hash,
                        salt,
                    },
                );
        }

        fn withdraw(
            ref self: ContractState,
            operator_nonce: u64,
            recipient: starknet::ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: super::Timestamp,
            salt: felt252,
        ) {
            validate_expiration(expiration: expiration, err: WITHDRAW_EXPIRED);
            let collateral_id = self.assets.get_collateral_id();
            let position = self.positions.get_position_snapshot(:position_id);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                    public_key: position.get_owner_public_key(),
                );

            /// Validations - Fundamentals:
            let position_diff = PositionDiff {
                collateral_diff: -amount.into(), asset_diff: Option::None,
            };

            self
                .positions
                .validate_healthy_or_healthier_position(
                    :position_id, :position, :position_diff, tvtr_before: Default::default(),
                );

            self.positions.apply_diff(:position_id, :position_diff);
            let quantum = self.assets.get_collateral_quantum();
            let withdraw_unquantized_amount = quantum * amount;
            let token_contract = self.assets.get_collateral_token_contract();
            token_contract.transfer(:recipient, amount: withdraw_unquantized_amount.into());

            self
                .emit(
                    Withdraw {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        withdraw_request_hash: hash,
                        salt,
                    },
                );
        }
    }
}
