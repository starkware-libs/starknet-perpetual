import pytest
from typing import Iterator, Callable
import pytest_asyncio
from test_utils.starknet_test_utils import StarknetTestUtils
from starknet_py.net.models.chains import StarknetChainId
from test_utils.starknet_test_utils import KeyPair

from starknet_py.net.account.account import Account
from starknet_py.net.models.address import Address
from starknet_py.net.client_models import Call
from starknet_py.contract import Contract
from test_utils.starknet_test_utils import load_contract
from scripts.script_utils import get_project_root
from pathlib import Path
import os
from starknet_py.net.client_models import ResourceBoundsMapping, ResourceBounds
from starknet_test_util import AccountNonceManager


perpetuals_Core = "perpetuals_Core"

resource_bounds = ResourceBoundsMapping(
    l1_gas=ResourceBounds(max_amount=10**15, max_price_per_unit=10**12),
    l1_data_gas=ResourceBounds(max_amount=10**15, max_price_per_unit=10**12),
    l2_gas=ResourceBounds(max_amount=10**15, max_price_per_unit=10**12),
)

OPERATOR_DUMMY_KEY = 1
DEPLOYER_DUMMY_KEY = 2


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
        starknet_chain_id=StarknetChainId.MAINNET,
        request_body_size_limit=20_000_000,
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


@pytest.fixture
def operator_account(
    starknet_forked_with_impersonated_accounts: StarknetTestUtils,
    operator_address: int,
) -> Account:
    """
    Return an Account instance for the impersonated operator account.
    """
    client = starknet_forked_with_impersonated_accounts.starknet.get_client()
    operator_account = Account(
        client=client,
        address=Address(operator_address),
        # Use a dummy private key since the account is impersonated.
        key_pair=KeyPair.from_private_key(OPERATOR_DUMMY_KEY),
        chain=StarknetChainId.MAINNET,
    )
    return operator_account


@pytest.fixture
def deployer_account(
    starknet_forked_with_impersonated_accounts: StarknetTestUtils,
    deployer_address: int,
) -> Account:
    """
    Return an Account instance for the impersonated deployer account.
    """
    client = starknet_forked_with_impersonated_accounts.starknet.get_client()
    deployer_account = Account(
        client=client,
        address=Address(deployer_address),
        # Use a dummy private key since the account is impersonated.
        key_pair=KeyPair.from_private_key(DEPLOYER_DUMMY_KEY),
        chain=StarknetChainId.MAINNET,
    )
    return deployer_account


@pytest.fixture
def setup_account() -> AccountNonceManager:
    """
    Return an AccountNonceManager for managing nonces of impersonated accounts.
    """
    return AccountNonceManager(account_number=0, nonce=0)


@pytest_asyncio.fixture
async def declare_perpetuals_core_contract(
    starknet_forked_with_impersonated_accounts: StarknetTestUtils,
    setup_account: AccountNonceManager,
) -> int:
    compiled_contract_casm = load_contract(
        contract_name=f"{perpetuals_Core}.compiled_contract_class",
        base_path=Path(os.path.join(get_project_root(), "target", "release")),
    )
    compiled_contract = load_contract(
        contract_name=f"{perpetuals_Core}.contract_class",
        base_path=Path(os.path.join(get_project_root(), "target", "release")),
    )
    declare_result = await Contract.declare_v3(
        account=starknet_forked_with_impersonated_accounts.starknet.accounts[
            setup_account.account_number
        ],
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=False,
        nonce=setup_account.bump_nonce(),
        resource_bounds=resource_bounds,
    )
    await declare_result.wait_for_acceptance(check_interval=0.1)
    return declare_result.class_hash
