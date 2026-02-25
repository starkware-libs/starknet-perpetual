use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use perpetuals::tests::test_utils::assert_with_error;
use starkware_utils_testing::test_utils::TokenTrait;

#[test]
fn test_deposit_into_protocol_vault_recieve_to_same_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let depositing_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state
        .facade
        .process_deposit(
            state.facade.deposit(depositing_user.account, depositing_user.position_id, 1000_u64),
        );

    let perps_usdc_balance_before_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    let depositing_user_usdc_balance_before_vaullt_interaction = state
        .facade
        .get_position_collateral_balance(depositing_user.position_id);

    let depositing_user_vault_share_balance_before_vault_interaction = state
        .facade
        .get_position_asset_balance(depositing_user.position_id, vault_config.asset_id);

    let vault_usdc_balance_before_vault_interaction = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    let expected_shares = state.facade.preview_vault_deposit(vault_config, 1000);

    let pending_vault_deposit = state
        .facade
        .deposit_into_vault(
            vault: vault_config,
            amount_to_invest: 1000,
            min_shares_to_receive: 500,
            :depositing_user,
            receiving_user: depositing_user,
        );

    state.facade.process_deposit(pending_vault_deposit);

    //explicity check invariants
    // 1. perps USDC balance must not change

    let perps_usdc_balance_after_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    assert_with_error(
        perps_usdc_balance_before_vault_interaction == perps_usdc_balance_after_vault_interaction,
        format!(
            "perps usdc balance changed after vault interaction, before: {}, after: {}",
            perps_usdc_balance_before_vault_interaction,
            perps_usdc_balance_after_vault_interaction,
        ),
    );
    // 2. depositing user position balance must decrease by 1000 USDC
    let depositing_user_usdc_balance_after_vaullt_interaction = state
        .facade
        .get_position_collateral_balance(depositing_user.position_id);

    assert_with_error(
        depositing_user_usdc_balance_after_vaullt_interaction == depositing_user_usdc_balance_before_vaullt_interaction
            - 1000_i64.into(),
        format!(
            "depositing user collateral balance did not decrease by 1000, before: {:?}, after: {:?}",
            depositing_user_usdc_balance_before_vaullt_interaction,
            depositing_user_usdc_balance_after_vaullt_interaction,
        ),
    );

    let depositing_user_vault_share_balance_after_vault_interaction = state
        .facade
        .get_position_asset_balance(depositing_user.position_id, vault_config.asset_id);

    // 3. depositing user vault share balance must increase by deposited amount
    assert_with_error(
        depositing_user_vault_share_balance_after_vault_interaction == depositing_user_vault_share_balance_before_vault_interaction
            + expected_shares.into(),
        format!(
            "depositing user vault share balance did not increase, before: {:?}, after: {:?}",
            depositing_user_vault_share_balance_before_vault_interaction,
            depositing_user_vault_share_balance_after_vault_interaction,
        ),
    );

    //4. vault usdc balance must increase by 1000
    let vault_usdc_balance_after_vault_interaction = state
        .facade
        .get_position_collateral_balance(vault_user.position_id);

    assert_with_error(
        vault_usdc_balance_after_vault_interaction == vault_usdc_balance_before_vault_interaction
            + 1000_i64.into(),
        format!(
            "vault usdc balance did not increase by 1000, before: {:?}, after: {:?}",
            vault_usdc_balance_before_vault_interaction,
            vault_usdc_balance_after_vault_interaction,
        ),
    );
}

#[test]
fn test_deposit_into_protocol_vault_recieve_to_different_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let depositing_user = state.new_user_with_position();
    let receiving_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    state
        .facade
        .process_deposit(
            state.facade.deposit(depositing_user.account, depositing_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    :depositing_user,
                    :receiving_user,
                ),
        );

    assert_with_error(
        state
            .facade
            .get_position_asset_balance(depositing_user.position_id, vault_config.asset_id) == 0_i64
            .into(),
        "depositing user vault share balance should be 0",
    );

    assert_with_error(
        state
            .facade
            .get_position_asset_balance(
                receiving_user.position_id, vault_config.asset_id,
            ) == 1000_i64
            .into(),
        "receiving user vault share balance should be 1000",
    );
}

#[test]
#[should_panic(expected: 'ONLY_PERPS_CAN_DEPOSIT')]
fn test_deposit_cannot_be_called_except_by_perps_contract() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let receiving_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');

    let dispatcher: IERC4626Dispatcher = vault_config.deployed_vault.erc4626;
    dispatcher.deposit(assets: 1000, receiver: receiving_user.account.address);
}
