import pytest
from test_utils.starknet_test_utils import StarknetTestUtils
from starknet_py.contract import Contract
from devnet_tests.perpetuals_test_utils import PerpetualsTestUtils


@pytest.mark.asyncio
async def test_helper_functions(
    upgrade_perpetuals_core_contract: Contract,
    starknet_forked_with_impersonated_accounts: StarknetTestUtils,
):
    test_utils = PerpetualsTestUtils(
        starknet_forked_with_impersonated_accounts, upgrade_perpetuals_core_contract
    )

    # Test that we can access the contracts
    assert test_utils.operator_contract is not None
    assert test_utils.app_governor_contract is not None

    # Test new_account
    account = await test_utils.new_account()
    assert account is not None

    # Test helper functions with the created account
    assert test_utils.get_account_address(account) == account.address
    assert test_utils.get_account_public_key(account) == account.signer.public_key

    # Test get_operator_nonce
    nonce = await test_utils.get_operator_nonce()
    assert nonce >= 0

    # Test new_position
    position_id = await test_utils.new_position(account)
    assert position_id > 0
    assert test_utils.get_account_position_id(account) == position_id
