import pytest
from test_utils.starknet_test_utils import StarknetTestUtils


# TODO: Implement system tests for the forked Starknet environment.
@pytest.mark.asyncio
async def test_dummy(
    starknet_forked_with_impersonated_accounts: StarknetTestUtils,
    declare_perpetuals_core_contract: int,
):
    assert starknet_forked_with_impersonated_accounts
