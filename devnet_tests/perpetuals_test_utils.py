import asyncio
import bisect
import os
from pathlib import Path
import random
import requests
from test_utils.starknet_test_utils import load_contract
from scripts.script_utils import get_project_root
from poseidon_py.poseidon_hash import poseidon_hash_many
from starknet_py.cairo.felt import encode_shortstring
from starknet_py.contract import Contract
from starknet_py.hash.utils import message_signature, pedersen_hash
from starknet_py.net.account.account import Account
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
from test_utils.starknet_test_utils import StarknetTestUtils
from typing import Dict, Tuple, Optional
from conftest import contracts_inner_fixture, resource_bounds
from typing import Union
from starknet_py.contract import DeclareResult, DeployResult
from starknet_py.net.account.account import Account
from starknet_py.net.models.chains import StarknetChainId


### Constants ###

# Required for hash computations.
ORDER_ARGS_HASH = 0x36DA8D51815527CABFAA9C982F564C80FA7429616739306036F1F9B608DD112
WITHDEAW_ARGS_HASH = 0x250A5FA378E8B771654BD43DCB34844534F9D1E29E16B14760D7936EA7F4B1D
STARKNET_DOMAIN_HASH = 0x1FF2F602E42168014D405A94F75E8A93D640751D71D16311266E140D8B0A210
PERPETUALS_NAME = "Perpetuals"
PERPETUALS_VERSION = "v0"
STARKNET_CHAIN_ID = StarknetChainId.MAINNET
REVISION = 1

MAX_UINT32 = 2**32 - 1  # Maximum value for a 32-bit unsigned integer
TWO_POW_40 = 2**40  # 2^40
TWO_POW_32 = 2**32  # 2^32

POSITION_ID_STR = "position_id"
BASE_ASSET_ID_STR = "base_asset_id"
BASE_AMOUNT_STR = "base_amount"
QUOTE_ASSET_ID_STR = "quote_asset_id"
QUOTE_AMOUNT_STR = "quote_amount"
FEE_ASSET_ID_STR = "fee_asset_id"
FEE_AMOUNT_STR = "fee_amount"
EXPIRATION_STR = "expiration"
SALT_STR = "salt"
VALUE_STR = "value"
SECONDS_STR = "seconds"
SIGNATURE_STR = "signature"
SIGNER_PUBLIC_KEY_STR = "signer_public_key"
TIMESTAMP_STR = "timestamp"
ORACLE_PRICE_STR = "oracle_price"


