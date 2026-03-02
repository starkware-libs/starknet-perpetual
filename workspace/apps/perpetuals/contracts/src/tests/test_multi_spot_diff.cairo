use core::traits::{Default, Into};
use perpetuals::core::components::assets::assets::AssetsComponent::InternalTrait as AssetsInternal;
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::components::positions::interface::IPositions;
use perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::position::MultiSpotPositionDiff;
use perpetuals::core::types::price::PriceMulTrait;
use perpetuals::core::types::risk_factor::{RiskFactorMulTrait, RiskFactorTrait};
use perpetuals::core::value_risk_calculator::TVTRChange;
use perpetuals::tests::constants::*;
use starknet::storage::StoragePointerReadAccess;
use starkware_utils::math::abs::Abs;
use crate::tests::test_utils::{
    PerpetualsInitConfig, User, create_token_state, init_position, send_price_tick_for_spot,
    send_price_tick_for_vault_share, setup_state_with_active_synthetic,
    setup_state_with_multiple_spot_assets, setup_state_with_pending_spot_asset,
    validate_asset_balance,
};

#[test]
fn test_apply_multi_spot_diff_happy_path() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_pending_spot_asset(@cfg, @token_state);

    // Create a user and a position
    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let collateral_diff_val: i64 = 1000;
    let collateral_diff: Balance = collateral_diff_val.into();

    // cfg is owned, so these access the values directly
    let spot_asset_id = cfg.spot_cfg.collateral_id;
    let spot_asset_diff_val: i64 = 500;
    let spot_asset_diff: Balance = spot_asset_diff_val.into();

    let multi_spot_diff = MultiSpotPositionDiff {
        collateral_diff: collateral_diff,
        asset_diffs: array![
            SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: spot_asset_diff_val },
        ]
            .span(),
    };

    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff);

    // Verify balances (collateral balance read directly as it's simple storage)
    let position = state.positions.get_position_snapshot(position_id);

    let expected_collateral = COLLATERAL_BALANCE_AMOUNT + 1000;
    assert(
        position.collateral_balance.read() == expected_collateral.into(),
        'Invalid collateral balance',
    );

    // Spot balance check using helper
    validate_asset_balance(ref state, position_id, spot_asset_id, spot_asset_diff);

    // Apply another diff (adding more)
    let spot_diff_2: i64 = 200;
    let col_diff_2: i64 = 100;

    let multi_spot_diff_2 = MultiSpotPositionDiff {
        collateral_diff: col_diff_2.into(),
        asset_diffs: array![SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: spot_diff_2 }]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff_2);

    let position_2 = state.positions.get_position_snapshot(position_id);
    assert(
        position_2.collateral_balance.read() == (expected_collateral + 100).into(),
        'Invalid col bal 2',
    );

    let expected_spot_2: i64 = 700;
    validate_asset_balance(ref state, position_id, spot_asset_id, expected_spot_2.into());

    // Apply negative diff (partial withdrawal)
    let spot_diff_3: i64 = -100;
    let col_diff_3: i64 = -50;

    let multi_spot_diff_3 = MultiSpotPositionDiff {
        collateral_diff: col_diff_3.into(),
        asset_diffs: array![SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: spot_diff_3 }]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff_3);

    let position_3 = state.positions.get_position_snapshot(position_id);
    assert(
        position_3.collateral_balance.read() == (expected_collateral + 100 - 50).into(),
        'Invalid col bal 3',
    );

    let expected_spot_3: i64 = 600;
    validate_asset_balance(ref state, position_id, spot_asset_id, expected_spot_3.into());
}

#[test]
#[should_panic(
    expected: "Spot Balance for asset: AssetId { value: 115908168817373063099305344695947534019542757008820723413990772101903177083 } has gone negative. now: Balance { value: -1 }, was: Balance { value: 0 }, position: PositionId { value: 100 }",
)]
fn test_apply_multi_spot_diff_negative_balance_panic() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_pending_spot_asset(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let spot_asset_id = cfg.spot_cfg.collateral_id;

    // Try to withdraw more than we have (0 initially)
    let neg_one: i64 = -1;
    let multi_spot_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(),
        asset_diffs: array![SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: neg_one }].span(),
    };

    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff);
}

#[test]
#[should_panic(
    expected: "Asset: AssetId { value: 720515315941943725751128480342703114962297896757142150278960020243082094068 } is not a spot asset",
)]
fn test_apply_multi_spot_diff_synthetic_panic() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    // Setup with synthetic asset
    let mut state = setup_state_with_active_synthetic(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    let multi_spot_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(),
        asset_diffs: array![SpotAssetBalanceDiff { asset_id: synthetic_id, diff: 100 }].span(),
    };

    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff);
}

