import pytest
from test_utils.starknet_test_utils import StarknetTestUtils
from starknet_py.contract import Contract


# TODO: Implement system tests for the forked Starknet environment.
def test_dummy(upgrade_perpetuals_core_contract: Contract):
    assert upgrade_perpetuals_core_contract
