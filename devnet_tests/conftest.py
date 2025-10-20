import pytest
from typing import Iterator, Callable
from test_utils.starknet_test_utils import StarknetTestUtils


@pytest.fixture(scope="session")
def operator_address() -> int:
    """
    Return the constant address of the 'operator' contract as an int.
    """
    return 0x048DDC53F41523D2A6B40C3DFF7F69F4BBAC799CD8B2E3FC50D3DE1D4119441F


@pytest.fixture(scope="session")
def contract_address() -> int:
    """
    Return the constant address of the 'main' contract as an int.
    """
    return 0x062DA0780FAE50D68CECAA5A051606DC21217BA290969B302DB4DD99D2E9B470


@pytest.fixture(scope="session")
def deployer_address() -> int:
    """
    Return the constant address of the 'deployer' contract as an int.
    """
    return 0x0522E5BA327BFBD85138B29BDE060A5340A460706B00AE2E10E6D2A16FBF8C57


@pytest.fixture
def starknet_forked(
    starknet_test_utils_factory: Callable[..., Iterator[StarknetTestUtils]]
) -> Iterator[StarknetTestUtils]:
    with starknet_test_utils_factory(
        fork_network="https://rpc.starknet.lava.build/",
        fork_block=1844544,
    ) as val:
        yield val


@pytest.fixture
def starknet_forked_with_impersonated_accounts(
    starknet_forked: StarknetTestUtils, operator_address: int, deployer_address: int
) -> StarknetTestUtils:
    """
    Impersonate the operator account in the forked Starknet instance.
    """
    client = starknet_forked.starknet.get_client()
    for address in [operator_address, deployer_address]:
        client.impersonate_account(address)

    return starknet_forked
