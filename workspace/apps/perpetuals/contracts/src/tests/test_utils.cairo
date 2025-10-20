use core::hash::{HashStateExTrait, HashStateTrait};
use core::num::traits::Zero;
use core::poseidon::PoseidonTrait;
use openzeppelin::presets::interfaces::{
    AccountUpgradeableABIDispatcher, AccountUpgradeableABIDispatcherTrait,
};
use perpetuals::core::components::assets::interface::IAssets;
use perpetuals::core::components::operator_nonce::interface::IOperatorNonce;
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::components::positions::interface::IPositions;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::{InternalCoreFunctions, SNIP12MetadataImpl};
use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::position::{PositionDiff, PositionId};
use perpetuals::core::types::price::{Price, SignedPrice};
use perpetuals::core::types::risk_factor::{RiskFactor, RiskFactorTrait};
use perpetuals::tests::constants::*;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, start_cheat_block_timestamp_global, test_address,
};
use starknet::ContractAddress;
use starknet::storage::StoragePointerWriteAccess;
use starkware_utils::components::roles::interface::{
    IRoles, IRolesDispatcher, IRolesDispatcherTrait,
};
use starkware_utils::constants::{MAX_U128, TWO_POW_32, TWO_POW_40};
use starkware_utils::signature::stark::Signature;
use starkware_utils::storage::iterable_map::*;
use starkware_utils::time::time::{Time, TimeDelta, Timestamp};
use starkware_utils_testing::signing::StarkKeyPair;
use starkware_utils_testing::test_utils::{
    Deployable, TokenConfig, TokenState, TokenTrait, cheat_caller_address_once,
};

/// The `User` struct represents a user corresponding to a position in the state of the Core
/// contract.
#[derive(Drop, Copy)]
pub struct User {
    pub position_id: PositionId,
    pub address: ContractAddress,
    key_pair: StarkKeyPair,
    pub salt_counter: felt252,
}

pub fn get_accept_ownership_signature(
    account_address: ContractAddress, current_public_key: felt252, new_key_pair: StarkKeyPair,
) -> Signature {
    let msg_hash = PoseidonTrait::new()
        .update_with('StarkNet Message')
        .update_with('accept_ownership')
        .update_with(account_address)
        .update_with(current_public_key)
        .finalize();
    let (sig_r, sig_s) = new_key_pair.sign(msg_hash).unwrap();
    array![sig_r, sig_s].span()
}

#[generate_trait]
pub impl UserImpl of UserTrait {
    fn sign_message(self: User, message: felt252) -> Signature {
        let (r, s) = self.key_pair.sign(message).unwrap();
        array![r, s].span()
    }
    fn set_public_key(ref self: User, new_key_pair: StarkKeyPair) {
        let signature = get_accept_ownership_signature(
            self.address, self.key_pair.public_key, new_key_pair,
        );
        let dispatcher = AccountUpgradeableABIDispatcher { contract_address: self.address };
        cheat_caller_address_once(contract_address: self.address, caller_address: self.address);
        dispatcher.set_public_key(new_public_key: new_key_pair.public_key, :signature);
        self.key_pair = new_key_pair;
    }
    fn get_public_key(self: @User) -> felt252 {
        *self.key_pair.public_key
    }
    fn new(position_id: PositionId, key_pair: StarkKeyPair) -> User {
        User {
            position_id, address: deploy_account(:key_pair), key_pair, salt_counter: Zero::zero(),
        }
    }
}
impl UserDefault of Default<User> {
    fn default() -> User {
        UserTrait::new(position_id: POSITION_ID_100, key_pair: KEY_PAIR_1())
    }
}

/// The `Oracle` struct represents an oracle providing information about prices.
#[derive(Drop, Copy)]
pub struct Oracle {
    pub oracle_name: felt252,
    pub asset_name: felt252,
    pub key_pair: StarkKeyPair,
}

#[generate_trait]
pub impl OracleImpl of OracleTrait {
    fn get_oracle_name_asset_name_concat(self: @Oracle) -> felt252 {
        *self.asset_name * TWO_POW_40.into() + *self.oracle_name
    }
    fn get_signed_price(self: Oracle, oracle_price: u128, timestamp: u32) -> SignedPrice {
        let message = core::pedersen::pedersen(
            self.get_oracle_name_asset_name_concat(),
            (oracle_price * TWO_POW_32.try_into().unwrap() + timestamp.into()).into(),
        );
        let (r, s) = self.key_pair.sign(message).unwrap();
        SignedPrice {
            signature: [r, s].span(),
            signer_public_key: self.key_pair.public_key,
            timestamp,
            oracle_price,
        }
    }
}

