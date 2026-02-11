use core::num::traits::Bounded;
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use super::perps_tests_facade::PerpsTestsFacadeTrait;

pub const MAX_U128: u128 = Bounded::<u128>::MAX;

#[test]
#[should_panic(
    expected: "Vault Protection Limit Exceeded, tv_at_last_check: 60000, tv_after_operation: 56999, max_allowed_loss : 3000",
)]
fn test_redeem_exceeding_5_percent_limit_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    // Initial deposit to vault: 50,000 USDC
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 50000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 10000,
                    min_shares_to_receive: 5000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    //trigger loading of TV and setting the limit
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    let shares_to_burn: u64 = 3000;
    let value_of_shares: u64 = 3000;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: shares_to_burn,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: shares_to_burn,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: shares_to_burn,
            actual_collateral_user: value_of_shares,
        );
}

#[test]
#[should_panic(
    expected: "Vault Protection Limit Exceeded, tv_at_last_check: 60000, tv_after_operation: 56999, max_allowed_loss : 3000",
)]
fn test_multiple_redeems_cumulative_failure() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    // Initial deposit to vault: 50,000 USDC
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 50000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Redeeming user deposits 10,000 USDC to invest
    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10000_u64),
        );

    // Invest 10,000 USDC into vault
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 10000,
                    min_shares_to_receive: 5000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // trigger loading of TV and setting the limit
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    // Baseline TV = 60000. Limit = 3000 loss.

    // 1st redeem: 1500 USDC (ok)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1500,
            value_of_shares_user: 1500,
            shares_to_burn_vault: 1500,
            value_of_shares_vault: 1500,
            actual_shares_user: 1500,
            actual_collateral_user: 1500,
        );

    // 2nd redeem: 1498 USDC (ok, total = 2999)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1498,
            value_of_shares_user: 1498,
            shares_to_burn_vault: 1498,
            value_of_shares_vault: 1498,
            actual_shares_user: 1498,
            actual_collateral_user: 1498,
        );

    // 3rd redeem: 2 USDC (should fail, total would be 3001)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 2,
            value_of_shares_user: 2,
            shares_to_burn_vault: 2,
            value_of_shares_vault: 2,
            actual_shares_user: 2,
            actual_collateral_user: 2,
        );
}

#[test]
fn test_reset_after_24h() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 50000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 10000,
                    min_shares_to_receive: 5000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // trigger loading of TV and setting the limit
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    // Baseline TV = 60000. Limit = 3000 loss.
    // Redeem 2900 USDC (ok)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 2900,
            value_of_shares_user: 2900,
            shares_to_burn_vault: 2900,
            value_of_shares_vault: 2900,
            actual_shares_user: 2900,
            actual_collateral_user: 2900,
        );

    // Wait another 24h+
    state.facade.advance_time(86401);
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.funding_tick(array![].span());
    // Now baseline should be ~57100. New limit ~2855.
    // Redeem another 2000 USDC (should be ok)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 2000,
            value_of_shares_user: 2000,
            shares_to_burn_vault: 2000,
            value_of_shares_vault: 2000,
            actual_shares_user: 2000,
            actual_collateral_user: 2000,
        );
}

#[test]
fn test_profit_does_not_reset_baseline_until_24h_pass() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 50000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 10000,
                    min_shares_to_receive: 5000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // trigger loading of TV and setting the limit
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 10000_u64),
        );

    //vault has 69999, but last check was at 60000
    // limit is be 3000, but we have additional 10000
    // redeem up to 12999 should succeed
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 9000,
            value_of_shares_user: 9000,
            shares_to_burn_vault: 9000,
            value_of_shares_vault: 9000,
            actual_shares_user: 9000,
            actual_collateral_user: 9000,
        );
}

#[test]
#[should_panic(
    expected: "Vault Protection Limit Exceeded, tv_at_last_check: 70000, tv_after_operation: 66499, max_allowed_loss : 3500",
)]
fn test_profit_then_redeem_over_limit_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 50000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 20000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 20000,
                    min_shares_to_receive: 5000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // trigger loading of TV and setting the limit
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    // Baseline TV = 70000. Limit = 3500 loss.
    // Profit 10000. TV = 80000.
    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 10000_u64),
        );

    // Redeem 13501.
    // Delta = 80000 - 13501 - 70000 = -3501.
    // Loss = 3501. Limit = 3500. Should fail.
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 13500,
            value_of_shares_user: 13500,
            shares_to_burn_vault: 13500,
            value_of_shares_vault: 13500,
            actual_shares_user: 13500,
            actual_collateral_user: 13500,
        );
}

#[test]
fn test_force_reset_protection_limit_allows_redemption() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    // Initial deposit to vault: 50,000 USDC
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 50000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 10000,
                    min_shares_to_receive: 5000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // trigger loading of TV and setting the limit (5% of 60000 = 3000)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    // Force reset to 10% (6000)
    state.facade.force_reset_protection_limit(vault_config.position_id, 10);

    // Now redeem 4000, should succeed.
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 4000,
            value_of_shares_user: 4000,
            shares_to_burn_vault: 4000,
            value_of_shares_vault: 4000,
            actual_shares_user: 4000,
            actual_collateral_user: 4000,
        );
}

#[test]
fn test_per_vault_protection_limit_override() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    // Initial deposit: 50,000 USDC
    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 50000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 20000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 20000,
                    min_shares_to_receive: 10000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // Initial baseline (5% of 70000 = 3500)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1,
            value_of_shares_user: 1,
            shares_to_burn_vault: 1,
            value_of_shares_vault: 1,
            actual_shares_user: 1,
            actual_collateral_user: 1,
        );

    // Update per-vault override to 20%
    state.facade.update_vault_protection_limit(vault_config.position_id, 20);

    // Wait 24h
    state.facade.advance_time(86401);
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.funding_tick(array![].span());

    // New baseline should be (70000 - 1) = 69999.
    // New max loss (with override) = 69999 * 200 / 1000 = 13999.
    // Redeeming 10000 should now succeed (would have failed with default 5% limit)
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 10000,
            value_of_shares_user: 10000,
            shares_to_burn_vault: 10000,
            value_of_shares_vault: 10000,
            actual_shares_user: 10000,
            actual_collateral_user: 10000,
        );
}