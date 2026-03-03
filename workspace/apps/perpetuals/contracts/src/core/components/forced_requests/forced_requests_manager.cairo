use perpetuals::core::events::ForcedTradeRequest;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::{LimitOrder, Order};
use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::signature::stark::{HashType, Signature};
use starkware_utils::time::time::Timestamp;
use crate::core::components::vaults::events::ForcedRedeemFromVaultRequest;

#[starknet::interface]
pub trait IForcedRequestsManager<TContractState> {
    fn forced_withdraw_request(
        ref self: TContractState,
        signature: Signature,
        collateral_id: AssetId,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    ) -> HashType;
    fn forced_trade_request(
        ref self: TContractState,
        signature_a: Signature,
        signature_b: Signature,
        order_a: Order,
        order_b: Order,
    );
    fn forced_redeem_from_vault_request(
        ref self: TContractState,
        signature: Signature,
        vault_signature: Signature,
        order: LimitOrder,
        vault_approval: LimitOrder,
    );
}

#[starknet::contract]
pub(crate) mod ForcedRequestsManager {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::IERC20DispatcherTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalImpl as AssetsInternal;
    use perpetuals::core::components::assets::errors::{ASSET_NOT_EXISTS, CANNOT_WITHDRAW_SYNTHETIC};
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::exchange_time::ExchangeTimeComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::components::snip::SNIP12MetadataImpl;
    use perpetuals::core::errors::{
        ESCAPE_HATCH_DISABLED, INSUFFICIENT_APPROVAL, INVALID_EXPIRATION, INVALID_ZERO_AMOUNT,
        TRANSFER_FAILED,
    };
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::synthetic::{AssetType, SyntheticTrait};
    use perpetuals::core::types::order::{ForcedRedeemFromVault, ForcedTrade, LimitOrder, Order};
    use perpetuals::core::types::position::PositionTrait;
    use perpetuals::core::types::withdraw::{ForcedWithdrawArgs, WithdrawArgs};
    use starknet::storage::{StorageAsPointer, StoragePathEntry, StoragePointerReadAccess};
    use starknet::{ContractAddress, get_block_info, get_caller_address, get_contract_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::hash::message_hash::OffchainMessageHash;
    use starkware_utils::signature::stark::{HashType, Signature};
    use starkware_utils::time::time::{Time, TimeDelta, Timestamp};
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_FORCED_REQUESTS;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::components::vaults::vaults::Vaults::InternalTrait as VaultsInternal;
    use crate::core::components::vaults::vaults::{IVaults, Vaults as VaultsComponent};
    use crate::core::types::position::PositionId;
    use crate::core::utils::validate_signature;
    use super::{ForcedRedeemFromVaultRequest, ForcedTradeRequest, IForcedRequestsManager};

    impl SnipImpl = SNIP12MetadataImpl;

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ForcedWithdrawRequest: perpetuals::core::events::ForcedWithdrawRequest,
        ForcedTradeRequest: perpetuals::core::events::ForcedTradeRequest,
        ForcedRedeemFromVaultRequest: crate::core::components::vaults::events::ForcedRedeemFromVaultRequest,
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
        #[flat]
        VaultsEvent: VaultsComponent::Event,
        #[flat]
        ExchangeTimeEvent: ExchangeTimeComponent::Event,
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
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub positions: PositionsComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        pub vaults: VaultsComponent::Storage,
        #[substorage(v0)]
        exchange_time: ExchangeTimeComponent::Storage,
        // Whether the new escape hatch logic is enabled.
        forced_actions_enabled: bool,
        // Cost for executing forced actions.
        premium_cost: u64,
        // Timelock before forced actions can be executed.
        forced_action_timelock: TimeDelta,
    }

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
    component!(path: VaultsComponent, storage: vaults, event: VaultsEvent);
    component!(path: ExchangeTimeComponent, storage: exchange_time, event: ExchangeTimeEvent);

    #[abi(embed_v0)]
    impl TypedComponent of ITypedComponent<ContractState> {
        fn component_type(ref self: ContractState) -> felt252 {
            EXTERNAL_COMPONENT_FORCED_REQUESTS
        }
    }

