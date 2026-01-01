import pytest
import pytest_asyncio
from starknet_py.contract import Contract
from starknet_py.net.account.account import Account
from starknet_py.net.schemas.rpc.executables_api import Optional
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
from devnet_tests.perpetuals_test_utils import (
    PerpetualsTestUtils,
    declare_contract,
    deploy_contract,
    VAULT_ASSET_ID,
    VAULT_POSITION_ID,
    formatted_position_id,
    formatted_timestamp,
)

USDC_NEW_CONTRACT_ADDRESS = 0x033068F6539F8E6E6B131E6B2B814E6C34A5224BC66947C47DAB9DFEE93B35FB
USDC_OLD_CONTRACT_ADDRESS = 0x053C91253BC9682C04929CA02ED00B3E423F6710D2EE7E0D5EBB06F3ECF368A8
MIGRATION_CONTRACT_ADDRESS = 0x07BFFC7F6BDA62B7BEE9B7880579633A38F7EF910E0AD5E686B0B8712E216A19
OLD_VAULT_ADDRESS = 0x07DB365513DF1EE2EB8FC2D157D4D1CBA3D4A2EF59B44DD3D61124C88B4F6084
RECIPIENT_ADDRESS = 0x0785932B867B6A21DFD64367EDD181C1CFA83FA7CE942D005857CD5935049D58


@pytest_asyncio.fixture(autouse=True)
async def phase_0_set_public_key(test_utils: PerpetualsTestUtils):

    # TODO: Not sure why but, this is needed to deploy the vault contract.
    #       After some debugging, declare + deploy costs about 1.5 STARKs
    #       so this should be too much funding but it fails with insufficient funding
    #       if we fund the account with less STARKs.
    fund_amount_fri = 3_000_000_000 * 10**18  # 1 STARK = 10**18 FRI
    await test_utils.fund_account(
        address=test_utils.known_accounts["upgrade_governor"].address,
        amount=fund_amount_fri,
    )

    # Upgrade the perpetuals contract to the latest version
    await test_utils.upgrade_perpetuals_contract(contract_name="perpetuals_Core_phase_0")

    # Register and activate the external components.
    # Required because the on-chain WithdrawalManager has the old interface (without collateral_id).
    await test_utils.register_and_activate_external_component(
        "perpetuals_WithdrawalManager", "WITHDRAWALS"
    )

    # Set new public key for Vault Position
    vault_manager_account = await test_utils.new_account()
    new_public_key = test_utils.get_account_public_key(vault_manager_account)
    invocation = (
        await test_utils.known_contracts["operator"]
        .functions["set_public_key"]
        .invoke_v3(
            operator_nonce=await test_utils.get_operator_nonce(),
            position_id=formatted_position_id(VAULT_POSITION_ID),
            new_public_key=new_public_key,
            expiration=formatted_timestamp(0),  # Expiration validation is skipped here,
            auto_estimate=True,
        )
    )
    await invocation.wait_for_acceptance(check_interval=0.1)
    test_utils.vault_manager_account = vault_manager_account