class PerpetualsTestUtils:
    def __init__(
        self,
        StarknetTestUtils: StarknetTestUtils,
        perpetuals_contract_address: int,
        now_timestamp: int,
        extended_active_synthetic_asset_ids: list[int],
        accounts: dict[str, Account],
        contracts: dict[str, Contract],
    ):
        self.starknet_test_utils = StarknetTestUtils
        self.known_accounts = accounts
        self.known_contracts = contracts

        self.perpetuals_contract_address = perpetuals_contract_address
        self.now_timestamp = now_timestamp
        self.operator_nonce = None
        self.asset_ids = extended_active_synthetic_asset_ids

        self.new_accounts_number = 0
        self.new_accounts = []

        # new_account_contracts[account] = contract
        self.new_account_contracts = {}

        # new_account_key_pairs[account] = (public_key, private_key)
        self.new_account_key_pairs = {}

        # new_account_positions[account] = position_id
        self.new_account_positions = {}

        random_seed = int(os.getenv("RANDOM_SEED", "0"))
        random.seed(random_seed)

    ### Helper functions ###

    def get_account_public_key(self, account: Account) -> int:
        return self.new_account_key_pairs[account][0]

    def get_account_address(self, account: Account) -> int:
        return account.address

    def get_account_position_id(self, account: Account) -> int:
        return self.new_account_positions[account]

    def create_signed_price(
        self, account: Account, oracle_price: int, timestamp: int, asset_name: int, oracle_name: int
    ):
        asset_oracle_payload = TWO_POW_40 * asset_name + oracle_name
        price_timestamp_payload = oracle_price * TWO_POW_32 + timestamp
        msg_hash = pedersen_hash(asset_oracle_payload, price_timestamp_payload)

        signature = message_signature(msg_hash, self.new_account_key_pairs[account][1])
        return {
            SIGNATURE_STR: signature,
            SIGNER_PUBLIC_KEY_STR: self.get_account_public_key(account),
            TIMESTAMP_STR: timestamp,
            ORACLE_PRICE_STR: oracle_price,
        }

    async def create_order(
        self,
        position_id: int,
        base_asset_id: int,
        base_amount: int,
        quote_amount: int,
        fee_amount: int,
        expiration: int,
    ):
        salt = random.randint(0, MAX_UINT32)
        collateral_asset_id = await self.get_collateral_asset_id()
        return {
            POSITION_ID_STR: formatted_position_id(position_id),
            BASE_ASSET_ID_STR: formatted_asset_id(base_asset_id),
            BASE_AMOUNT_STR: base_amount,
            QUOTE_ASSET_ID_STR: formatted_asset_id(collateral_asset_id),
            QUOTE_AMOUNT_STR: quote_amount,
            FEE_ASSET_ID_STR: formatted_asset_id(collateral_asset_id),
            FEE_AMOUNT_STR: fee_amount,
            EXPIRATION_STR: formatted_timestamp(expiration),
            SALT_STR: salt,
        }

    async def new_account(self) -> Account:
        if self.new_accounts_number >= len(self.starknet_test_utils.starknet.accounts):
            raise ValueError("No more accounts available")

        account = self.starknet_test_utils.starknet.accounts[self.new_accounts_number]
        self.new_accounts.append(account)
        self.new_account_key_pairs[account] = (
            account.signer.public_key,
            account.signer.private_key,
        )
        self.new_accounts_number += 1

        abi, cairo_version = await ContractAbiResolver(
            address=self.perpetuals_contract_address,
            client=account.client,
            proxy_config=ProxyConfig(),
        ).resolve()

        account_contract = Contract(
            address=self.perpetuals_contract_address,
            abi=abi,
            provider=account,
            cairo_version=cairo_version,
        )
        self.new_account_contracts[account] = account_contract

        return account

    ### View functions ###

    async def get_operator_nonce(self) -> int:
        (nonce,) = await self.known_contracts["operator"].functions["get_operator_nonce"].call()
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
        (asset_id,) = await self.known_contracts["operator"].functions["get_collateral_id"].call()
        return asset_id["value"]

    async def get_base_collateral_token_contract(self) -> int:
        (token_contract,) = (
            await self.known_contracts["operator"]
            .functions["get_base_collateral_token_contract"]
            .call()
        )
        return token_contract["contract_address"]

    async def get_position_total_value(self, position_id: int) -> int:
        (tv_tr,) = (
            await self.known_contracts["operator"]
            .functions["get_position_tv_tr"]
            .call(formatted_position_id(position_id))
        )
        return tv_tr["total_value"]

    async def get_num_of_active_synthetic_assets(self) -> int:
        (num_of_active_synthetic_assets,) = (
            await self.known_contracts["operator"]
            .functions["get_num_of_active_synthetic_assets"]
            .call()
        )
        return num_of_active_synthetic_assets

    async def get_asset_timely_data(self, asset_id: int) -> dict:
        (asset_timely_data,) = (
            await self.known_contracts["operator"]
            .functions["get_timely_data"]
            .call(formatted_asset_id(asset_id))
        )
        return asset_timely_data

    ### Storage-mutating functions ###

    async def new_position(self, account: Account, tries: int = 3) -> int:
        error = None
        while tries > 0:
            position_id = random.randint(1, MAX_UINT32)
            try:
                invocation = (
                    await self.known_contracts["operator"]
                    .functions["new_position"]
                    .invoke_v3(
                        await self.consume_operator_nonce(),
                        formatted_position_id(position_id),
                        self.get_account_public_key(account),
                        self.get_account_address(account),
                        True,
                        auto_estimate=True,
                    )
                )
                await invocation.wait_for_acceptance(check_interval=0.1)
                # Success! Store and return the position_id
                self.new_account_positions[account] = position_id
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
                address=await self.get_base_collateral_token_contract(),
                client=self.known_accounts["rich_usdc_holder"].client,
                proxy_config=ProxyConfig(),
            ).resolve()

            erc20_contract = Contract(
                address=await self.get_base_collateral_token_contract(),
                abi=abi,
                provider=self.known_accounts["rich_usdc_holder"],
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
                address=await self.get_base_collateral_token_contract(),
                client=account.client,
                proxy_config=ProxyConfig(),
            ).resolve()

            erc20_contract = Contract(
                address=await self.get_base_collateral_token_contract(),
                abi=abi,
                provider=account,
                cairo_version=cairo_version,
            )

            invocation = await erc20_contract.functions["approve"].invoke_v3(
                self.perpetuals_contract_address, amount, auto_estimate=True
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _approve_deposit(account, amount)

        # Deposit
        salt = random.randint(0, MAX_UINT32)
        invocation = (
            await self.new_account_contracts[account]
            .functions["deposit_asset"]
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
            invocation = (
                await self.known_contracts["operator"]
                .functions["process_deposit"]
                .invoke_v3(
                    await self.consume_operator_nonce(),
                    self.get_account_address(account),
                    formatted_asset_id(await self.get_collateral_asset_id()),
                    formatted_position_id(self.get_account_position_id(account)),
                    amount,
                    salt,
                    auto_estimate=True,
                )
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
        signature = message_signature(message_hash, self.new_account_key_pairs[account][1])
        asset_id = await self.get_collateral_asset_id()

        invocation = (
            await self.new_account_contracts[account]
            .functions["withdraw_request"]
            .invoke_v3(
                signature,
                formatted_asset_id(asset_id),
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
            asset_id = await self.get_collateral_asset_id()

            invocation = (
                await self.known_contracts["operator"]
                .functions["withdraw"]
                .invoke_v3(
                    await self.consume_operator_nonce(),
                    formatted_asset_id(asset_id),
                    self.get_account_address(account),
                    formatted_position_id(self.get_account_position_id(account)),
                    amount,
                    formatted_timestamp(expiration),
                    salt,
                    auto_estimate=True,
                )
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _process_withdraw(account, amount, expiration, salt)

    async def price_tick(self, asset_id: int, oracle_price: int, signed_prices: list[dict]):
        invocation = (
            await self.known_contracts["operator"]
            .functions["price_tick"]
            .invoke_v3(
                await self.get_operator_nonce(),
                formatted_asset_id(asset_id),
                oracle_price,
                signed_prices,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def add_synthetic_asset(
        self,
        risk_factor_tiers: list[int],
        risk_factor_first_tier_boundary: int,
        risk_factor_tier_size: int,
        quorum: int,
        resolution_factor: int,
    ):
        asset_id = random.randint(1, MAX_UINT32)
        try:
            invocation = (
                await self.known_contracts["app_governor"]
                .functions["add_synthetic_asset"]
                .invoke_v3(
                    formatted_asset_id(asset_id),
                    risk_factor_tiers,
                    risk_factor_first_tier_boundary,
                    risk_factor_tier_size,
                    quorum,
                    resolution_factor,
                    auto_estimate=True,
                )
            )
            await invocation.wait_for_acceptance(check_interval=0.1)
            bisect.insort(self.asset_ids, asset_id)
            return asset_id
        except Exception as e:
            raise Exception(f"Failed to add synthetic asset {asset_id}: {e}")

    async def add_oracle_to_asset(
        self, asset_id: int, oracle_public_key: int, oracle_name: int, asset_name: int
    ):
        invocation = (
            await self.known_contracts["app_governor"]
            .functions["add_oracle_to_asset"]
            .invoke_v3(
                formatted_asset_id(asset_id),
                oracle_public_key,
                oracle_name,
                asset_name,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def funding_tick(self, funding_ticks_diffs: dict):
        FUNDING_INDEX_STR = "funding_index"
        ASSET_ID_STR = "asset_id"

        # Get all funding indices
        async def _get_all_funding_indices() -> Dict[int, int]:
            async def fetch_funding_index(asset_id: int) -> Tuple[int, Optional[int]]:
                try:
                    timely_data = await self.get_asset_timely_data(asset_id)
                    funding_index_value = timely_data[FUNDING_INDEX_STR][VALUE_STR]
                    return (asset_id, funding_index_value)
                except Exception as e:
                    print(f"Error fetching funding index for asset {hex(asset_id)}: {e}")
                    return (asset_id, None)

            coroutines = [fetch_funding_index(asset_id) for asset_id in self.asset_ids]

            results = await asyncio.gather(*coroutines)

            funding_indices = {
                asset_id: funding_index
                for asset_id, funding_index in results
                if funding_index is not None
            }

            num_of_active_synthetic_assets = await self.get_num_of_active_synthetic_assets()
            if len(funding_indices) != num_of_active_synthetic_assets:
                raise Exception(
                    f"Failed to get all funding indices. \
                    Expected {num_of_active_synthetic_assets}, got {len(funding_indices)}."
                )
            return funding_indices

        current_funding_indices = await _get_all_funding_indices()

        # Calculate new funding indices
        new_funding_indices = []
        for asset_id in self.asset_ids:
            if asset_id in funding_ticks_diffs.keys():
                new_funding_indices.append(
                    {
                        ASSET_ID_STR: formatted_asset_id(asset_id),
                        FUNDING_INDEX_STR: formatted_funding_index(
                            current_funding_indices[asset_id] + funding_ticks_diffs[asset_id]
                        ),
                    }
                )
            else:
                new_funding_indices.append(
                    {
                        ASSET_ID_STR: formatted_asset_id(asset_id),
                        FUNDING_INDEX_STR: formatted_funding_index(
                            current_funding_indices[asset_id]
                        ),
                    }
                )

        # Execute funding tick
        invocation = (
            await self.known_contracts["operator"]
            .functions["funding_tick"]
            .invoke_v3(
                await self.get_operator_nonce(),
                new_funding_indices,
                formatted_timestamp(self.now_timestamp),
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def trade(
        self,
        account_a: Account,
        account_b: Account,
        order_a: dict,
        order_b: dict,
        actual_amount_base_a: int,
        actual_amount_quote_a: int,
        actual_fee_a: int,
        actual_fee_b: int,
    ):
        order_a_hash = poseidon_hash_many(
            [
                ORDER_ARGS_HASH,
                order_a[POSITION_ID_STR][VALUE_STR],
                order_a[BASE_ASSET_ID_STR][VALUE_STR],
                order_a[BASE_AMOUNT_STR],
                order_a[QUOTE_ASSET_ID_STR][VALUE_STR],
                order_a[QUOTE_AMOUNT_STR],
                order_a[FEE_ASSET_ID_STR][VALUE_STR],
                order_a[FEE_AMOUNT_STR],
                order_a[EXPIRATION_STR][SECONDS_STR],
                order_a[SALT_STR],
            ]
        )
        order_b_hash = poseidon_hash_many(
            [
                ORDER_ARGS_HASH,
                order_b[POSITION_ID_STR][VALUE_STR],
                order_b[BASE_ASSET_ID_STR][VALUE_STR],
                order_b[BASE_AMOUNT_STR],
                order_b[QUOTE_ASSET_ID_STR][VALUE_STR],
                order_b[QUOTE_AMOUNT_STR],
                order_b[FEE_ASSET_ID_STR][VALUE_STR],
                order_b[FEE_AMOUNT_STR],
                order_b[EXPIRATION_STR][SECONDS_STR],
                order_b[SALT_STR],
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

        message_a = [
            encode_shortstring("StarkNet Message"),
            starknet_domain_hash,
            self.get_account_public_key(account_a),
            order_a_hash,
        ]
        message_b = [
            encode_shortstring("StarkNet Message"),
            starknet_domain_hash,
            self.get_account_public_key(account_b),
            order_b_hash,
        ]

        message_hash_a = poseidon_hash_many(message_a)
        message_hash_b = poseidon_hash_many(message_b)
        signature_a = message_signature(message_hash_a, self.new_account_key_pairs[account_a][1])
        signature_b = message_signature(message_hash_b, self.new_account_key_pairs[account_b][1])

        invocation = (
            await self.known_contracts["operator"]
            .functions["trade"]
            .invoke_v3(
                await self.get_operator_nonce(),
                signature_a,
                signature_b,
                order_a,
                order_b,
                actual_amount_base_a,
                actual_amount_quote_a,
                actual_fee_a,
                actual_fee_b,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def upgrade_perpetuals_contract(
        self,
        eic_data: Optional[dict] = None,
    ):
        """
        Upgrade the perpetuals contract to a new implementation.
        """
        upgrade_governor_contract = self.known_contracts["upgrade_governor"]
        new_class_hash = (
            await declare_contract("perpetuals_Core", self.known_accounts["upgrade_governor"])
        ).class_hash

        invocation = await upgrade_governor_contract.functions["add_new_implementation"].invoke_v3(
            {
                "impl_hash": new_class_hash,
                "eic_data": eic_data,
                "final": False,
            },
            auto_estimate=True,
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

        invocation = await upgrade_governor_contract.functions["replace_to"].invoke_v3(
            {
                "impl_hash": new_class_hash,
                "eic_data": eic_data,
                "final": False,
            },
            auto_estimate=True,
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

        # After the upgrade, the ABI changes, so we need to re-fetch the contracts
        self.known_contracts = await contracts_inner_fixture(
            self.perpetuals_contract_address, self.known_accounts
        )
        self.new_account_contracts = await contracts_inner_fixture(
            self.perpetuals_contract_address, self.new_accounts
        )

    async def register_and_activate_external_component(
        self, contract_name: str, component_type: str
    ):
        component_declare_result = await declare_contract(
            contract_name, self.known_accounts["upgrade_governor"]
        )
        invocation = (
            await self.known_contracts["upgrade_governor"]
            .functions["register_external_component"]
            .invoke_v3(
                encode_shortstring(component_type),
                component_declare_result.class_hash,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

        invocation = (
            await self.known_contracts["upgrade_governor"]
            .functions["activate_external_component"]
            .invoke_v3(
                encode_shortstring(component_type),
                component_declare_result.class_hash,
                auto_estimate=True,
            )
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    ### JSON-RPC requests ###
    async def fund_account(self, address: Union[str, int], amount: int, unit: str = "FRI") -> dict:
        """
        Fund an account on devnet using the devnet_mint JSON-RPC method.

        Args:
            address: The account address to fund (hex string, e.g., "0x6e3205f...")
            amount: The amount to mint
            unit: The unit of the amount ("WEI" or "FRI")

        Returns:
            The JSON-RPC response as a dictionary

        Raises:
            requests.HTTPError: If the request fails
            ValueError: If the JSON-RPC response contains an error
        """
        if isinstance(address, int):
            address = hex(address)
        port = self.starknet_test_utils.starknet.port
        response = requests.post(
            f"http://localhost:{port}",
            json={
                "jsonrpc": "2.0",
                "id": "1",
                "method": "devnet_mint",
                "params": {
                    "address": address,
                    "amount": amount,
                    "unit": unit,
                },
            },
            timeout=10,
        )
        response.raise_for_status()
        result = response.json()
        if "error" in result:
            print(f"Error funding account: {result['error']}")
            raise ValueError(f"devnet_mint failed: {result['error']}")
        print(f"Successfully funded account {address}: {result}")
        return result

    def get_account_balance(
        self,
        address: Union[str, int],
        unit: str = "FRI",
    ) -> int:
        """
        Get an account's balance on devnet using the devnet_getAccountBalance JSON-RPC method.

        Args:
            address: The account address (hex string or int)
            unit: The unit of the balance ("WEI" or "FRI")

        Returns:
            The JSON-RPC response as a dictionary

        Raises:
            requests.HTTPError: If the request fails
            ValueError: If the JSON-RPC response contains an error
        """
        if isinstance(address, int):
            address = hex(address)
        port = self.starknet_test_utils.starknet.port
        response = requests.post(
            f"http://localhost:{port}",
            json={
                "jsonrpc": "2.0",
                "id": "1",
                "method": "devnet_getAccountBalance",
                "params": {
                    "address": address,
                    "unit": unit,
                    "block_id": "latest",
                },
            },
            timeout=10,
        )
        response.raise_for_status()
        result = response.json()
        if "error" in result:
            print(f"Error getting account balance: {result['error']}")
            raise ValueError(f"devnet_getAccountBalance failed: {result['error']}")
        return int(result["result"]["amount"])


### Utility functions ###
async def declare_contract(
    contract_name: str,
    account: Account,
) -> DeclareResult:
    compiled_contract_casm = load_contract(
        contract_name=f"{contract_name}.compiled_contract_class",
        base_path=Path(os.path.join(get_project_root(), "target", "release")),
    )
    compiled_contract = load_contract(
        contract_name=f"{contract_name}.contract_class",
        base_path=Path(os.path.join(get_project_root(), "target", "release")),
    )
    declare_result = await Contract.declare_v3(
        account=account,
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=False,
        resource_bounds=resource_bounds,
    )
    await declare_result.wait_for_acceptance(check_interval=0.1)
    return declare_result


async def deploy_contract(
    declare_result: DeclareResult,
    constructor_args: list[Union[dict, int, str, bool, list, tuple]],
) -> DeployResult:
    deploy_result = await declare_result.deploy_v3(
        auto_estimate=False,
        resource_bounds=resource_bounds,
        constructor_args=constructor_args,
    )
    await deploy_result.wait_for_acceptance(check_interval=0.1)
    return deploy_result


def formatted_position_id(value: int) -> dict:
    return {VALUE_STR: value}


def formatted_asset_id(value: int) -> dict:
    return {VALUE_STR: value}


def formatted_timestamp(seconds: int) -> dict:
    return {SECONDS_STR: seconds}


def formatted_funding_index(value: int) -> dict:
    return {VALUE_STR: value}
