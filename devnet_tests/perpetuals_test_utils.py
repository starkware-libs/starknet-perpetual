import os
import random
from starknet_py.contract import Contract
from starknet_py.net.account.account import Account
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
from test_utils.starknet_test_utils import StarknetTestUtils

MAX_UINT32 = 2**32 - 1  # Maximum value for a 32-bit unsigned integer


def formatted_position_id(value: int) -> dict:
    return {"value": value}


class PerpetualsTestUtils:
    def __init__(
        self, StarknetTestUtils: StarknetTestUtils, upgrade_perpetuals_core_contract: dict
    ):
        self.starknet_test_utils = StarknetTestUtils
        self.operator_contract = upgrade_perpetuals_core_contract["operator_contract"]
        self.app_governor_contract = upgrade_perpetuals_core_contract["app_governor_contract"]

        self.operator_nonce = None
        self.accounts_number = 0
        self.account_contracts = {}
        self.account_key_pairs = {}  # key_pairs[account] = (public_key, private_key)
        self.account_positions = {}

    ## Helper functions

    def get_account_public_key(self, account: Account) -> int:
        return self.account_key_pairs[account][0]

    def get_account_address(self, account: Account) -> int:
        return account.address

    def get_account_position_id(self, account: Account) -> int:
        return self.account_positions[account]

    async def new_account(self) -> Account:
        if self.accounts_number >= len(self.starknet_test_utils.starknet.accounts):
            raise ValueError("No more accounts available")

        account = self.starknet_test_utils.starknet.accounts[self.accounts_number]
        self.account_key_pairs[account] = (account.signer.public_key, account.signer.private_key)
        self.accounts_number += 1

        abi, cairo_version = await ContractAbiResolver(
            address=self.operator_contract.address,
            client=account.client,
            proxy_config=ProxyConfig(),
        ).resolve()

        account_contract = Contract(
            address=self.operator_contract.address,
            abi=abi,
            provider=account,
            cairo_version=cairo_version,
        )
        self.account_contracts[account] = account_contract

        return account

    ## View functions

    async def get_operator_nonce(self) -> int:
        (nonce,) = await self.operator_contract.functions["get_operator_nonce"].call()
        self.operator_nonce = nonce
        return nonce

    async def consume_operator_nonce(self) -> int:
        if self.operator_nonce is None:
            await self.get_operator_nonce()
        nonce = self.operator_nonce
        self.operator_nonce += 1
        return nonce

    ## Storage-mutating functions

    async def new_position(self, account: Account, seed: int | None = None, tries: int = 3) -> int:
        error = None
        if seed is None:
            seed = int(os.getenv("RANDOM_SEED", "0"))
        random.seed(seed)
        while tries > 0:
            position_id = random.randint(1, MAX_UINT32)
            try:
                invocation = await self.operator_contract.functions["new_position"].invoke_v3(
                    await self.consume_operator_nonce(),
                    formatted_position_id(position_id),
                    self.get_account_public_key(account),
                    self.get_account_address(account),
                    auto_estimate=True,
                )
                await invocation.wait_for_acceptance(check_interval=0.1)
                # Success! Store and return the position_id
                self.account_positions[account] = position_id
                return position_id

            except Exception as e:
                tries -= 1
                error = e
                continue

        assert error is not None
        raise Exception(f"Failed to create a new position: {error}")
