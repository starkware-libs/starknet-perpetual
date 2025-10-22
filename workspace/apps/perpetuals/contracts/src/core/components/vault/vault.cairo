#[starknet::component]
pub mod VaultComponent {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::interfaces::token::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit as DepositComponent;
    use perpetuals::core::components::deposit::interface::IDeposit;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternalTrait;
    use perpetuals::core::components::vault::errors::{
        COLLATERAL_BALANCE_MISMATCH, INVALID_VAULT_CONTRACT_ADDRESS, NOT_VAULT_SHARE_ASSET,
        POSITION_IS_VAULT_POSITION, RECEIVED_AMOUNT_TOO_SMALL, SHARES_BALANCE_MISMATCH,
        VAULT_CONTRACT_ALREADY_EXISTS, VAULT_POSITION_ALREADY_EXISTS, VAULT_POSITION_HAS_SHARES,
        VAULT_REQUEST_ALREADY_FULFILLED,
    };
    use perpetuals::core::components::vault::events;
    use perpetuals::core::components::vault::interface::IVault;
    use perpetuals::core::core::Core::SNIP12MetadataImpl;
    use perpetuals::core::errors::{AMOUNT_OVERFLOW, INVALID_ZERO_AMOUNT, SIGNED_TX_EXPIRED};
    use perpetuals::core::types::asset::{AssetId, AssetType};
    use perpetuals::core::types::balance::Balance;
    use perpetuals::core::types::deposit_into_vault::VaultDepositArgs;
    use perpetuals::core::types::position::{Position, PositionDiff, PositionId, PositionTrait};
    use perpetuals::core::types::price::{Price, PriceMulTrait};
    use perpetuals::core::types::redeem_from_vault::{
        RedeemFromVaultOwnerArgs, RedeemFromVaultUserArgs,
    };
    use perpetuals::core::types::register_vault::RegisterVaultArgs;
    use perpetuals::core::utils::validate_signature;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePath, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::math::abs::Abs;
    use starkware_utils::signature::stark::{HashType, Signature};
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::{Time, Timestamp, validate_expiration};
    use vault::interface::{IProtocolVaultDispatcher, IProtocolVaultDispatcherTrait};

    #[storage]
    pub struct Storage {
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
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        DepositIntoVault: events::DepositIntoVault,
        RedeemedFromVault: events::RedeemedFromVault,
        VaultRegistered: events::VaultRegistered,
    }