    #[abi(embed_v0)]
    impl ForcedRequestsManagerImpl of IForcedRequestsManager<ContractState> {
        /// Requests a forced withdrawal of a collateral amount from a position.
        ///
        /// Validations:
        /// - Validates the position is not a vault position.
        /// - Validates the forced request signature.
        /// - Validates the position exists.
        /// - Validates no pending forced withdraw request already exists for this position.
        /// - Validates the caller is the position owner.
        ///
        /// Execution:
        /// - Stores the forced withdrawal request hash in pending forced actions.
        /// - transfer `ForcedFee` amount.
        /// - Emits a `ForcedWithdrawRequest` event.
        fn forced_withdraw_request(
            ref self: ContractState,
            signature: Signature,
            collateral_id: AssetId,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) -> HashType {
            assert(self._is_escape_hatch_enabled(), ESCAPE_HATCH_DISABLED);
            assert(!self.vaults.is_vault_position(position_id), 'VAULT_CANNOT_INITIATE_WITHDRAW');

            // Validate position exists.
            let position = self.positions.get_position_snapshot(:position_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);

            let now = Time::now();
            let forced_action_timelock = self.forced_action_timelock.read();
            assert(now.add(forced_action_timelock) <= expiration, INVALID_EXPIRATION);

            // Validate valid collateral id.
            if collateral_id != self.assets.get_base_collateral_id() {
                let entry = (@self).assets.asset_config.entry(collateral_id).as_ptr();
                assert(SyntheticTrait::is_some_config(entry), ASSET_NOT_EXISTS);
                assert(
                    SyntheticTrait::at_asset_type(entry) != AssetType::SYNTHETIC,
                    CANNOT_WITHDRAW_SYNTHETIC,
                );
            }

            let owner_account = if (position.owner_protection_enabled.read()) {
                position.get_owner_account()
            } else {
                Option::None
            };
            let public_key = position.get_owner_public_key();

            // Validate the withdraw request was not registered nor processed yet.
            let withdraw_args_hash = self
                .request_approvals
                .store_approval(
                    :public_key,
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                );

            // Validate the forced request signature
            let hash = self
                .request_approvals
                .register_forced_approval(
                    :owner_account,
                    :public_key,
                    :signature,
                    args: ForcedWithdrawArgs { withdraw_args_hash },
                );

            // Transfer premium_cost (forced fee) from the caller to the sequencer address.
            self._collect_forced_action_premium();

            self
                .emit(
                    perpetuals::core::events::ForcedWithdrawRequest {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        forced_withdraw_request_hash: hash,
                        salt,
                    },
                );
            hash
        }

        /// Requests a forced trade - it enables withdrawal of synthetic amount from a position.
        ///
        /// Validations:
        /// - Validates the forced request signature.
        /// - Validates the position exists.
        /// - Validates no pending forced withdraw request already exists for this position.
        /// - Validates the caller is the position owner.
        ///
        /// Execution:
        /// - Stores the forced withdrawal request hash in pending forced actions.
        /// - transfer `ForcedFee` amount.
        /// - Emits a `ForcedTradeRequest` event.
        fn forced_trade_request(
            ref self: ContractState,
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
        ) {
            assert(self._is_escape_hatch_enabled(), ESCAPE_HATCH_DISABLED);
            let position_a = self.positions.get_position_snapshot(position_id: order_a.position_id);
            let position_b = self.positions.get_position_snapshot(position_id: order_b.position_id);

            // Validate the caller is the position owner account
            let owner_account = if (position_a.owner_protection_enabled.read()) {
                position_a.get_owner_account()
            } else {
                Option::None
            };
            let public_key_a = position_a.get_owner_public_key();
            let public_key_b = position_b.get_owner_public_key();

            // Validate the forced request signatures.
            self
                .request_approvals
                .register_forced_approval(
                    :owner_account,
                    public_key: public_key_a,
                    signature: signature_a,
                    args: ForcedTrade { order_a, order_b },
                );

            validate_signature(
                public_key: public_key_b,
                message: ForcedTrade { order_a, order_b },
                signature: signature_b,
            );

            // Transfer premium_cost (forced fee) from the caller to the sequencer address.
            self._collect_forced_action_premium();

            self
                .emit(
                    ForcedTradeRequest {
                        order_a_position_id: order_a.position_id,
                        order_a_base_asset_id: order_a.base_asset_id,
                        order_a_base_amount: order_a.base_amount,
                        order_a_quote_asset_id: order_a.quote_asset_id,
                        order_a_quote_amount: order_a.quote_amount,
                        fee_a_asset_id: order_a.fee_asset_id,
                        fee_a_amount: order_a.fee_amount,
                        order_b_position_id: order_b.position_id,
                        order_b_base_asset_id: order_b.base_asset_id,
                        order_b_base_amount: order_b.base_amount,
                        order_b_quote_asset_id: order_b.quote_asset_id,
                        order_b_quote_amount: order_b.quote_amount,
                        fee_b_asset_id: order_b.fee_asset_id,
                        fee_b_amount: order_b.fee_amount,
                        order_a_hash: order_a.get_message_hash(public_key: public_key_a),
                        order_b_hash: order_b.get_message_hash(public_key: public_key_b),
                    },
                );
        }

