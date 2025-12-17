import pytest
from devnet_tests.perpetuals_test_utils import PerpetualsTestUtils


@pytest.mark.asyncio
async def test_helper_functions(test_utils: PerpetualsTestUtils):
    """Test helper functions in PerpetualsTestUtils."""

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


@pytest.mark.asyncio
async def test_view_functions(test_utils: PerpetualsTestUtils):
    """Test view functions in the perpetuals contract."""

    # Test get_operator_nonce
    nonce = await test_utils.get_operator_nonce()
    assert nonce >= 0

    # Test get_collateral_asset_id
    collateral_asset_id = await test_utils.get_collateral_asset_id()
    assert collateral_asset_id == 1

    # Test get_collateral_token_contract
    token_contract = await test_utils.get_collateral_token_contract()
    assert token_contract > 0

    # Test get_num_of_active_synthetic_assets
    num_assets = await test_utils.get_num_of_active_synthetic_assets()
    assert num_assets == 76

    # Create account and position for position-related view functions
    account = await test_utils.new_account()
    position_id = await test_utils.new_position(account)

    # Test get_position_total_value
    position_tv = await test_utils.get_position_total_value(position_id)
    assert position_tv == 0


@pytest.mark.asyncio
async def test_deposit_withdraw(test_utils: PerpetualsTestUtils):
    """Test deposit and withdraw functionality."""

    # Create account and position
    account = await test_utils.new_account()
    position_id = await test_utils.new_position(account)

    # Test deposit
    deposit_amount = 10
    await test_utils.deposit(account, deposit_amount)

    # Verify position total value is equal to the deposit amount
    tv_after_deposit = await test_utils.get_position_total_value(position_id)
    assert tv_after_deposit == 10

    # Test withdraw
    withdraw_amount = 5
    expiration = 3765971800  # Some future timestamp
    await test_utils.withdraw(account, withdraw_amount, expiration)

    # Verify position total value decreased by withdraw amount
    tv_after_withdraw = await test_utils.get_position_total_value(position_id)
    assert tv_after_withdraw == 5