# @pytest.mark.skip(reason="This is a test for USDC migration, run manually when needed")
@pytest.mark.asyncio
async def test_migration(test_utils: PerpetualsTestUtils):
    """
    Phase 0- Set new public key for Vault Position:
    *This is a workaround to allow the migration simulation to succeed*
        1. Upgrade Core contract with a permissionless set_public_key function
        2. Set new public key for Vault Position

    Phase 1- Deploy new vault contract:
        1. Declare New Vault Contract
        2. Invest in vault from POSITION_A and assert that it is successful
        3. Deploy New Vault Contract
        4. Upgrade Core contract (eic only, same class hash)
           (https://github.com/x10xchange/starknet-perpetual/pull/49)
        5. Redeem from vault to POSITION_A and assert that it is successful
        6. [Optional] Upgrade Vault contract to original code (with the replaceability component)

    Phase 2- Upgrade Core contract into migration phase:
        1. Declare new Core contract (https://github.com/x10xchange/starknet-perpetual/pull/44)
        2. Upgrade Core contract with declaration and eic from previous step
        3. Deposit request from ACCOUNT_A to POSITION_A (operator does not process the request)
        3. Withdraw request from POSITION_A to ACCOUNT_A (operator does not process the request)
        4. Transfer request from POSITION_A to POSITION_B (operator does not process the request)
        5. Invest in vault from POSITION_A and assert that it is successful
        6. Store Core contract USDC.e balance
        7. Migrate USDC.e to Native USDC in a few batches (at least 50%)
        8. Assert USDC.e balance + Native USDC balance = Core contract USDC.e balance from step 6

    Phase 3- Upgrade Core contract to final version:
        1. Declare eic for Core contract (https://github.com/x10xchange/starknet-perpetual/pull/45)
        2. Upgrade Core contract (eic only, same class hash)
        3. Declare eic for Vault contract (https://github.com/x10xchange/starknet-perpetual/pull/45)
        4. Upgrade Vault contract (eic only, same class hash)
        5. Assert that process_deposit on deposit request from ACCOUNT_A to POSITION_A fails
        6. Assert that reject_deposit on deposit request from ACCOUNT_A to POSITION_A fails
        7. Process old deposit request from ACCOUNT_A to POSITION_A and assert that it is successful
        8. Withdraw and assert that withdraw request from POSITION_A to ACCOUNT_A is successful
        9. Transfer and assert that transfer request from POSITION_A to POSITION_B is successful
        10. Redeem from vault to POSITION_A and assert that it is successful
        11. Invest in vault from POSITION_A and assert that it is successful
        12. Assert USDC.e balance + Native USDC balance = Original USDC.e balance - withdraw amount
        13. [Optional] Migrate the rest of the USDC.e to Native USDC and assert that it is successful
        14. [Optional] Upgrade Core contract to original code
    """
    ### Phase 1- Deploy new vault contract ###

    new_vault_declare_result = await declare_contract(
        "vault_TempProtocolVault",
        # I chose upgrade governor to declare + deploy because we will need to upgrade
        # contract later but, this is arbitrary, we could use any account.
        test_utils.known_accounts["upgrade_governor"],
    )

    # invest in vault from POSITION_A

    account_a = await test_utils.new_account()
    position_a_id = await test_utils.new_position(account_a)
    await test_utils.deposit(account_a, 3000)
    await test_utils.invest_in_vault(
        account=account_a,
        min_base_amount=500,
        quote_amount=-1000,
    )
    vault_shares_balance_after_invest = await test_utils.get_asset_balance_of_position(
        position_a_id, VAULT_ASSET_ID
    )
    collateral_balance_after_invest = await test_utils.get_asset_balance_of_position(
        position_a_id, await test_utils.get_collateral_asset_id()
    )
    assert vault_shares_balance_after_invest >= 500
    assert collateral_balance_after_invest == 2000

    # Deploy new vault contract

    # This choice is also arbitrary, we could use any account
    governance_admin_address = test_utils.known_accounts["governance_admin"].address
    upgrade_delay = 0
    name = "VaultShare"
    symbol = "VS"
    pnl_collateral_contract = USDC_OLD_CONTRACT_ADDRESS
    perps_contract = test_utils.perpetuals_contract_address
    owning_position_id = VAULT_POSITION_ID
    old_vault_address = OLD_VAULT_ADDRESS
    recipient = RECIPIENT_ADDRESS
    new_vault_deploy_result = await deploy_contract(
        declare_result=new_vault_declare_result,
        constructor_args=[
            governance_admin_address,
            upgrade_delay,
            name,
            symbol,
            pnl_collateral_contract,
            perps_contract,
            owning_position_id,
            old_vault_address,
            recipient,
        ],
    )
    assert new_vault_deploy_result.deployed_contract.address is not None

    # Upgrade core contract

    eic_declare_result = await declare_contract(
        "perpetuals_ReplaceCollateralEIC_phase_1",
        test_utils.known_accounts["upgrade_governor"],
    )
    eic_data = {
        "eic_hash": eic_declare_result.class_hash,
        "eic_init_data": [
            VAULT_ASSET_ID,
            new_vault_deploy_result.deployed_contract.address,
            OLD_VAULT_ADDRESS,
        ],
    }
    await test_utils.upgrade_perpetuals_contract(eic_data=eic_data)
    asset_config = await test_utils.get_asset_config(VAULT_ASSET_ID)
    assert asset_config["token_contract"] == new_vault_deploy_result.deployed_contract.address

    # Redeem from vault to POSITION_A

    await test_utils.redeem_from_vault(account=account_a, base_amount=-250)
    collateral_balance_after_redeem = await test_utils.get_asset_balance_of_position(
        position_a_id, await test_utils.get_collateral_asset_id()
    )
    vault_shares_balance_after_redeem = await test_utils.get_asset_balance_of_position(
        position_a_id, VAULT_ASSET_ID
    )
    assert collateral_balance_after_redeem > collateral_balance_after_invest
    assert vault_shares_balance_after_redeem == vault_shares_balance_after_invest - 250

    # Upgrade vault to original code (with the replaceability component)

    upgrade_governor_account = test_utils.known_accounts["upgrade_governor"]
    abi, cairo_version = await ContractAbiResolver(
        address=new_vault_deploy_result.deployed_contract.address,
        client=upgrade_governor_account.client,
        proxy_config=ProxyConfig(),
    ).resolve()
    upgrade_governor_vault_contract = Contract(
        address=new_vault_deploy_result.deployed_contract.address,
        abi=abi,
        provider=upgrade_governor_account,
        cairo_version=cairo_version,
    )

    governance_admin_account = test_utils.known_accounts["governance_admin"]
    abi, cairo_version = await ContractAbiResolver(
        address=new_vault_deploy_result.deployed_contract.address,
        client=governance_admin_account.client,
        proxy_config=ProxyConfig(),
    ).resolve()
    governance_admin_vault_contract = Contract(
        address=new_vault_deploy_result.deployed_contract.address,
        abi=abi,
        provider=governance_admin_account,
        cairo_version=cairo_version,
    )

    await setup_upgrade_role(upgrade_governor_account.address, governance_admin_vault_contract)
    await upgrade_vault_contract(upgrade_governor_account, upgrade_governor_vault_contract)

    ### Phase 2- Upgrade Core contract into migration phase ###

    # Upgrade Core contract to migration phase
    eic_declare_result = await declare_contract(
        "perpetuals_MigrateTVLEIC",
        test_utils.known_accounts["upgrade_governor"],
    )
    eic_data = {
        "eic_hash": eic_declare_result.class_hash,
        "eic_init_data": [MIGRATION_CONTRACT_ADDRESS],
    }
    await test_utils.upgrade_perpetuals_contract(
        contract_name="perpetuals_Core_phase_2_3", eic_data=eic_data
    )

    # Deposit, Withdraw, Transfer requests but do not process them
    account_b = await test_utils.new_account()
    await test_utils.new_position(account_b)
    await test_utils.deposit(account_a, 1000, process_deposit=False)
    await test_utils.withdraw(account_a, 500, process_withdraw=False)
    await test_utils.transfer(
        sender=account_a, recipient=account_b, amount=500, process_transfer=False
    )

    # Invest in vault
    await test_utils.invest_in_vault(
        account=account_a,
        min_base_amount=500,
        quote_amount=-1000,
    )
    vault_shares_balance_after_2nd_invest = await test_utils.get_asset_balance_of_position(
        position_a_id, VAULT_ASSET_ID
    )
    collateral_balance_after_2nd_invest = await test_utils.get_asset_balance_of_position(
        position_a_id, await test_utils.get_collateral_asset_id()
    )
    assert vault_shares_balance_after_2nd_invest >= vault_shares_balance_after_redeem + 500
    assert collateral_balance_after_2nd_invest == collateral_balance_after_redeem - 1000

    # Store USDC.e balance of Core contract
    old_usdc_perps_balance_before_migration = await get_old_usdc_balance(
        test_utils.known_accounts["operator"], test_utils.perpetuals_contract_address
    )
    new_usdc_perps_balance_before_migration = await get_new_usdc_balance(
        test_utils.known_accounts["operator"], test_utils.perpetuals_contract_address
    )
    assert old_usdc_perps_balance_before_migration > 0
    assert new_usdc_perps_balance_before_migration == 0

    # Register token admin
    token_admin_account = await test_utils.new_account()
    abi, cairo_version = await ContractAbiResolver(
        address=test_utils.perpetuals_contract_address,
        client=token_admin_account.client,
        proxy_config=ProxyConfig(),
    ).resolve()
    token_admin_perps_contract = Contract(
        address=test_utils.perpetuals_contract_address,
        abi=abi,
        provider=token_admin_account,
        cairo_version=cairo_version,
    )
    await test_utils.register_token_admin(token_admin_account)

    # get max available swap amount
    abi, cairo_version = await ContractAbiResolver(
        address=MIGRATION_CONTRACT_ADDRESS,
        client=token_admin_account.client,
        proxy_config=ProxyConfig(),
    ).resolve()
    migration_contract = Contract(
        address=MIGRATION_CONTRACT_ADDRESS,
        abi=abi,
        provider=token_admin_account,
        cairo_version=cairo_version,
    )
    (max_available_swap_amount,) = await migration_contract.functions["max_available_swap"].call()
    print(f"Max available swap amount: {max_available_swap_amount}")

    # Migrate USDC
    threshold = old_usdc_perps_balance_before_migration // 2
    current_old_usdc_perps_balance = old_usdc_perps_balance_before_migration
    current_new_usdc_perps_balance = 0
    amount_to_migrate = 100_000_000_000
    total_migrated = 0
    while current_old_usdc_perps_balance > threshold:
        if total_migrated + amount_to_migrate > max_available_swap_amount:
            print(f"Max available swap amount reached, total migrated: {total_migrated}")
            break
        await test_utils.migrate_usdc(contract=token_admin_perps_contract, amount=amount_to_migrate)
        current_old_usdc_perps_balance -= amount_to_migrate
        current_new_usdc_perps_balance += amount_to_migrate
        total_migrated += amount_to_migrate
        print(
            f"Migrated {amount_to_migrate} USDC.e, current old balance: {current_old_usdc_perps_balance}, current new balance: {current_new_usdc_perps_balance}"
        )
    old_usdc_perps_balance_after_migration = await get_old_usdc_balance(
        test_utils.known_accounts["operator"], test_utils.perpetuals_contract_address
    )
    new_usdc_perps_balance_after_migration = await get_new_usdc_balance(
        test_utils.known_accounts["operator"], test_utils.perpetuals_contract_address
    )
    assert old_usdc_perps_balance_after_migration == current_old_usdc_perps_balance
    assert new_usdc_perps_balance_after_migration == current_new_usdc_perps_balance

    # Assert that the total USDC.e + Native USDC = Original USDC.e balance
    assert (
        old_usdc_perps_balance_after_migration + new_usdc_perps_balance_after_migration
        == old_usdc_perps_balance_before_migration
    )