#[test]
fn test_apply_multi_spot_diff_multiple_assets_mixed() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_multiple_spot_assets(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let spot_asset_id = cfg.spot_cfg.collateral_id;
    let vault_share_id = cfg.vault_share_cfg.collateral_id;

    // Initial funding for both assets
    let initial_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(),
        asset_diffs: array![
            SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: 1000 },
            SpotAssetBalanceDiff { asset_id: vault_share_id, diff: 1000 },
        ]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, initial_diff);

    // Apply mixed diffs across both assets
    let mixed_diffs = MultiSpotPositionDiff {
        collateral_diff: 100_i64.into(),
        asset_diffs: array![
            SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: 500 }, // 1000 + 500 = 1500
            SpotAssetBalanceDiff { asset_id: vault_share_id, diff: -300 } // 1000 - 300 = 700
        ]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, mixed_diffs);

    validate_asset_balance(ref state, position_id, spot_asset_id, 1500_i64.into());
    validate_asset_balance(ref state, position_id, vault_share_id, 700_i64.into());
}

#[test]
fn test_apply_multi_spot_diff_tvtr_tracking() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_multiple_spot_assets(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let spot_asset_id = cfg.spot_cfg.collateral_id;
    let vault_share_id = cfg.vault_share_cfg.collateral_id;

    send_price_tick_for_spot(ref state, @cfg, 12_u64);
    send_price_tick_for_vault_share(ref state, @cfg, 12_u64);

    let spot_asset_price = state.assets.get_asset_price(spot_asset_id);
    let vault_share_price = state.assets.get_asset_price(vault_share_id);

    // Initial TVTR
    let initial_tvtr = state.positions.get_position_tv_tr(position_id);
    assert(initial_tvtr.total_value == COLLATERAL_BALANCE_AMOUNT.into(), 'Initial TV wrong');
    assert(initial_tvtr.total_risk == 0, 'Initial TR wrong');

    // Diffs
    let collateral_diff_val: i64 = 500;
    let spot_diff_val: i64 = 1000;
    let vault_share_diff_val: i64 = 2000;

    let mixed_diffs = MultiSpotPositionDiff {
        collateral_diff: collateral_diff_val.into(),
        asset_diffs: array![
            SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: spot_diff_val },
            SpotAssetBalanceDiff { asset_id: vault_share_id, diff: vault_share_diff_val },
        ]
            .span(),
    };

    // Apply and capture TVTR change
    let tvtr_change: TVTRChange = state.positions.apply_multi_spot_diff(position_id, mixed_diffs);

    // Verify before matches the state prior
    assert(tvtr_change.before.total_value == initial_tvtr.total_value, 'TVTR before val mismatch');
    assert(tvtr_change.before.total_risk == initial_tvtr.total_risk, 'TVTR before risk mismatch');

    // Expected value addition: collateral + (spot_diff * spot_price) + (vault_diff * vault_price)
    // Both spot assets have risk factor 500 (50%) in these setups which means 50% value == 50% risk
    // contribution (since balances > 0)
    let risk_factor = RiskFactorTrait::new(RISK_FACTOR);

    let spot_diff_balance: Balance = spot_diff_val.into();
    let spot_value_added: i128 = spot_asset_price.mul(spot_diff_balance);
    let spot_expected_value = spot_value_added
        - risk_factor.mul(spot_value_added.abs()).try_into().unwrap();

    let vault_share_diff_balance: Balance = vault_share_diff_val.into();
    let vault_share_value_added: i128 = vault_share_price.mul(vault_share_diff_balance);
    let vault_share_expected_value = vault_share_value_added
        - risk_factor.mul(vault_share_value_added.abs()).try_into().unwrap();

    let expected_tv_added: i128 = collateral_diff_val.into()
        + spot_expected_value
        + vault_share_expected_value;

    // Verify after state calculations
    assert(
        tvtr_change.after.total_value == initial_tvtr.total_value + expected_tv_added,
        'TVTR after value mismatch',
    );

    // Now if we do a negative diff, it decreases risk and value correctly
    let next_diffs = MultiSpotPositionDiff {
        collateral_diff: (-100_i64).into(),
        asset_diffs: array![SpotAssetBalanceDiff { asset_id: spot_asset_id, diff: -200 }].span(),
    };

    let next_tvtr_change = state.positions.apply_multi_spot_diff(position_id, next_diffs);
    assert(
        next_tvtr_change.before.total_value == tvtr_change.after.total_value, 'Chain TVTR break',
    );

    let removed_spot_balance: Balance = (-200_i64).into();
    let spot_value_removed: i128 = spot_asset_price.mul(removed_spot_balance);
    let spot_expected_value_removed = spot_value_removed
        + risk_factor.mul(spot_value_removed.abs()).try_into().unwrap();

    let expected_new_tv = next_tvtr_change.before.total_value
        - 100_i128
        + spot_expected_value_removed;
    assert(next_tvtr_change.after.total_value == expected_new_tv, 'Final TVTR decrease mismatch');
}