        /// Requests a forced redeem from vault - it enables redemption of vault shares without
        /// operator approval.
        ///
        /// Validations:
        /// - Validates the forced request signature.
        /// - Validates the position exists.
        /// - Validates the caller is the position owner.
        ///
        /// Execution:
        /// - Stores the forced redemption request hash in pending forced actions.
        /// - transfer `ForcedFee` amount.
        /// - Emits a `ForcedRedeemFromVaultRequest` event.
        fn forced_redeem_from_vault_request(
            ref self: ContractState,
            signature: Signature,
            vault_signature: Signature,
            order: LimitOrder,
            vault_approval: LimitOrder,
        ) {
            assert(self._is_escape_hatch_enabled(), ESCAPE_HATCH_DISABLED);

            let redeeming_position = self
                .positions
                .get_position_snapshot(position_id: order.source_position);
            let vault_config = self.vaults.get_vault_config_for_asset(order.base_asset_id);
            let vault_position_id: PositionId = vault_config.position_id.into();
            let vault_position = self
                .positions
                .get_position_snapshot(position_id: vault_position_id);

            // Validate the caller is the position owner account
            let owner_account = if (redeeming_position.owner_protection_enabled.read()) {
                redeeming_position.get_owner_account()
            } else {
                Option::None
            };
            let public_key = redeeming_position.get_owner_public_key();
            let vault_public_key = vault_position.get_owner_public_key();
            let forced_redeem_from_vault = ForcedRedeemFromVault { order, vault_approval };

            // Validate the forced request signatures.
            let hash = self
                .request_approvals
                .register_forced_approval(
                    :owner_account, :public_key, :signature, args: forced_redeem_from_vault,
                );

            validate_signature(
                public_key: vault_public_key,
                message: forced_redeem_from_vault,
                signature: vault_signature,
            );

            // Transfer premium_cost (forced fee) from the caller to the sequencer address.
            self._collect_forced_action_premium();

            self
                .emit(
                    ForcedRedeemFromVaultRequest {
                        order_source_position: order.source_position,
                        order_receive_position: order.receive_position,
                        order_base_asset_id: order.base_asset_id,
                        order_base_amount: order.base_amount,
                        order_quote_asset_id: order.quote_asset_id,
                        order_quote_amount: order.quote_amount,
                        order_fee_asset_id: order.fee_asset_id,
                        order_fee_amount: order.fee_amount,
                        order_expiration: order.expiration,
                        order_salt: order.salt,
                        vault_approval_source_position: vault_approval.source_position,
                        vault_approval_receive_position: vault_approval.receive_position,
                        vault_approval_base_asset_id: vault_approval.base_asset_id,
                        vault_approval_base_amount: vault_approval.base_amount,
                        vault_approval_quote_asset_id: vault_approval.quote_asset_id,
                        vault_approval_quote_amount: vault_approval.quote_amount,
                        vault_approval_fee_asset_id: vault_approval.fee_asset_id,
                        vault_approval_fee_amount: vault_approval.fee_amount,
                        vault_approval_expiration: vault_approval.expiration,
                        vault_approval_salt: vault_approval.salt,
                        hash,
                    },
                );
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn _is_escape_hatch_enabled(ref self: ContractState) -> bool {
            return self.forced_actions_enabled.read();
        }

        /// Transfers the premium cost (forced fee) from the caller to the sequencer address.
        fn _collect_forced_action_premium(ref self: ContractState) {
            let caller = get_caller_address();
            let premium_cost = self.premium_cost.read();
            let quantum = self.assets.get_collateral_quantum();
            let token_contract = self.assets.get_base_collateral_token_contract();
            let amount: u256 = (premium_cost * quantum).into();
            let outstanding_allowance = token_contract
                .allowance(owner: caller, spender: get_contract_address());
            assert(outstanding_allowance >= amount, INSUFFICIENT_APPROVAL);

            assert(
                token_contract
                    .transfer_from(
                        sender: caller, recipient: get_block_info().sequencer_address, :amount,
                    ),
                TRANSFER_FAILED,
            );
        }
    }
}