    #[embeddable_as(VaultImpl)]
    impl Vault<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        +RequestApprovalsComponent::HasComponent<TContractState>,
        +RolesComponent::HasComponent<TContractState>,
        impl Deposit: DepositComponent::HasComponent<TContractState>,
    > of IVault<ComponentState<TContractState>> {
        /// Deposits a specified amount into a vault.
        ///
        /// Validations:
        /// - Ensures the contract is not paused.
        /// - Validates the operator nonce.
        /// - Checks price integrity.
        /// - Retrieves the vault share asset ID associated with the vault position.
        /// - Validates the deposit parameters including position IDs, amount, expiration,
        ///   and signature. Refer to `_validate_deposit_into_vault` for detailed validation steps.
        ///
        /// Execution:
        /// - Calculates the unquantized amount.
        /// - Deposits the unquantized amount into the vault contract.
        /// - Retrieves the shares amount from the vault contract.
        /// - Runs fundamental validation on the position ID.
        /// - Applies the diff in the collateral only.
        /// - Emits the event.
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
            let current_time = Time::now();
            let mut assets = get_dep_component_mut!(ref self, Assets);
            assets.validate_price_interval_integrity(:current_time);

            let vault_share_asset_id = self.vault_positions_to_assets.read(vault_position_id);
            self
                ._validate_deposit_into_vault(
                    :signature,
                    :position_id,
                    :vault_position_id,
                    :collateral_quantized_amount,
                    :expiration,
                    :salt,
                    :vault_share_asset_id,
                );

            /// Executions:
            let (asset_type, erc20_vault_dispatcher, vault_share_quantum) = assets
                .get_token_contract_and_quantum(asset_id: vault_share_asset_id);
            assert(asset_type == AssetType::VAULT_SHARE_COLLATERAL, NOT_VAULT_SHARE_ASSET);
            let actual_unquantized_vault_shares_amount = self
                ._execute_deposit_into_vault(
                    :position_id,
                    :vault_position_id,
                    :collateral_quantized_amount,
                    vault_address: erc20_vault_dispatcher.contract_address,
                    :vault_share_quantum,
                );

            let perps_address = get_contract_address();
            let actual_quantized_vault_shares_amount: u64 = (actual_unquantized_vault_shares_amount
                / vault_share_quantum.into())
                .try_into()
                .expect(AMOUNT_OVERFLOW);
            let mut deposit = get_dep_component_mut!(ref self, Deposit);
            deposit
                .deposit(
                    asset_id: vault_share_asset_id,
                    depositor: perps_address,
                    :position_id,
                    quantized_amount: actual_quantized_vault_shares_amount,
                    // As the operator nonce is unique, it can be used as salt.
                    salt: operator_nonce.into(),
                );

            // Emit event.
            self
                .emit(
                    events::DepositIntoVault {
                        position_id,
                        vault_position_id,
                        collateral_id: get_dep_component!(@self, Assets).get_collateral_id(),
                        quantized_amount: collateral_quantized_amount,
                        expiration,
                        salt,
                        quantized_shares_amount: actual_quantized_vault_shares_amount,
                    },
                );
        }

