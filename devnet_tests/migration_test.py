import pytest
from starknet_py.cairo.felt import encode_shortstring
from devnet_tests.perpetuals_test_utils import (
    PerpetualsTestUtils,
    declare_contract,
    deploy_contract,
)

USDC_CONTRACT_ADDRESS = 0x033068F6539F8E6E6B131E6B2B814E6C34A5224BC66947C47DAB9DFEE93B35FB
VAULT_POSITION_ID = 0x7
VAULT_ASSET_ID = 0x7DB365513DF1EE2EB8FC2D157D4D1CBA3D4A2EF59B44DD3D61124C88B4F6084
OLD_VAULT_ADDRESS = 0x07DB365513DF1EE2EB8FC2D157D4D1CBA3D4A2EF59B44DD3D61124C88B4F6084
RECIPIENT_ADDRESS = 0x785932B867B6A21DFD64367EDD181C1CFA83FA7CE942D005857CD5935049D58


# @pytest.mark.skip(reason="This is a test for USDC migration, run manually when needed")
@pytest.mark.asyncio
async def test_migration(test_utils: PerpetualsTestUtils):
    """
    Phase 1- Deploy new vault contract:
        1. Declare New Vault Contract
        2. Invest in vault from POSITION_A and assert that it is successful
        3. Deploy New Vault Contract
        4. Upgrade Core contract (eic only, same class hash)
        5. Redeem from vault to POSITION_A and assert that it is successful
        6. Upgrade Vault contract to original code (with the replaceability component)

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
        3. Assert that process_deposit on deposit request from ACCOUNT_A to POSITION_A fails
        4. Assert that reject_deposit on deposit request from ACCOUNT_A to POSITION_A fails
        5. Process old deposit request from ACCOUNT_A to POSITION_A and assert that it is successful
        6. Withdraw and assert that withdraw request from POSITION_A to ACCOUNT_A is successful
        7. Transfer and assert that transfer request from POSITION_A to POSITION_B is successful
        8. Redeem from vault to POSITION_A and assert that it is successful
        9. Invest in vault from POSITION_A and assert that it is successful
        10. Assert USDC.e balance + Native USDC balance = Original USDC.e balance - withdraw amount
        11. Upgrade Core contract to original code
    """
    ### Phase 1- Deploy new vault contract:

    fund_amount_fri = 3_000_000_000 * 10**18
    await test_utils.fund_account(
        address=test_utils.known_accounts["deployer"].address,
        amount=fund_amount_fri,
    )
    new_vault_declare_result = await declare_contract(
        "vault_TempProtocolVault",
        test_utils.known_accounts["deployer"],
    )

    # invest in vault from POSITION_A (TODO)

    # Deploy new vault contract
    governance_admin_address = test_utils.known_accounts["governance_admin"].address
    upgrade_delay = 0
    name = "VaultShare"
    symbol = "VS"
    pnl_collateral_contract = USDC_CONTRACT_ADDRESS
    perps_contract = test_utils.known_contracts["operator"].address
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
    core_contract_declare_result = await declare_contract(
        "perpetuals_Core",
        test_utils.known_accounts["deployer"],
    )
    eic_declare_result = await declare_contract(
        "perpetuals_ReplaceCollateralEIC",
        test_utils.known_accounts["deployer"],
    )
    eic_data = {
        "eic_hash": eic_declare_result.class_hash,
        "eic_init_data": [
            VAULT_ASSET_ID,
            new_vault_deploy_result.deployed_contract.address,
            OLD_VAULT_ADDRESS,
        ],
    }
    await test_utils.upgrade_contract(
        new_class_hash=core_contract_declare_result.class_hash, eic_data=eic_data
    )
    asset_config = await test_utils.get_asset_config(VAULT_ASSET_ID)
    assert asset_config["token_contract"] == new_vault_deploy_result.deployed_contract.address

    # Redeem from vault to POSITION_A (TODO)

    # Upgrade vault to original code (with the replaceability component)
    new_vault_declare_result = await declare_contract(
        "vault_ProtocolVault",
        test_utils.known_accounts["deployer"],
    )
    await test_utils.upgrade_contract(
        new_class_hash=new_vault_declare_result.class_hash, eic_data=None
    )
