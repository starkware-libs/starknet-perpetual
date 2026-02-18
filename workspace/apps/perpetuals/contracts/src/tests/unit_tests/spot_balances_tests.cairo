//! Tests for `Position.spot_balances: LinkedIterableMapFelt<AssetId, SpotBalance>`.
//! Covers read, write (via apply_diff), and iteration behavior.

use core::num::traits::Zero;
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::AssetType;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::position::{PositionDiff, PositionId};
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, UserTrait, init_position, init_position_with_spot_asset_balance,
    setup_state_with_pending_spot_asset, validate_asset_balance,
};
use snforge_std::test_address;
use starkware_utils::constants::MAX_U128;
use starkware_utils::storage::linked_iterable_map_felt::LinkedIterableMapFeltReadAccess;
use starkware_utils_testing::test_utils::{Deployable, cheat_caller_address_once};
use crate::core::components::assets::interface::IAssetsManager;
use crate::core::components::operator_nonce::interface::IOperatorNonce;
use crate::core::components::positions::interface::IPositions;
use crate::core::core::Core;

// --- Read tests ---------------------------------------------------------------------------------

#[test]
fn test_spot_balances_read_after_deposit() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(cfg: @cfg, token_state: @token_state);

    let user: User = Default::default();
    let spot_asset_id: AssetId = cfg.spot_cfg.collateral_id;
    let spot_asset_balance: Balance = 1000_i64.into();

    init_position_with_spot_asset_balance(
        cfg: @cfg, ref :state, :user, :spot_asset_id, :spot_asset_balance,
    );

    validate_asset_balance(
        ref :state,
        position_id: user.position_id,
        asset_id: spot_asset_id,
        expected_balance: spot_asset_balance,
    );
}

#[test]
fn test_spot_balances_read_missing_key_returns_zero() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(cfg: @cfg, token_state: @token_state);

    let user: User = Default::default();
    let spot_asset_id_a: AssetId = cfg.spot_cfg.collateral_id;
    let spot_asset_balance: Balance = 500_i64.into();
    init_position_with_spot_asset_balance(
        cfg: @cfg, ref :state, :user, spot_asset_id: spot_asset_id_a, :spot_asset_balance,
    );

    // Add a second spot asset (never deposited to this position).
    let spot_asset_id_b = SYNTHETIC_ASSET_ID_2();
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_spot_asset(
            asset_id: spot_asset_id_b,
            erc20_contract_address: token_state.address,
            quantum: 1,
            resolution_factor: SYNTHETIC_RESOLUTION_FACTOR,
            risk_factor_tiers: array![10].span(),
            risk_factor_first_tier_boundary: MAX_U128,
            risk_factor_tier_size: MAX_U128,
            quorum: 1,
        );

    let snapshot = state.positions.get_position_snapshot(position_id: user.position_id);
    let read_balance_b = snapshot.spot_balances.read(key: spot_asset_id_b).balance;
    assert!(read_balance_b == Zero::zero());
}

// --- Write test ----------------------------------------------------------------------------------

#[test]
fn test_spot_balances_write_then_read() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(cfg: @cfg, token_state: @token_state);

    let user: User = Default::default();
    let spot_asset_id: AssetId = cfg.spot_cfg.collateral_id;
    let first_balance: Balance = 300_i64.into();
    let second_balance: Balance = 700_i64.into();

    init_position_with_spot_asset_balance(
        cfg: @cfg, ref :state, :user, :spot_asset_id, spot_asset_balance: first_balance,
    );

    let position_diff = PositionDiff {
        collateral_diff: Zero::zero(), asset_diff: Option::Some((spot_asset_id, second_balance)),
    };
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state.positions.apply_diff(position_id: user.position_id, position_diff: position_diff);

    let expected_total: Balance = 1000_i64.into();
    validate_asset_balance(
        ref :state,
        position_id: user.position_id,
        asset_id: spot_asset_id,
        expected_balance: expected_total,
    );
}

// --- Iteration tests -----------------------------------------------------------------------------

fn count_spot_assets_in_position_data(state: @Core::ContractState, position_id: PositionId) -> u32 {
    let position_data = state.get_position_assets(position_id);
    let mut count: u32 = 0;
    let assets = position_data.assets;
    let len = assets.len();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        if (*assets.at(i)).asset_type == AssetType::SPOT_COLLATERAL {
            count += 1;
        }
        i += 1;
    }
    count
}

#[test]
fn test_spot_balances_iteration_empty() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(cfg: @cfg, token_state: @token_state);

    let user: User = Default::default();
    init_position(cfg: @cfg, ref :state, :user);

    let spot_count = count_spot_assets_in_position_data(@state, user.position_id);
    assert!(spot_count == 0);
}

#[test]
fn test_spot_balances_iteration_single_entry() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(cfg: @cfg, token_state: @token_state);

    let user: User = Default::default();
    let spot_asset_id: AssetId = cfg.spot_cfg.collateral_id;
    let spot_asset_balance: Balance = 2000_i64.into();
    init_position_with_spot_asset_balance(
        cfg: @cfg, ref :state, :user, :spot_asset_id, :spot_asset_balance,
    );

    let spot_count = count_spot_assets_in_position_data(@state, user.position_id);
    assert!(spot_count == 1);
    validate_asset_balance(
        ref :state,
        position_id: user.position_id,
        asset_id: spot_asset_id,
        expected_balance: spot_asset_balance,
    );
}

#[test]
fn test_spot_balances_iteration_multiple_entries() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(cfg: @cfg, token_state: @token_state);

    let spot_asset_id_1: AssetId = cfg.spot_cfg.collateral_id;
    let spot_asset_id_2 = SYNTHETIC_ASSET_ID_2();
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_spot_asset(
            asset_id: spot_asset_id_2,
            erc20_contract_address: token_state.address,
            quantum: 1,
            resolution_factor: SYNTHETIC_RESOLUTION_FACTOR,
            risk_factor_tiers: array![10].span(),
            risk_factor_first_tier_boundary: MAX_U128,
            risk_factor_tier_size: MAX_U128,
            quorum: 1,
        );

    let user: User = Default::default();
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .new_position(
            operator_nonce: state.get_operator_nonce(),
            position_id: user.position_id,
            owner_public_key: user.get_public_key(),
            owner_account: Zero::zero(),
            owner_protection_enabled: false,
        );

    let amount_1: Balance = 1000_i64.into();
    let amount_2: Balance = 2000_i64.into();
    state
        .positions
        .apply_diff(
            position_id: user.position_id,
            position_diff: PositionDiff {
                collateral_diff: Zero::zero(),
                asset_diff: Option::Some((spot_asset_id_1, amount_1)),
            },
        );
    state
        .positions
        .apply_diff(
            position_id: user.position_id,
            position_diff: PositionDiff {
                collateral_diff: Zero::zero(),
                asset_diff: Option::Some((spot_asset_id_2, amount_2)),
            },
        );

    let spot_count = count_spot_assets_in_position_data(@state, user.position_id);
    assert!(spot_count == 2);
    validate_asset_balance(
        ref :state,
        position_id: user.position_id,
        asset_id: spot_asset_id_1,
        expected_balance: amount_1,
    );
    validate_asset_balance(
        ref :state,
        position_id: user.position_id,
        asset_id: spot_asset_id_2,
        expected_balance: amount_2,
    );
}
