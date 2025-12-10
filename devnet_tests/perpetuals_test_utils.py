import os
import random
from poseidon_py.poseidon_hash import poseidon_hash_many
from starknet_py.cairo.felt import encode_shortstring
from starknet_py.contract import Contract
from starknet_py.hash.utils import message_signature
from starknet_py.net.account.account import Account
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
from test_utils.starknet_test_utils import StarknetTestUtils

# Required for hash computations.
WITHDEAW_ARGS_HASH = 0x250A5FA378E8B771654BD43DCB34844534F9D1E29E16B14760D7936EA7F4B1D
STARKNET_DOMAIN_HASH = 0x1FF2F602E42168014D405A94F75E8A93D640751D71D16311266E140D8B0A210
PERPETUALS_NAME = "Perpetuals"
PERPETUALS_VERSION = "v0"
STARKNET_CHAIN_ID = StarknetChainId.MAINNET
REVISION = 1

MAX_UINT32 = 2**32 - 1  # Maximum value for a 32-bit unsigned integer


def formatted_position_id(value: int) -> dict:
    return {"value": value}


def formatted_asset_id(value: int) -> dict:
    return {"value": value}


def formatted_timestamp(seconds: int) -> dict:
    return {"seconds": seconds}


class PerpetualsTestUtils:
    def __init__(
        self,
        StarknetTestUtils: StarknetTestUtils,
        upgrade_perpetuals_core_contract: dict,
        rich_usdc_holder_account: Account,
    ):
        self.starknet_test_utils = StarknetTestUtils
        self.operator_contract = upgrade_perpetuals_core_contract["operator_contract"]
        self.app_governor_contract = upgrade_perpetuals_core_contract["app_governor_contract"]
        self.rich_usdc_holder_account = rich_usdc_holder_account

        self.operator_nonce = None
        self.accounts_number = 0
        self.account_contracts = {}
        self.account_key_pairs = {}  # key_pairs[account] = (public_key, private_key)
        self.account_positions = {}

        random_seed = int(os.getenv("RANDOM_SEED", "0"))
        random.seed(random_seed)

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
        return nonce

    async def consume_operator_nonce(self) -> int:
        if self.operator_nonce is None:
            nonce = await self.get_operator_nonce()
            self.operator_nonce = nonce + 1
            return nonce
        nonce = self.operator_nonce
        self.operator_nonce += 1
        return nonce

    async def get_collateral_asset_id(self) -> int:
        (asset_id,) = await self.operator_contract.functions["get_collateral_id"].call()
        return asset_id["value"]

    async def get_collateral_token_contract(self) -> int:
        (token_contract,) = await self.operator_contract.functions[
            "get_collateral_token_contract"
        ].call()
        return token_contract["contract_address"]

    async def get_position_total_value(self, position_id: int) -> int:
        (tv_tr,) = await self.operator_contract.functions["get_position_tv_tr"].call(
            formatted_position_id(position_id)
        )
        return tv_tr["total_value"]

    async def get_num_of_active_synthetic_assets(self) -> int:
        (num_of_active_synthetic_assets,) = await self.operator_contract.functions[
            "get_num_of_active_synthetic_assets"
        ].call()
        return num_of_active_synthetic_assets

    ## Storage-mutating functions

    async def new_position(self, account: Account, tries: int = 3) -> int:
        error = None
        while tries > 0:
            position_id = random.randint(1, MAX_UINT32)
            try:
                invocation = await self.operator_contract.functions["new_position"].invoke_v3(
                    await self.consume_operator_nonce(),
                    formatted_position_id(position_id),
                    self.get_account_public_key(account),
                    self.get_account_address(account),
                    True,
                    auto_estimate=True,
                )
                await invocation.wait_for_acceptance(check_interval=0.1)
                # Success! Store and return the position_id
                self.account_positions[account] = position_id
                return position_id

            except Exception as e:
                tries -= 1
                error = e
                self.operator_nonce = None
                continue

        assert error is not None
        raise Exception(f"Failed to create a new position: {error}")

    async def deposit(self, account: Account, amount: int):
        # Fund the account with collateral tokens
        async def _fund_account_with_collateral(account: Account, amount: int):
            """Fund an account with collateral tokens using the rich USDC holder account."""
            # Get the ERC20 contract
            abi, cairo_version = await ContractAbiResolver(
                address=await self.get_collateral_token_contract(),
                client=self.rich_usdc_holder_account.client,
                proxy_config=ProxyConfig(),
            ).resolve()

            erc20_contract = Contract(
                address=await self.get_collateral_token_contract(),
                abi=abi,
                provider=self.rich_usdc_holder_account,
                cairo_version=cairo_version,
            )

            # Transfer tokens to the test account
            invocation = await erc20_contract.functions["transfer"].invoke_v3(
                account.address, amount, auto_estimate=True
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _fund_account_with_collateral(account, amount)

        # Approve deposit
        async def _approve_deposit(account: Account, amount: int):
            abi, cairo_version = await ContractAbiResolver(
                address=await self.get_collateral_token_contract(),
                client=account.client,
                proxy_config=ProxyConfig(),
            ).resolve()

            erc20_contract = Contract(
                address=await self.get_collateral_token_contract(),
                abi=abi,
                provider=account,
                cairo_version=cairo_version,
            )

            invocation = await erc20_contract.functions["approve"].invoke_v3(
                self.operator_contract.address, amount, auto_estimate=True
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _approve_deposit(account, amount)

        # Deposit
        salt = random.randint(0, MAX_UINT32)
        invocation = (
            await self.account_contracts[account]
            .functions["deposit"]
            .invoke_v3(
                formatted_asset_id(await self.get_collateral_asset_id()),
                formatted_position_id(self.get_account_position_id(account)),
                amount,
                salt,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

        # Process deposit
        async def _process_deposit(account: Account, amount: int, salt: int):
            invocation = await self.operator_contract.functions["process_deposit"].invoke_v3(
                await self.consume_operator_nonce(),
                self.get_account_address(account),
                formatted_asset_id(await self.get_collateral_asset_id()),
                formatted_position_id(self.get_account_position_id(account)),
                amount,
                salt,
                auto_estimate=True,
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _process_deposit(account, amount, salt)

    async def withdraw(self, account: Account, amount: int, expiration: int):
        salt = random.randint(0, MAX_UINT32)
        collateral_asset_id = await self.get_collateral_asset_id()

        withdraw_args_hash = poseidon_hash_many(
            [
                WITHDEAW_ARGS_HASH,
                self.get_account_address(account),
                self.get_account_position_id(account),
                collateral_asset_id,
                amount,
                expiration,
                salt,
            ]
        )
        starknet_domain_hash = poseidon_hash_many(
            [
                STARKNET_DOMAIN_HASH,
                encode_shortstring(PERPETUALS_NAME),
                encode_shortstring(PERPETUALS_VERSION),
                STARKNET_CHAIN_ID,
                REVISION,
            ]
        )

        message = [
            encode_shortstring("StarkNet Message"),
            starknet_domain_hash,
            self.get_account_public_key(account),
            withdraw_args_hash,
        ]

        message_hash = poseidon_hash_many(message)
        signature = message_signature(message_hash, self.account_key_pairs[account][1])

        invocation = (
            await self.account_contracts[account]
            .functions["withdraw_request"]
            .invoke_v3(
                signature,
                self.get_account_address(account),
                formatted_position_id(self.get_account_position_id(account)),
                amount,
                formatted_timestamp(expiration),
                salt,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

        # Process withdrawal request
        async def _process_withdraw(account: Account, amount: int, expiration: int, salt: int):
            invocation = await self.operator_contract.functions["withdraw"].invoke_v3(
                await self.consume_operator_nonce(),
                self.get_account_address(account),
                formatted_position_id(self.get_account_position_id(account)),
                amount,
                formatted_timestamp(expiration),
                salt,
                auto_estimate=True,
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _process_withdraw(account, amount, expiration, salt)