#[derive(Drop)]
pub struct PerpetualsInitConfig {
    pub governance_admin: ContractAddress,
    pub upgrade_delay: u64,
    pub app_role_admin: ContractAddress,
    pub app_governor: ContractAddress,
    pub operator: ContractAddress,
    pub max_funding_interval: TimeDelta,
    pub max_price_interval: TimeDelta,
    pub max_funding_rate: u32,
    pub max_oracle_price_validity: TimeDelta,
    pub cancel_delay: TimeDelta,
    pub fee_position_owner_account: ContractAddress,
    pub fee_position_owner_public_key: felt252,
    pub insurance_fund_position_owner_account: ContractAddress,
    pub insurance_fund_position_owner_public_key: felt252,
    pub collateral_cfg: CollateralCfg,
    pub synthetic_cfg: SyntheticCfg,
}

#[generate_trait]
pub impl CoreImpl of CoreTrait {
    fn deploy(self: @PerpetualsInitConfig, token_state: @TokenState) -> ContractAddress {
        let mut calldata = ArrayTrait::new();
        self.governance_admin.serialize(ref calldata);
        self.upgrade_delay.serialize(ref calldata);
        self.collateral_cfg.collateral_id.serialize(ref calldata);
        (*token_state).address.serialize(ref calldata);
        self.collateral_cfg.quantum.serialize(ref calldata);
        self.max_price_interval.serialize(ref calldata);
        self.max_oracle_price_validity.serialize(ref calldata);
        self.max_funding_interval.serialize(ref calldata);
        self.max_funding_rate.serialize(ref calldata);
        self.cancel_delay.serialize(ref calldata);
        self.fee_position_owner_public_key.serialize(ref calldata);
        self.insurance_fund_position_owner_public_key.serialize(ref calldata);

        let core_contract = snforge_std::declare("Core").unwrap().contract_class();
        let (core_contract_address, _) = core_contract.deploy(@calldata).unwrap();
        core_contract_address
    }
}

impl PerpetualsInitConfigDefault of Default<PerpetualsInitConfig> {
    fn default() -> PerpetualsInitConfig {
        PerpetualsInitConfig {
            governance_admin: GOVERNANCE_ADMIN(),
            upgrade_delay: UPGRADE_DELAY,
            app_role_admin: APP_ROLE_ADMIN(),
            app_governor: APP_GOVERNOR(),
            operator: OPERATOR(),
            max_funding_interval: MAX_FUNDING_INTERVAL,
            max_price_interval: MAX_PRICE_INTERVAL,
            max_funding_rate: MAX_FUNDING_RATE,
            max_oracle_price_validity: MAX_ORACLE_PRICE_VALIDITY,
            cancel_delay: Time::weeks(1),
            fee_position_owner_account: OPERATOR(),
            fee_position_owner_public_key: OPERATOR_PUBLIC_KEY(),
            insurance_fund_position_owner_account: OPERATOR(),
            insurance_fund_position_owner_public_key: OPERATOR_PUBLIC_KEY(),
            collateral_cfg: CollateralCfg {
                token_cfg: TokenConfig {
                    name: COLLATERAL_NAME(),
                    symbol: COLLATERAL_SYMBOL(),
                    initial_supply: INITIAL_SUPPLY,
                    owner: COLLATERAL_OWNER(),
                },
                collateral_id: COLLATERAL_ASSET_ID(),
                quantum: COLLATERAL_QUANTUM,
                risk_factor: Zero::zero(),
                quorum: COLLATERAL_QUORUM,
            },
            synthetic_cfg: SyntheticCfg { synthetic_id: SYNTHETIC_ASSET_ID_1() },
        }
    }
}

/// The 'CollateralCfg' struct represents a deployed collateral with an associated asset id.
#[derive(Drop)]
pub struct CollateralCfg {
    pub token_cfg: TokenConfig,
    pub collateral_id: AssetId,
    pub quantum: u64,
    pub risk_factor: RiskFactor,
    pub quorum: u8,
}

/// The 'SyntheticCfg' struct represents a synthetic asset config with an associated asset id.
#[derive(Drop)]
pub struct SyntheticCfg {
    pub synthetic_id: AssetId,
}

// Internal functions.

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

fn deploy_account(key_pair: StarkKeyPair) -> ContractAddress {
    let calldata = array![key_pair.public_key];

    let contract_class = snforge_std::declare("AccountUpgradeable").unwrap().contract_class();
    let (account_address, _) = contract_class.deploy(@calldata).unwrap();

    account_address
}