        /// Registers a vault.
        ///
        /// Validations:
        /// - Validates the operator nonce (and operator is the caller).
        /// - Validates the vault parameters including vault_position, vault_position id,
        /// vault_contract address, vault_asset_id, expiration,
        ///   and signature. Refer to `_validate_register_vault` for detailed validation steps.
        ///
        /// Execution:
        /// - Writes (vault_contract_address, vault_position_id) to the vault_positions_to_addresses
        /// map.
        /// - Writes (vault_asset_id, vault_position_id) to the vault_positions_to_assets map.
        /// - Writes (vault_contract_address, vault_position_id) to the addresses_to_vault_positions
        /// map.
        /// - Emits the event.
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
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);
            self
                ._validate_register_vault(
                    :vault_position_id,
                    :vault_contract_address,
                    :vault_asset_id,
                    :expiration,
                    :signature,
                );

            /// Execution:
            self.vault_positions_to_addresses.write(vault_position_id, vault_contract_address);
            self.vault_positions_to_assets.write(vault_position_id, vault_asset_id);
            self.addresses_to_vault_positions.write(vault_contract_address, vault_position_id);

            // Emit event:
            self
                .emit(
                    events::VaultRegistered {
                        vault_position_id, vault_contract_address, vault_asset_id, expiration,
                    },
                )
        }

        /// Redeems vault shares into collateral.
        ///
        /// Validations:
        /// - Ensures the contract is not paused.
        /// - Validates the operator nonce.
        /// - Checks price integrity.
        /// - Non-zero `number_of_shares`, `minimum_received_total_amount`,
        /// `vault_share_execution_price`.
        /// - Retrieves the vault share asset ID associated with the vault position.
        /// - Validates the withdraw parameters including position IDs, amount, expiration,
        ///   and signature.
        ///
        /// Execution:
        /// - Redeem shares from the vault; convert unquantized to quantized using collateral
        /// quantum.
        /// - Apply diffs: `position_id` (+collateral, −shares), `vault_position_id`
        /// (−collateral).
        /// - Validate both positions remain healthy or healthier; enforce vault collateral safety
        /// limit.
        /// - Emit `RedeemFromVault`.
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
            let current_time = Time::now();
            let mut assets = get_dep_component_mut!(ref self, Assets);
            assets.validate_price_interval_integrity(:current_time);

            let vault_share_asset_id = self.vault_positions_to_assets.read(vault_position_id);

            let (vault_position, position) = self
                ._validate_redeem_from_vault(
                    :position_id,
                    :user_signature,
                    :vault_position_id,
                    :vault_owner_signature,
                    :number_of_shares,
                    :minimum_received_total_amount,
                    :vault_share_execution_price,
                    :expiration,
                    :salt,
                    :vault_share_asset_id,
                );

            /// Executions:
            let actual_collateral_quantized_amount = self
                ._execute_redeem_from_vault(
                    :position_id,
                    :vault_position_id,
                    :number_of_shares,
                    :vault_share_execution_price,
                    :vault_share_asset_id,
                    :vault_position,
                    :position,
                );

            // Emit event.
            self
                .emit(
                    events::RedeemedFromVault {
                        position_id,
                        vault_position_id,
                        collateral_id: assets.get_collateral_id(),
                        quantized_amount: actual_collateral_quantized_amount,
                        expiration,
                        salt,
                        quantized_shares_amount: number_of_shares,
                        price: vault_share_execution_price,
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
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>,
        ) { // Checks that the component has not been initialized yet.
        }
    }

    #[generate_trait]
    impl PrivateImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl Deposit: DepositComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        +RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        /// Validates a deposit into a vault.
        ///
        /// This function ensures the transaction is valid by:
        /// - Checking tx expiration.
        /// - Verifying the vault asset is active, meaning vault asset has already a price.
        /// - Ensuring the position is not a vault position itself.
        /// - Confirming the deposit amount is non-zero.
        /// - Checking the signature.
        /// - Ensuring the operation hasn't been previously fulfilled.
        fn _validate_deposit_into_vault(
            ref self: ComponentState<TContractState>,
            signature: Signature,
            position_id: PositionId,
            vault_position_id: PositionId,
            collateral_quantized_amount: u64,
            expiration: Timestamp,
            salt: felt252,
            vault_share_asset_id: AssetId,
        ) {
            validate_expiration(expiration: expiration, err: SIGNED_TX_EXPIRED);

            get_dep_component!(@self, Assets).validate_active_asset(asset_id: vault_share_asset_id);
            let mut positions = get_dep_component!(@self, Positions);

            // Depositing position must not be a vault position.
            assert(!self._is_vault_position(:position_id), POSITION_IS_VAULT_POSITION);

            assert(collateral_quantized_amount.is_non_zero(), INVALID_ZERO_AMOUNT);

            // Signature validation
            let position = positions.get_position_snapshot(:position_id);
            let hash = validate_signature(
                public_key: position.get_owner_public_key(),
                message: VaultDepositArgs {
                    position_id, vault_position_id, collateral_quantized_amount, expiration, salt,
                },
                :signature,
            );
            let fulfilled_vault_request = self.fulfilled_vault_requests.entry(hash);
            assert(!fulfilled_vault_request.read(), VAULT_REQUEST_ALREADY_FULFILLED);
            fulfilled_vault_request.write(true);
        }

        /// Executes a deposit into vault by transferring collateral and receiving vault shares.
        ///
        /// - Converts quantized amount to unquantized amount using collateral quantum.
        /// - Deposits collateral into the vault contract and receives shares (using deposit flow).
        /// - Updates position balances: reduces collateral.
        /// - adding synthetic shares is part of the deposit flow.
        /// - Updates position diffs.
        ///
        /// Returns:
        /// - The amount of vault shares received from the deposit.
        fn _execute_deposit_into_vault(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            vault_position_id: PositionId,
            collateral_quantized_amount: u64,
            vault_address: ContractAddress,
            vault_share_quantum: u64,
        ) -> u256 {
            // Deposit into vault.
            let actual_unquantized_vault_shares_amount = self
                ._deposit_to_vault_contract(:vault_address, :collateral_quantized_amount);

            // Build position diffs.
            let position_diff = PositionDiff {
                collateral_diff: -collateral_quantized_amount.into(), asset_diff: Option::None,
            };
            let vault_diff = PositionDiff {
                collateral_diff: collateral_quantized_amount.into(), asset_diff: Option::None,
            };

            /// Validations - Fundamentals:
            let mut positions = get_dep_component_mut!(ref self, Positions);
            let position = positions.get_position_snapshot(:position_id);
            positions
                .validate_healthy_or_healthier_position(
                    :position_id, :position, :position_diff, tvtr_before: Default::default(),
                );

            // Apply diffs.
            positions.apply_diff(:position_id, :position_diff);
            positions.apply_diff(position_id: vault_position_id, position_diff: vault_diff);

            actual_unquantized_vault_shares_amount
        }

        fn _deposit_to_vault_contract(
            ref self: ComponentState<TContractState>,
            vault_address: ContractAddress,
            collateral_quantized_amount: u64,
        ) -> u256 {
            let contract_address = get_contract_address();
            let erc20_collateral_dispatcher = get_dep_component!(@self, Assets)
                .get_collateral_token_contract();
            let collateral_quantum = get_dep_component!(@self, Assets).get_collateral_quantum();
            let erc20_vault_dispatcher = IERC20Dispatcher { contract_address: vault_address };

            // Fetch balances before deposit
            let before_deposit_balance = erc20_collateral_dispatcher
                .balance_of(account: contract_address);
            let before_deposit_shares_balance = erc20_vault_dispatcher
                .balance_of(account: contract_address);

            // Approve and deposit assets into the vault
            let collateral_unquantized_amount: u256 = collateral_quantized_amount.into()
                * collateral_quantum.into();
            erc20_collateral_dispatcher
                .approve(spender: vault_address, amount: collateral_unquantized_amount);
            let vault_shares_amount = IERC4626Dispatcher { contract_address: vault_address }
                .deposit(assets: collateral_unquantized_amount, receiver: contract_address);

            // Fetch balances after deposit
            let after_deposit_balance = erc20_collateral_dispatcher
                .balance_of(account: contract_address);
            let after_deposit_shares_balance = erc20_vault_dispatcher
                .balance_of(account: contract_address);

            // Validate balances to ensure correctness
            assert(after_deposit_balance == before_deposit_balance, COLLATERAL_BALANCE_MISMATCH);
            assert(
                after_deposit_shares_balance == before_deposit_shares_balance + vault_shares_amount,
                SHARES_BALANCE_MISMATCH,
            );

            vault_shares_amount
        }


        /// Validates a vault registration.
        ///
        /// This function ensures the transaction is valid by:
        /// - Checking the vault contract address is not zero.
        /// - Validating the expiration.
        /// - Checking the vault asset id is registered.
        /// - Checking the vault position id is not already registered.
        /// - Checking the vault position is not a vault position.
        /// - Checking the vault position has no share assets.
        /// - Validating the signature.
        fn _validate_register_vault(
            ref self: ComponentState<TContractState>,
            vault_position_id: PositionId,
            vault_contract_address: ContractAddress,
            vault_asset_id: AssetId,
            expiration: Timestamp,
            signature: Signature,
        ) {
            assert(vault_contract_address.is_non_zero(), INVALID_VAULT_CONTRACT_ADDRESS);
            validate_expiration(expiration: expiration, err: SIGNED_TX_EXPIRED);

            // Validate asset id exists, if not found get_asset_config will panic.
            get_dep_component!(@self, Assets).get_asset_config(asset_id: vault_asset_id);

            let vault_address = self.vault_positions_to_addresses.read(vault_position_id);
            assert(vault_address.is_zero(), VAULT_POSITION_ALREADY_EXISTS);
            let vault_position = self.addresses_to_vault_positions.read(vault_contract_address);
            assert(vault_position.is_zero(), VAULT_CONTRACT_ALREADY_EXISTS);

            //Position check
            let mut positions = get_dep_component!(@self, Positions);
            let vault_position = positions.get_position_snapshot(position_id: vault_position_id);

            for (asset_id, asset_balance) in vault_position.assets_balance {
                if get_dep_component!(@self, Assets)
                    .get_asset_type(asset_id) == AssetType::VAULT_SHARE_COLLATERAL {
                    assert(asset_balance.is_zero(), VAULT_POSITION_HAS_SHARES);
                }
            }

            validate_signature(
                public_key: vault_position.get_owner_public_key(),
                message: RegisterVaultArgs {
                    vault_position_id, vault_contract_address, vault_asset_id, expiration,
                },
                :signature,
            );
        }

        fn _validate_redeem_from_vault(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            user_signature: Signature,
            vault_position_id: PositionId,
            vault_owner_signature: Signature,
            number_of_shares: u64,
            minimum_received_total_amount: u64,
            vault_share_execution_price: Price,
            expiration: Timestamp,
            salt: felt252,
            vault_share_asset_id: AssetId,
        ) -> (StoragePath<Position>, StoragePath<Position>) {
            validate_expiration(expiration: expiration, err: SIGNED_TX_EXPIRED);
            let mut positions = get_dep_component!(@self, Positions);

            assert(number_of_shares.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(minimum_received_total_amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(vault_share_execution_price.is_non_zero(), INVALID_ZERO_AMOUNT);

            let number_of_shares_as_balance: Balance = number_of_shares.into();
            let actual_received_amount: u64 = vault_share_execution_price
                .mul(rhs: number_of_shares_as_balance)
                .abs()
                .try_into()
                .expect(AMOUNT_OVERFLOW);

            assert(
                minimum_received_total_amount <= actual_received_amount, RECEIVED_AMOUNT_TOO_SMALL,
            );

            // Vault position id is a vault position, and the asset is active.
            let vault_position = positions.get_position_snapshot(position_id: vault_position_id);
            get_dep_component!(@self, Assets).validate_active_asset(asset_id: vault_share_asset_id);

            // position id is exists and it is not a vault position.
            let position = positions.get_position_snapshot(:position_id);
            // Make sure the withdrawing position is not a vault position
            // by asserting that position id is not in the vault map.
            assert(
                self.vault_positions_to_addresses.read(position_id).is_zero(),
                POSITION_IS_VAULT_POSITION,
            );
            // Signature validation
            let redeem_from_vault_user_hash: HashType = validate_signature(
                public_key: position.get_owner_public_key(),
                message: RedeemFromVaultUserArgs {
                    position_id,
                    vault_position_id,
                    number_of_shares,
                    minimum_received_total_amount,
                    expiration,
                    salt,
                },
                signature: user_signature,
            );
            assert(
                !self.fulfilled_vault_requests.read(redeem_from_vault_user_hash),
                VAULT_REQUEST_ALREADY_FULFILLED,
            );
            self.fulfilled_vault_requests.write(redeem_from_vault_user_hash, true);

            validate_signature(
                public_key: vault_position.get_owner_public_key(),
                message: RedeemFromVaultOwnerArgs {
                    redeem_from_vault_user_hash, vault_share_execution_price,
                },
                signature: vault_owner_signature,
            );

            (vault_position, position)
        }

        fn _execute_redeem_from_vault(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            vault_position_id: PositionId,
            number_of_shares: u64,
            vault_share_execution_price: Price,
            vault_share_asset_id: AssetId,
            vault_position: StoragePath<Position>,
            position: StoragePath<Position>,
        ) -> u64 {
            // Withdraw from vault.
            let actual_collateral_quantized_amount = self
                ._redeem_from_vault_contract(
                    :vault_share_asset_id, :number_of_shares, :vault_share_execution_price,
                );

            // Build position diffs.
            let position_diff = PositionDiff {
                collateral_diff: actual_collateral_quantized_amount.into(),
                asset_diff: Option::Some((vault_share_asset_id, -number_of_shares.into())),
            };
            let vault_diff = PositionDiff {
                collateral_diff: -actual_collateral_quantized_amount.into(),
                asset_diff: Option::None,
            };
            let mut positions = get_dep_component_mut!(ref self, Positions);
            positions
                .validate_healthy_or_healthier_position(
                    :position_id, :position, :position_diff, tvtr_before: Default::default(),
                );

            // Apply diffs.
            positions.apply_diff(:position_id, :position_diff);
            positions.apply_diff(position_id: vault_position_id, position_diff: vault_diff);

            actual_collateral_quantized_amount
        }

        fn _redeem_from_vault_contract(
            ref self: ComponentState<TContractState>,
            vault_share_asset_id: AssetId,
            number_of_shares: u64,
            vault_share_execution_price: Price,
        ) -> u64 {
            let perps_address = get_contract_address();
            let collateral_dispatcher = get_dep_component!(@self, Assets)
                .get_collateral_token_contract();
            let collateral_quantum = get_dep_component!(@self, Assets).get_collateral_quantum();

            let (asset_type, erc20_vault_dispatcher, vault_share_quantum) = get_dep_component!(
                @self, Assets,
            )
                .get_token_contract_and_quantum(asset_id: vault_share_asset_id);
            assert(asset_type == AssetType::VAULT_SHARE_COLLATERAL, NOT_VAULT_SHARE_ASSET);

            let vault_address = erc20_vault_dispatcher.contract_address;

            // Fetch balances before withdraw
            let before_withdraw_collateral_balance = collateral_dispatcher
                .balance_of(account: perps_address);
            let before_withdraw_vault_shares_balance = erc20_vault_dispatcher
                .balance_of(account: perps_address);

            let number_of_shares_as_balance: Balance = number_of_shares.into();
            let expected_quantized_collateral_amount = vault_share_execution_price
                .mul(number_of_shares_as_balance);
            let expected_unquantized_collateral_amount = expected_quantized_collateral_amount
                .abs()
                .into()
                * collateral_quantum.into();
            collateral_dispatcher
                .approve(spender: vault_address, amount: expected_unquantized_collateral_amount);

            let expected_unquantized_vault_shares_amount = number_of_shares.into()
                * vault_share_quantum.into();
            erc20_vault_dispatcher
                .approve(spender: vault_address, amount: expected_unquantized_vault_shares_amount);
            let value_of_shares_in_assets = IProtocolVaultDispatcher {
                contract_address: vault_address,
            }
                .redeem_with_price(
                    shares: expected_unquantized_vault_shares_amount,
                    value_of_shares_in_assets: expected_unquantized_collateral_amount,
                );

            assert(
                value_of_shares_in_assets == expected_unquantized_collateral_amount,
                SHARES_BALANCE_MISMATCH,
            );

            // Fetch balances after withdraw
            let after_withdraw_vault_shares_balance = erc20_vault_dispatcher
                .balance_of(account: perps_address);
            let after_withdraw_collateral_balance = collateral_dispatcher
                .balance_of(account: perps_address);

            // Validate balances to ensure correctness
            assert(
                after_withdraw_collateral_balance == before_withdraw_collateral_balance,
                COLLATERAL_BALANCE_MISMATCH,
            );
            assert(
                after_withdraw_vault_shares_balance == before_withdraw_vault_shares_balance
                    - expected_unquantized_vault_shares_amount,
                SHARES_BALANCE_MISMATCH,
            );

            (value_of_shares_in_assets / collateral_quantum.into())
                .try_into()
                .expect(AMOUNT_OVERFLOW)
        }

        fn _is_vault_position(
            ref self: ComponentState<TContractState>, position_id: PositionId,
        ) -> bool {
            let position_address = self.vault_positions_to_addresses.read(position_id);
            position_address.is_non_zero()
        }
    }
}
