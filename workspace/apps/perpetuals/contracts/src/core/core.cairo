#[starknet::contract]
pub mod Core {
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use core::num::traits::{Pow, Zero};
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::IERC20DispatcherTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::components::assets::errors::{NOT_SYNTHETIC, NO_SUCH_ASSET};
    use perpetuals::core::components::deposit::Deposit;
    use perpetuals::core::components::deposit::Deposit::InternalTrait as DepositInternal;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as OperatorNonceInternal;
    use perpetuals::core::components::positions::Positions;
    use perpetuals::core::components::positions::Positions::{
        FEE_POSITION, InternalTrait as PositionsInternalTrait,
    };
    use perpetuals::core::components::system_time::SystemTimeComponent;
    use perpetuals::core::errors::{
        AMOUNT_OVERFLOW, FORCED_WAIT_REQUIRED, INVALID_ZERO_TIMEOUT, LENGTH_MISMATCH,
        ORDER_IS_NOT_EXPIRED, TRADE_ASSET_NOT_SYNTHETIC, TRANSFER_FAILED, ZERO_MAX_INTEREST_RATE,
    };
    use perpetuals::core::events;
    use perpetuals::core::interface::{ICore, Settlement};
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::synthetic::AssetType;
    use perpetuals::core::types::balance::Balance;
    use perpetuals::core::types::order::{ForcedRedeemFromVault, ForcedTrade, LimitOrder, Order};
    use perpetuals::core::types::position::{PositionDiff, PositionId, PositionTrait};
    use perpetuals::core::types::price::PriceMulTrait;
    use perpetuals::core::types::vault::ConvertPositionToVault;
    use perpetuals::core::value_risk_calculator::PositionTVTR;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        StorageMapReadAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_info, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::components::roles::interface::IRoles;
    use starkware_utils::hash::message_hash::OffchainMessageHash;
    use starkware_utils::signature::stark::{PublicKey, Signature};
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::{Time, TimeDelta, Timestamp};
    use crate::core::components::assets::interface::IAssets;
    use crate::core::components::deleverage::deleverage_manager::IDeleverageManagerDispatcherTrait;
    use crate::core::components::deposit::events as deposit_events;
    use crate::core::components::external_components::external_component_manager::ExternalComponents as ExternalComponentsComponent;
    use crate::core::components::external_components::external_component_manager::ExternalComponents::InternalTrait as ExternalComponentsInternalTrait;
    use crate::core::components::fulfillment::fulfillment::Fulfillement;
    use crate::core::components::fulfillment::interface::IFulfillment;
    use crate::core::components::liquidation::liquidation_manager::ILiquidationManagerDispatcherTrait;
    use crate::core::components::snip::SNIP12MetadataImpl;
    use crate::core::components::transfer::transfer_manager::ITransferManagerDispatcherTrait;
    use crate::core::components::vaults::events as vault_events;
    use crate::core::components::vaults::vaults::Vaults::InternalTrait as VaultsInternal;
    use crate::core::components::vaults::vaults::{IVaults, Vaults as VaultsComponent};
    use crate::core::components::vaults::vaults_contract::IVaultExternalDispatcherTrait;
    use crate::core::components::withdrawal::withdrawal_manager::IWithdrawalManagerDispatcherTrait;
    use crate::core::utils::{validate_signature, validate_trade};


    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: SystemTimeComponent, storage: system_time, event: SystemTimeEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: Deposit, storage: deposits, event: DepositEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );
    component!(path: Positions, storage: positions, event: PositionsEvent);
    component!(path: Fulfillement, storage: fulfillment_tracking, event: FulfillmentEvent);
    component!(
        path: ExternalComponentsComponent,
        storage: external_components,
        event: ExternalComponentsEvent,
    );

    component!(path: VaultsComponent, storage: vaults, event: VaultsEvent);


    #[abi(embed_v0)]
    impl OperatorNonceImpl =
        OperatorNonceComponent::OperatorNonceImpl<ContractState>;

    #[abi(embed_v0)]
    impl SystemTimeImpl = SystemTimeComponent::SystemTimeImpl<ContractState>;

    #[abi(embed_v0)]
    impl DepositImpl = Deposit::DepositImpl<ContractState>;

    #[abi(embed_v0)]
    impl RequestApprovalsImpl =
        RequestApprovalsComponent::RequestApprovalsImpl<ContractState>;

    #[abi(embed_v0)]
    impl AssetsImpl = AssetsComponent::AssetsImpl<ContractState>;

    #[abi(embed_v0)]
    impl AssetsManagerImpl = AssetsComponent::AssetsManagerImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[abi(embed_v0)]
    impl PositionsImpl = Positions::PositionsImpl<ContractState>;

    #[abi(embed_v0)]
    impl ExternalComponentsImpl =
        ExternalComponentsComponent::ExternalComponentsImpl<ContractState>;


    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        operator_nonce: OperatorNonceComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        system_time: SystemTimeComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub deposits: Deposit::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        pub positions: Positions::Storage,
        #[substorage(v0)]
        pub fulfillment_tracking: Fulfillement::Storage,
        #[substorage(v0)]
        pub external_components: ExternalComponentsComponent::Storage,
        #[substorage(v0)]
        pub vaults: VaultsComponent::Storage,
        /// ------- Core -------
        // Forced action parameters:
        // Timelock before forced actions can be executed.
        forced_action_timelock: TimeDelta,
        // Cost for executing forced actions.
        premium_cost: u64,
        // Maximum interest rate per second (32-bit fixed-point with 32-bit fractional part).
        // Example: max_interest_rate_per_sec = 10 means the rate is 10 / 2^32 ≈ 0.000000232 per
        // second, which is approximately 7.4% per year.
        max_interest_rate_per_sec: u32,
        // Whether the new escape hatch logic is enabled. 
        // Off by default to be enabled one time in the future
        forced_actions_enabled: bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        SystemTimeEvent: SystemTimeComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        DepositEvent: Deposit::Event,
        #[flat]
        RequestApprovalsEvent: RequestApprovalsComponent::Event,
        #[flat]
        PositionsEvent: Positions::Event,
        Deleverage: events::Deleverage,
        AssetPositionReduced: events::AssetPositionReduced,
        Liquidate: events::Liquidate,
        Trade: events::Trade,
        Withdraw: events::Withdraw,
        WithdrawRequest: events::WithdrawRequest,
        ForcedTradeRequest: events::ForcedTradeRequest,
        ForcedTrade: events::ForcedTrade,
        ForcedRedeemFromVaultRequest: vault_events::ForcedRedeemFromVaultRequest,
        ForcedRedeemFromVault: vault_events::ForcedRedeemFromVault,
        #[flat]
        FulfillmentEvent: Fulfillement::Event,
        #[flat]
        ExternalComponentsEvent: ExternalComponentsComponent::Event,
        #[flat]
        VaultsEvent: VaultsComponent::Event,
        //duplicated for ABI
        Deposit: deposit_events::Deposit,
        DepositCanceled: deposit_events::DepositCanceled,
        DepositProcessed: deposit_events::DepositProcessed,
        InvestInVault: vault_events::InvestInVault,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        collateral_id: AssetId,
        collateral_token_address: ContractAddress,
        // Collateral quantum must make the minimal collateral unit == 10^-6 USD. For more details
        // see `SN_PERPS_SCALE` in the `price.cairo` file.
        collateral_quantum: u64,
        max_price_interval: TimeDelta,
        max_oracle_price_validity: TimeDelta,
        max_funding_interval: TimeDelta,
        max_funding_rate: u32,
        cancel_delay: TimeDelta,
        fee_position_owner_public_key: PublicKey,
        insurance_fund_position_owner_public_key: PublicKey,
        forced_action_timelock: u64,
        premium_cost: u64,
        max_interest_rate_per_sec: u32,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self
            .assets
            .initialize(
                :collateral_id,
                :collateral_token_address,
                :collateral_quantum,
                :max_price_interval,
                :max_funding_interval,
                :max_funding_rate,
                :max_oracle_price_validity,
            );
        self.deposits.initialize(:cancel_delay);
        self
            .positions
            .initialize(:fee_position_owner_public_key, :insurance_fund_position_owner_public_key);

        assert(forced_action_timelock.is_non_zero(), INVALID_ZERO_TIMEOUT);
        self.forced_action_timelock.write(TimeDelta { seconds: forced_action_timelock });
        self.premium_cost.write(premium_cost);
        assert(max_interest_rate_per_sec.is_non_zero(), ZERO_MAX_INTEREST_RATE);
        self.max_interest_rate_per_sec.write(max_interest_rate_per_sec);
    }

    #[abi(embed_v0)]
    pub impl CoreImpl of ICore<ContractState> {
        /// Requests a withdrawal of a collateral amount from a position to a `recipient`.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the request does not exist.
        /// - Validates the owner account is the caller.
        ///
        /// Execution:
        /// - Registers the withdraw request.
        /// - Emits a `WithdrawRequest` event.
        fn withdraw_request(
            ref self: ContractState,
            signature: Signature,
            collateral_id: AssetId,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            if (self._is_vault(vault_position: position_id)) {
                panic_with_felt252('VAULT_CANNOT_INITIATE_WITHDRAW');
            }
            self
                .external_components
                ._get_withdrawal_manager_dispatcher()
                .withdraw_request(
                    :signature,
                    :collateral_id,
                    :recipient,
                    :position_id,
                    :amount,
                    :expiration,
                    :salt,
                );
        }

        /// Withdraw collateral `amount` from the a position to `recipient`.
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
        /// - The withdrawal message has not been fulfilled.
        /// - A fact was registered for the withdraw message.
        /// - Validate the position is healthy after the withdraw.
        ///
        /// Execution:
        /// - Transfer the collateral `amount` to the `recipient`.
        /// - Update the position's collateral balance.
        /// - Mark the withdrawal message as fulfilled.
        fn withdraw(
            ref self: ContractState,
            operator_nonce: u64,
            collateral_id: AssetId,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_withdrawal_manager_dispatcher()
                .withdraw(:collateral_id, :recipient, :position_id, :amount, :expiration, :salt);
        }

        fn transfer_request(
            ref self: ContractState,
            signature: Signature,
            asset_id: AssetId,
            recipient: PositionId,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            if (self._is_vault(vault_position: position_id)) {
                panic_with_felt252('VAULT_CANNOT_INITIATE_TRANSFER');
            }
            self
                .external_components
                ._get_transfer_manager_dispatcher()
                .transfer_request(
                    :signature, :asset_id, :recipient, :position_id, :amount, :expiration, :salt,
                );
        }

        fn transfer(
            ref self: ContractState,
            operator_nonce: u64,
            asset_id: AssetId,
            recipient: PositionId,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_transfer_manager_dispatcher()
                .transfer(
                    :operator_nonce,
                    :asset_id,
                    :recipient,
                    :position_id,
                    :amount,
                    :expiration,
                    :salt,
                );
        }

        fn multi_trade(ref self: ContractState, operator_nonce: u64, trades: Span<Settlement>) {
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            let mut tvtr_cache: Felt252Dict<Nullable<PositionTVTR>> = Default::default();

            for _trade in trades {
                let trade = *_trade;
                let position_id_a: felt252 = trade.order_a.position_id.value.into();
                let position_id_b: felt252 = trade.order_b.position_id.value.into();
                // In case there is no cached tvtr for position, it will be Nullable::Null.
                let cached_pos_a_tvtr = tvtr_cache.get(position_id_a);
                let cached_pos_b_tvtr = tvtr_cache.get(position_id_b);
                let (updated_a, updated_b) = self
                    ._execute_trade(
                        signature_a: trade.signature_a,
                        signature_b: trade.signature_b,
                        order_a: trade.order_a,
                        order_b: trade.order_b,
                        actual_amount_base_a: trade.actual_amount_base_a,
                        actual_amount_quote_a: trade.actual_amount_quote_a,
                        actual_fee_a: trade.actual_fee_a,
                        actual_fee_b: trade.actual_fee_b,
                        tvtr_a_before: cached_pos_a_tvtr,
                        tvtr_b_before: cached_pos_b_tvtr,
                        check_signature: true,
                    );
                tvtr_cache.insert(position_id_a, NullableTrait::new(updated_a));
                tvtr_cache.insert(position_id_b, NullableTrait::new(updated_b));
            }
        }

        fn clean_fulfillments(
            ref self: ContractState, orders: Span<Order>, public_keys: Span<felt252>,
        ) {
            assert(orders.len() == public_keys.len(), LENGTH_MISMATCH);
            let now = Time::now();
            let mut hashes = array![];
            let mut i: usize = 0;

            for order in orders {
                assert(*order.expiration < now, ORDER_IS_NOT_EXPIRED);
                let public_key = *public_keys[i];
                let hash = order.get_message_hash(:public_key);
                hashes.append(hash);
                i += 1;
            }
            self.fulfillment_tracking.clean_fulfillment(hashes.span());
        }


        /// Executes a trade between two orders (Order A and Order B).
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Validates signatures for both orders using the public keys of their respective owners.
        /// - Ensures the fee amounts in both orders are positive.
        /// - Validates that the base and quote asset types match between the two orders.
        /// - Verifies the signs of amounts:
        ///   - Ensures the sign of amounts in each order is consistent.
        ///   - Ensures the signs between Order A and Order B amounts are opposite where required.
        /// - Ensures the order fulfillment amounts do not exceed their respective limits.
        /// - Validates that the fee ratio does not increase.
        /// - Ensures the base-to-quote amount ratio does not decrease.
        ///
        /// Execution:
        /// - Subtract the fees from each position's collateral.
        /// - Add the fees to the `fee_position`.
        /// - Update Order A's position and Order B's position, based on `actual_amount_base`.
        /// - Adjust collateral balances.
        /// - Perform fundamental validation for both positions after the execution.
        /// - Update order fulfillment.
        fn trade(
            ref self: ContractState,
            operator_nonce: u64,
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);

            self
                ._execute_trade(
                    :signature_a,
                    :signature_b,
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                    tvtr_a_before: Default::default(),
                    tvtr_b_before: Default::default(),
                    check_signature: true,
                );
        }

        fn liquidate(
            ref self: ContractState,
            operator_nonce: u64,
            liquidator_signature: Signature,
            liquidated_position_id: PositionId,
            liquidator_order: Order,
            actual_amount_base_liquidated: i64,
            actual_amount_quote_liquidated: i64,
            actual_liquidator_fee: u64,
            /// The `liquidated_fee_amount` is paid by the liquidated position to the
            /// insurance fund position.
            liquidated_fee_amount: u64,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_liquidation_manager_dispatcher()
                .liquidate(
                    :liquidator_signature,
                    :liquidated_position_id,
                    :liquidator_order,
                    :actual_amount_base_liquidated,
                    :actual_amount_quote_liquidated,
                    :actual_liquidator_fee,
                    :liquidated_fee_amount,
                );
        }

        /// Executes a deleverage of a user position with a deleverager position.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in base and quote.
        ///   - Ensures the sign of amounts in each position is consistent.
        /// - Verifies that the base asset is active.
        /// - validates the deleveraged position is deleveragable.
        ///
        /// Execution:
        /// - Update the position, based on `delevereged_base_asset`.
        /// - Adjust collateral balances based on `delevereged_quote_asset`.
        /// - Perform fundamental validation for both positions after the execution.
        fn deleverage(
            ref self: ContractState,
            operator_nonce: u64,
            deleveraged_position_id: PositionId,
            deleverager_position_id: PositionId,
            base_asset_id: AssetId,
            deleveraged_base_amount: i64,
            deleveraged_quote_amount: i64,
        ) {
            /// Validations:
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_deleverage_manager_dispatcher()
                .deleverage(
                    :deleveraged_position_id,
                    :deleverager_position_id,
                    :base_asset_id,
                    :deleveraged_base_amount,
                    :deleveraged_quote_amount,
                )
        }

        /// Executes a spot asset deleverage of a user position with a deleverager position.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The prices of all assets in the system are valid.
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in spot and base collateral.
        ///   - Ensures the sign of amounts in each position is consistent.
        /// - Verifies that the spot asset is active.
        /// - validates the deleveraged position is deleveragable.
        ///
        /// Execution:
        /// - Update the position, based on `delevereged_spot_asset`.
        /// - Adjust collateral balances based on `delevereged_base_collateral_amount`.
        /// - Perform fundamental validation for both positions after the execution.
        fn deleverage_spot_asset(
            ref self: ContractState,
            operator_nonce: u64,
            deleveraged_position_id: PositionId,
            deleverager_position_id: PositionId,
            asset_id: AssetId,
            deleveraged_amount: i64,
            deleveraged_base_collateral_amount: i64,
        ) {
            /// Validations:
            self.pausable.assert_not_paused();
            self.assets.validate_price_interval_integrity(Time::now());
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_deleverage_manager_dispatcher()
                .deleverage_spot_asset(
                    :deleveraged_position_id,
                    :deleverager_position_id,
                    :asset_id,
                    :deleveraged_amount,
                    :deleveraged_base_collateral_amount,
                )
        }

        /// Executes a trade between position with inactive synthetic assets.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Verifies that the base asset is inactive.
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in base and quote.
        ///   - Ensures the sign of amounts in each position is consistent.
        ///
        /// Execution:
        /// - Update the position, based on `base_asset`.
        /// - Adjust collateral balances based on `quote_amount`.
        fn reduce_asset_position(
            ref self: ContractState,
            operator_nonce: u64,
            position_id_a: PositionId,
            position_id_b: PositionId,
            base_asset_id: AssetId,
            base_amount_a: i64,
        ) {
            /// Validations:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            let position_a = self.positions.get_position_snapshot(position_id: position_id_a);
            let position_b = self.positions.get_position_snapshot(position_id: position_id_b);

            if let Option::Some(config) = self.assets.asset_config.read(base_asset_id) {
                assert(config.asset_type == AssetType::SYNTHETIC, NOT_SYNTHETIC);
            } else {
                panic_with_felt252(NO_SUCH_ASSET);
            }
            let base_balance: Balance = base_amount_a.into();
            let quote_amount_a: i64 = -1
                * self
                    .assets
                    .get_asset_price(asset_id: base_asset_id)
                    .mul(rhs: base_balance)
                    .try_into()
                    .expect(AMOUNT_OVERFLOW);
            self
                .positions
                ._validate_imposed_reduction_trade(
                    :position_id_a,
                    :position_id_b,
                    :position_a,
                    :position_b,
                    :base_asset_id,
                    :base_amount_a,
                    :quote_amount_a,
                );

            /// Execution:
            let position_diff_a = PositionDiff {
                collateral_diff: quote_amount_a.into(),
                asset_diff: Option::Some((base_asset_id, base_amount_a.into())),
            };
            // Passing the negative of actual amounts to position_b as it is linked to position_a.
            let position_diff_b = PositionDiff {
                collateral_diff: -quote_amount_a.into(),
                asset_diff: Option::Some((base_asset_id, -base_amount_a.into())),
            };

            // Apply diffs
            self.positions.apply_diff(position_id: position_id_a, position_diff: position_diff_a);
            self.positions.apply_diff(position_id: position_id_b, position_diff: position_diff_b);

            self
                .emit(
                    events::AssetPositionReduced {
                        position_id_a,
                        position_id_b,
                        base_asset_id,
                        base_amount_a,
                        quote_asset_id: self.assets.get_collateral_id(),
                        quote_amount_a,
                    },
                )
        }


        fn redeem_from_vault(
            ref self: ContractState,
            operator_nonce: u64,
            signature: Signature,
            order: LimitOrder,
            vault_approval: LimitOrder,
            vault_signature: Signature,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_vault_manager_dispatcher()
                .redeem_from_vault(
                    :signature,
                    :order,
                    :vault_approval,
                    :vault_signature,
                    :actual_shares_user,
                    :actual_collateral_user,
                )
        }

        fn liquidate_vault_shares(
            ref self: ContractState,
            operator_nonce: u64,
            liquidated_position_id: PositionId,
            vault_approval: LimitOrder,
            vault_signature: Span<felt252>,
            liquidated_asset_id: AssetId,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_vault_manager_dispatcher()
                .liquidate_vault_shares(
                    :liquidated_position_id,
                    :vault_approval,
                    :vault_signature,
                    :liquidated_asset_id,
                    :actual_shares_user,
                    :actual_collateral_user,
                )
        }
        fn activate_vault(
            ref self: ContractState,
            operator_nonce: u64,
            order: ConvertPositionToVault,
            signature: Signature,
        ) {
            self.assets.validate_assets_integrity();
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_vault_manager_dispatcher()
                .activate_vault(:order, :signature)
        }
        fn invest_in_vault(
            ref self: ContractState,
            operator_nonce: u64,
            signature: Span<felt252>,
            order: LimitOrder,
            correlation_id: felt252,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self
                .external_components
                ._get_vault_manager_dispatcher()
                .invest_in_vault(:signature, :order, :correlation_id)
        }

        // Forced actions.

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
        ) {
            assert(self._is_escape_hatch_enabled(), 'ESCAPE-HATCH-DISABLED');
            assert(!self._is_vault(vault_position: position_id), 'VAULT_CANNOT_INITIATE_WITHDRAW');
            self
                .external_components
                ._get_withdrawal_manager_dispatcher()
                .forced_withdraw_request(
                    :signature,
                    :collateral_id,
                    :recipient,
                    :position_id,
                    :amount,
                    :expiration,
                    :salt,
                );
        }

        /// Executes a previously submitted forced withdrawal request for a position.
        ///
        /// Validations:
        /// - Validates that a matching forced withdrawal request exists.
        /// - Validates the request is not already completed.
        /// - Validates the forced request timeout has passed.
        /// - Validates after the withdrawal the position still healthy.
        ///
        /// Execution:
        /// - Processes the forced withdrawal and releases the collateral to the recipient.
        /// - Marks the forced request as completed and clears the pending entry.
        /// - Emits a `ForcedWithdraw` event.
        fn forced_withdraw(
            ref self: ContractState,
            collateral_id: AssetId,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self
                .external_components
                ._get_withdrawal_manager_dispatcher()
                .forced_withdraw(
                    :collateral_id, :recipient, :position_id, :amount, :expiration, :salt,
                );
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
            assert(self._is_escape_hatch_enabled(), 'ESCAPE-HATCH-DISABLED');
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
            let premium_cost = self.premium_cost.read();
            let quantum = self.assets.get_collateral_quantum();
            let token_contract = self.assets.get_base_collateral_token_contract();
            assert(
                token_contract
                    .transfer_from(
                        sender: get_caller_address(),
                        recipient: get_block_info().sequencer_address,
                        amount: (premium_cost * quantum).into(),
                    ),
                TRANSFER_FAILED,
            );

            self
                .emit(
                    events::ForcedTradeRequest {
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

        /// Executes a previously submitted forced trade request for a position.
        ///
        /// Validations:
        /// - Validates that a matching forced trade request exists.
        /// - Validates the request is not already completed.
        /// - Validates the forced request timeout has passed.
        /// - Execute regular trade validations.
        ///
        /// Execution:
        /// - Processes the forced trade.
        /// - Marks the forced request as completed and clears the pending entry.
        /// - Emits a `ForcedTrade` event.
        fn forced_trade(
            ref self: ContractState, operator_nonce: u64, order_a: Order, order_b: Order,
        ) {
            let position_a = self.positions.get_position_snapshot(position_id: order_a.position_id);
            let position_b = self.positions.get_position_snapshot(position_id: order_b.position_id);
            let public_key_a = position_a.get_owner_public_key();
            let public_key_b = position_b.get_owner_public_key();

            // Check forced request.
            let (request_time, _) = self
                .request_approvals
                .consume_forced_approved_request(
                    args: ForcedTrade { order_a, order_b }, public_key: public_key_a,
                );

            // Only operator can process the force trade during timelock.
            if !self.roles.is_operator(get_caller_address()) {
                let now = Time::now();
                let forced_action_timelock = self.forced_action_timelock.read();
                assert(request_time.add(forced_action_timelock) <= now, FORCED_WAIT_REQUIRED);
            } else {
                self.operator_nonce.use_checked_nonce(:operator_nonce);
            }

            // Execute trade.
            self
                ._execute_trade(
                    signature_a: array![].span(),
                    signature_b: array![].span(),
                    :order_a,
                    :order_b,
                    actual_amount_base_a: order_a.base_amount,
                    actual_amount_quote_a: order_a.quote_amount,
                    actual_fee_a: Zero::zero(),
                    actual_fee_b: Zero::zero(),
                    tvtr_a_before: Default::default(),
                    tvtr_b_before: Default::default(),
                    check_signature: false,
                );

            self
                .emit(
                    events::ForcedTrade {
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
                        actual_amount_base_a: order_a.base_amount,
                        actual_amount_quote_a: order_a.quote_amount,
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
            let premium_cost = self.premium_cost.read();
            let quantum = self.assets.get_collateral_quantum();
            let token_contract = self.assets.get_base_collateral_token_contract();
            assert(
                token_contract
                    .transfer_from(
                        sender: get_caller_address(),
                        recipient: get_block_info().sequencer_address,
                        amount: (premium_cost * quantum).into(),
                    ),
                TRANSFER_FAILED,
            );

            self
                .emit(
                    vault_events::ForcedRedeemFromVaultRequest {
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

        /// Executes a previously submitted forced redeem from vault request.
        ///
        /// Validations:
        /// - Validates that a matching forced redeem request exists.
        /// - Validates the request is not already completed.
        /// - If the caller is the operator, validates the operator nonce.
        /// - If the caller is not the operator, validates the forced request timeout has passed.
        /// - Execute regular redeem validations.
        ///
        /// Execution:
        /// - Processes the forced redeem.
        /// - Marks the forced request as completed and clears the pending entry.
        /// - Emits a `ForcedRedeemFromVault` event.
        fn force_redeem_from_vault(
            ref self: ContractState,
            operator_nonce: u64,
            order: LimitOrder,
            vault_approval: LimitOrder,
        ) {
            let redeeming_position = self
                .positions
                .get_position_snapshot(position_id: order.source_position);
            let public_key = redeeming_position.get_owner_public_key();

            // Check forced request.
            let (request_time, _) = self
                .request_approvals
                .consume_forced_approved_request(
                    args: ForcedRedeemFromVault { order, vault_approval }, public_key: public_key,
                );

            // Only operator can process the force redeem during timelock.
            if !self.roles.is_operator(get_caller_address()) {
                let now = Time::now();
                let forced_action_timelock = self.forced_action_timelock.read();
                assert(request_time.add(forced_action_timelock) <= now, FORCED_WAIT_REQUIRED);
            } else {
                self.operator_nonce.use_checked_nonce(:operator_nonce);
            }

            // Execute redeem.
            self
                .external_components
                ._get_vault_manager_dispatcher()
                .force_redeem_from_vault(:order, :vault_approval);

            self
                .emit(
                    vault_events::ForcedRedeemFromVault {
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
                    },
                );
        }

        fn apply_interests(
            ref self: ContractState,
            operator_nonce: u64,
            position_ids: Span<PositionId>,
            interest_amounts: Span<i64>,
        ) {
            assert(position_ids.len() == interest_amounts.len(), LENGTH_MISMATCH);
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);

            // Read once and pass as arguments to avoid redundant storage reads
            let current_time = self.get_system_time();
            let max_interest_rate_per_sec = self.max_interest_rate_per_sec.read();
            let interest_rate_scale: u64 = 2_u64.pow(32);

            let mut i: usize = 0;
            for position_id in position_ids {
                let interest_amount = *interest_amounts[i];
                self
                    .positions
                    .apply_interest(
                        position_id: *position_id,
                        :interest_amount,
                        :current_time,
                        :max_interest_rate_per_sec,
                        :interest_rate_scale,
                    );
                i += 1;
            }
        }

        fn liquidate_spot_asset(
            ref self: ContractState,
            operator_nonce: u64,
            liquidated_position_id: PositionId,
            liquidator_order: LimitOrder,
            liquidator_signature: Signature,
            actual_amount_spot_collateral: i64,
            actual_amount_base_collateral: i64,
            actual_liquidator_fee: u64,
            liquidated_fee_amount: u64,
        ) {
            self.pausable.assert_not_paused();
            self.assets.validate_assets_integrity();
            self.operator_nonce.use_checked_nonce(:operator_nonce);

            self
                .external_components
                ._get_liquidation_manager_dispatcher()
                .liquidate_spot_asset(
                    :liquidated_position_id,
                    :liquidator_order,
                    :liquidator_signature,
                    :actual_amount_spot_collateral,
                    :actual_amount_base_collateral,
                    :actual_liquidator_fee,
                    :liquidated_fee_amount,
                );
        }

        fn enable_escape_hatch(ref self: ContractState) { 
            assert(self.roles.is_governance_admin(get_caller_address()), 'NOT-GOVERNANCE-ADMIN');
            self.forced_actions_enabled.write(true);
        }
    }

    #[generate_trait]
    pub impl InternalCoreFunctions of InternalCoreFunctionsTrait {
        fn _execute_trade(
            ref self: ContractState,
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
            tvtr_a_before: Nullable<PositionTVTR>,
            tvtr_b_before: Nullable<PositionTVTR>,
            check_signature: bool,
        ) -> (PositionTVTR, PositionTVTR) {
            let synthetic_asset = self.assets.get_asset_config(order_a.base_asset_id);
            assert(synthetic_asset.asset_type == AssetType::SYNTHETIC, TRADE_ASSET_NOT_SYNTHETIC);
            validate_trade(
                :order_a,
                :order_b,
                :actual_amount_base_a,
                :actual_amount_quote_a,
                :actual_fee_a,
                :actual_fee_b,
                asset: Some(synthetic_asset),
                collateral_id: self.assets.get_collateral_id(),
            );
            let position_id_a = order_a.position_id;
            let position_id_b = order_b.position_id;

            let position_a = self.positions.get_position_snapshot(position_id_a);
            let position_b = self.positions.get_position_snapshot(position_id_b);
            // Signatures validation:
            let (hash_a, hash_b) = match check_signature {
                true => (
                    validate_signature(
                        public_key: position_a.get_owner_public_key(),
                        message: order_a,
                        signature: signature_a,
                    ),
                    validate_signature(
                        public_key: position_b.get_owner_public_key(),
                        message: order_b,
                        signature: signature_b,
                    ),
                ),
                false => (
                    order_a.get_message_hash(public_key: position_a.get_owner_public_key()),
                    order_b.get_message_hash(public_key: position_b.get_owner_public_key()),
                ),
            };

            // Validate and update fulfillments.
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: position_id_a,
                    hash: hash_a,
                    order_base_amount: order_a.base_amount,
                    actual_base_amount: actual_amount_base_a,
                );

            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: position_id_b,
                    hash: hash_b,
                    order_base_amount: order_b.base_amount,
                    // Passing the negative of actual amounts to `order_b` as it is linked to
                    // `order_a`.
                    actual_base_amount: -actual_amount_base_a,
                );

            /// Positions' Diffs:
            let position_diff_a = PositionDiff {
                collateral_diff: actual_amount_quote_a.into() - actual_fee_a.into(),
                asset_diff: Option::Some((order_a.base_asset_id, actual_amount_base_a.into())),
            };

            // Passing the negative of actual amounts to order_b as it is linked to order_a.
            let position_diff_b = PositionDiff {
                collateral_diff: -actual_amount_quote_a.into() - actual_fee_b.into(),
                asset_diff: Option::Some((order_b.base_asset_id, -actual_amount_base_a.into())),
            };

            // Assuming fee_asset_id is the same for both orders.
            let fee_position_diff = PositionDiff {
                collateral_diff: (actual_fee_a + actual_fee_b).into(), asset_diff: Option::None,
            };

            /// Validations - Fundamentals:
            let tvtr_a_after = self
                .positions
                .validate_healthy_or_healthier_position(
                    position_id: order_a.position_id,
                    position: position_a,
                    position_diff: position_diff_a,
                    tvtr_before: tvtr_a_before,
                );
            let tvtr_b_after = self
                .positions
                .validate_healthy_or_healthier_position(
                    position_id: order_b.position_id,
                    position: position_b,
                    position_diff: position_diff_b,
                    tvtr_before: tvtr_b_before,
                );

            // Apply Diffs.
            self
                .positions
                .apply_diff(position_id: order_a.position_id, position_diff: position_diff_a);

            self
                .positions
                .apply_diff(position_id: order_b.position_id, position_diff: position_diff_b);

            self.positions.apply_diff(position_id: FEE_POSITION, position_diff: fee_position_diff);

            self
                .emit(
                    events::Trade {
                        order_a_position_id: position_id_a,
                        order_a_base_asset_id: order_a.base_asset_id,
                        order_a_base_amount: order_a.base_amount,
                        order_a_quote_asset_id: order_a.quote_asset_id,
                        order_a_quote_amount: order_a.quote_amount,
                        fee_a_asset_id: order_a.fee_asset_id,
                        fee_a_amount: order_a.fee_amount,
                        order_b_position_id: position_id_b,
                        order_b_base_asset_id: order_b.base_asset_id,
                        order_b_base_amount: order_b.base_amount,
                        order_b_quote_asset_id: order_b.quote_asset_id,
                        order_b_quote_amount: order_b.quote_amount,
                        fee_b_asset_id: order_b.fee_asset_id,
                        fee_b_amount: order_b.fee_amount,
                        actual_amount_base_a,
                        actual_amount_quote_a,
                        actual_fee_a,
                        actual_fee_b,
                        order_a_hash: hash_a,
                        order_b_hash: hash_b,
                    },
                );
            (tvtr_a_after, tvtr_b_after)
        }

        fn _is_vault(ref self: ContractState, vault_position: PositionId) -> bool {
            self.vaults.is_vault_position(vault_position)
        }

        fn _is_escape_hatch_enabled(ref self: ContractState) -> bool {
            return self.forced_actions_enabled.read();
        }
    }
}