// Public functions.

pub fn set_roles(ref state: Core::ContractState, cfg: @PerpetualsInitConfig) {
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.governance_admin,
    );
    state.register_app_role_admin(account: *cfg.app_role_admin);
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.app_role_admin,
    );
    state.register_app_governor(account: *cfg.app_governor);
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.app_role_admin,
    );
    state.register_operator(account: *cfg.operator);
}

pub fn setup_state_with_active_asset(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> Core::ContractState {
    let mut state = setup_state_with_pending_asset(:cfg, :token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    cheat_caller_address_once(contract_address: test_address(), caller_address: *cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: *cfg.synthetic_cfg.synthetic_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: *cfg.operator);
    let oracle_price = ORACLE_PRICE;
    let operator_nonce = state.get_operator_nonce();
    let timestamp: u64 = Time::now().into();
    state
        .price_tick(
            :operator_nonce,
            asset_id: *cfg.synthetic_cfg.synthetic_id,
            :oracle_price,
            signed_prices: [
                oracle1.get_signed_price(:oracle_price, timestamp: timestamp.try_into().unwrap())
            ]
                .span(),
        );
    state
}

pub fn setup_state_with_pending_asset(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> Core::ContractState {
    let mut state = init_state(:cfg, :token_state);
    // Synthetic asset configs.
    state
        .assets
        .add_synthetic_asset(
            asset_id: *cfg.synthetic_cfg.synthetic_id,
            risk_factor_tiers: array![RISK_FACTOR].span(),
            risk_factor_first_tier_boundary: MAX_U128,
            risk_factor_tier_size: MAX_U128,
            quorum: SYNTHETIC_QUORUM,
            resolution_factor: SYNTHETIC_RESOLUTION_FACTOR,
        );
    state
}

pub fn init_state(cfg: @PerpetualsInitConfig, token_state: @TokenState) -> Core::ContractState {
    start_cheat_block_timestamp_global(
        block_timestamp: Time::now().add(delta: Time::weeks(count: 1)).into(),
    );
    let mut state = initialized_contract_state(:cfg, :token_state);
    set_roles(ref :state, :cfg);
    cheat_caller_address_once(contract_address: test_address(), caller_address: *cfg.app_governor);
    // Fund the contract.
    (*token_state)
        .fund(recipient: test_address(), amount: CONTRACT_INIT_BALANCE.try_into().unwrap());

    state
}

pub fn create_token_state() -> TokenState {
    let token_config = TokenConfig {
        name: COLLATERAL_NAME(),
        symbol: COLLATERAL_SYMBOL(),
        initial_supply: INITIAL_SUPPLY,
        owner: COLLATERAL_OWNER(),
    };
    Deployable::deploy(@token_config)
}

pub fn init_position(cfg: @PerpetualsInitConfig, ref state: Core::ContractState, user: User) {
    cheat_caller_address_once(contract_address: test_address(), caller_address: *cfg.operator);
    let position_id = user.position_id;
    state
        .new_position(
            operator_nonce: state.get_operator_nonce(),
            :position_id,
            owner_public_key: user.get_public_key(),
            owner_account: Zero::zero(),
        );
    let position_diff = PositionDiff {
        collateral_diff: COLLATERAL_BALANCE_AMOUNT.into(), asset_diff: Option::None,
    };

    state.positions.apply_diff(:position_id, :position_diff);
}

pub fn init_position_with_owner(
    cfg: @PerpetualsInitConfig, ref state: Core::ContractState, user: User,
) {
    init_position(cfg, ref :state, :user);
    let position = state.positions.get_position_mut(position_id: user.position_id);
    position.owner_account.write(Option::Some(user.address));
}

pub fn add_synthetic_to_position(
    ref state: Core::ContractState, synthetic_id: AssetId, position_id: PositionId, balance: i64,
) {
    let position_diff = PositionDiff {
        collateral_diff: Default::default(),
        asset_diff: Option::Some((synthetic_id, balance.into())),
    };
    state.positions.apply_diff(:position_id, :position_diff);
}

pub fn initialized_contract_state(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> Core::ContractState {
    let mut state = CONTRACT_STATE();
    Core::constructor(
        ref state,
        governance_admin: GOVERNANCE_ADMIN(),
        upgrade_delay: UPGRADE_DELAY,
        collateral_id: *cfg.collateral_cfg.collateral_id,
        collateral_token_address: *token_state.address,
        collateral_quantum: *cfg.collateral_cfg.quantum,
        max_price_interval: MAX_PRICE_INTERVAL,
        max_oracle_price_validity: MAX_ORACLE_PRICE_VALIDITY,
        max_funding_interval: MAX_FUNDING_INTERVAL,
        max_funding_rate: MAX_FUNDING_RATE,
        cancel_delay: CANCEL_DELAY,
        fee_position_owner_public_key: OPERATOR_PUBLIC_KEY(),
        insurance_fund_position_owner_public_key: OPERATOR_PUBLIC_KEY(),
    );
    state
}

pub fn check_asset_config(
    state: @Core::ContractState,
    synthetic_id: AssetId,
    status: AssetStatus,
    risk_factor_tiers: Span<u16>,
    risk_factor_first_tier_boundary: u128,
    risk_factor_tier_size: u128,
    quorum: u8,
    resolution_factor: u64,
) {
    let asset_config = state.assets.get_asset_config(synthetic_id);
    assert!(asset_config.status == status);
    let tiers = state.assets.get_risk_factor_tiers(asset_id: synthetic_id);
    for i in 0..risk_factor_tiers.len() {
        assert!(*tiers[i] == RiskFactorTrait::new(*risk_factor_tiers[i]));
    }
    assert!(asset_config.risk_factor_first_tier_boundary == risk_factor_first_tier_boundary);
    assert!(asset_config.risk_factor_tier_size == risk_factor_tier_size);
    assert!(asset_config.quorum == quorum);
    assert!(asset_config.resolution_factor == resolution_factor);
}

pub fn check_asset_timely_data(
    state: @Core::ContractState,
    synthetic_id: AssetId,
    price: Price,
    last_price_update: Timestamp,
    funding_index: FundingIndex,
) {
    let asset_timely_data = state.assets.get_asset_timely_data(synthetic_id);
    assert!(asset_timely_data.price == price);
    assert!(asset_timely_data.last_price_update == last_price_update);
    assert!(asset_timely_data.funding_index == funding_index);
}

pub fn is_asset_in_asset_timely_data_list(
    state: @Core::ContractState, synthetic_id: AssetId,
) -> bool {
    let mut flag = false;

    for (asset_id, _) in state.assets.asset_timely_data {
        if asset_id == synthetic_id {
            flag = true;
            break;
        }
    }
    flag
}

pub fn check_synthetic_asset(
    state: @Core::ContractState,
    synthetic_id: AssetId,
    status: AssetStatus,
    risk_factor_tiers: Span<u16>,
    risk_factor_first_tier_boundary: u128,
    risk_factor_tier_size: u128,
    quorum: u8,
    resolution_factor: u64,
    price: Price,
    last_price_update: Timestamp,
    funding_index: FundingIndex,
) {
    check_asset_config(
        :state,
        :synthetic_id,
        status: status,
        :risk_factor_tiers,
        :risk_factor_first_tier_boundary,
        :risk_factor_tier_size,
        :quorum,
        :resolution_factor,
    );
    check_asset_timely_data(
        :state,
        :synthetic_id,
        price: Zero::zero(),
        last_price_update: Zero::zero(),
        funding_index: Zero::zero(),
    );
    // Check the asset_timely_data list.
    assert!(is_asset_in_asset_timely_data_list(:state, :synthetic_id));
}

pub fn validate_balance(token_state: TokenState, address: ContractAddress, expected_balance: u128) {
    let balance_to_check = token_state.balance_of(address);
    assert_eq!(balance_to_check, expected_balance);
}

// Utils for dispatcher usage.

pub fn set_roles_by_dispatcher(contract_address: ContractAddress, cfg: @PerpetualsInitConfig) {
    let dispatcher = IRolesDispatcher { contract_address };
    cheat_caller_address_once(:contract_address, caller_address: *cfg.governance_admin);
    dispatcher.register_app_role_admin(account: *cfg.app_role_admin);
    cheat_caller_address_once(:contract_address, caller_address: *cfg.app_role_admin);
    dispatcher.register_app_governor(account: *cfg.app_governor);
    cheat_caller_address_once(:contract_address, caller_address: *cfg.app_role_admin);
    dispatcher.register_operator(account: *cfg.operator);
}

pub fn init_by_dispatcher(cfg: @PerpetualsInitConfig, token_state: @TokenState) -> ContractAddress {
    let contract_address = cfg.deploy(:token_state);
    set_roles_by_dispatcher(:contract_address, :cfg);
    contract_address
}