async def setup_upgrade_role(
    upgrade_governor_account_address: int, governance_admin_vault_contract: Contract
):
    invocation = await governance_admin_vault_contract.functions[
        "register_upgrade_governor"
    ].invoke_v3(
        upgrade_governor_account_address,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance(check_interval=0.1)


async def upgrade_vault_contract(
    upgrade_governor_account: Account,
    upgrade_governor_vault_contract: Contract,
    eic_data: Optional[dict] = None,
):
    new_class_hash = (
        await declare_contract(
            "vault_ProtocolVault",
            upgrade_governor_account,
        )
    ).class_hash

    invocation = await upgrade_governor_vault_contract.functions[
        "add_new_implementation"
    ].invoke_v3(
        {
            "impl_hash": new_class_hash,
            "eic_data": eic_data,
            "final": False,
        },
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance(check_interval=0.1)

    invocation = await upgrade_governor_vault_contract.functions["replace_to"].invoke_v3(
        {
            "impl_hash": new_class_hash,
            "eic_data": eic_data,
            "final": False,
        },
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance(check_interval=0.1)


async def get_old_usdc_balance(account: Account, address: Optional[int] = None):
    if address is None:
        address = account.address
    abi, cairo_version = await ContractAbiResolver(
        address=USDC_OLD_CONTRACT_ADDRESS,
        client=account.client,
        proxy_config=ProxyConfig(),
    ).resolve()
    usdc_contract = Contract(
        address=USDC_OLD_CONTRACT_ADDRESS,
        abi=abi,
        provider=account,
        cairo_version=cairo_version,
    )
    (balance,) = await usdc_contract.functions["balance_of"].call(address)
    return balance


async def get_new_usdc_balance(account: Account, address: Optional[int] = None):
    if address is None:
        address = account.address
    abi, cairo_version = await ContractAbiResolver(
        address=USDC_NEW_CONTRACT_ADDRESS,
        client=account.client,
        proxy_config=ProxyConfig(),
    ).resolve()
    usdc_contract = Contract(
        address=USDC_NEW_CONTRACT_ADDRESS,
        abi=abi,
        provider=account,
        cairo_version=cairo_version,
    )
    (balance,) = await usdc_contract.functions["balance_of"].call(address)
    return balance
