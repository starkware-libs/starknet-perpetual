import pytest_asyncio
from test_utils.starknet_test_utils import StarknetTestUtils


@pytest_asyncio.fixture
async def simple_test_context(
    starknet_test_utils: StarknetTestUtils,
) -> dict:
    return {
        "version": "0.1.0",
        "contract_name": "simple_contract",
    }
