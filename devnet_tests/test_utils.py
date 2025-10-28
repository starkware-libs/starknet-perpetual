import pytest
from typing import Iterator, Callable
import pytest_asyncio
from starknet_py.net.schemas.common import Uint64
from test_utils.starknet_test_utils import StarknetTestUtils
from starknet_py.net.models.chains import StarknetChainId
from test_utils.starknet_test_utils import KeyPair

from starknet_py.net.account.account import Account
from starknet_py.net.models.address import Address
from starknet_py.net.client_models import Call
from starknet_py.contract import Contract
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
from starknet_py.utils.typed_data import Domain, TypedData
from test_utils.starknet_test_utils import load_contract
from scripts.script_utils import get_project_root
from pathlib import Path
import os
import random
from starknet_py.net.client_models import ResourceBoundsMapping, ResourceBounds

# Maximum value for a 64-bit unsigned integer
MAX_UINT64 = 2**64 - 1

# Required for hash computation.
PERPETUALS_NAME = "Perpetuals"
PERPETUALS_VERSION = "v0"

class TestUtils:
    def __init__(self, StarknetTestUtils: StarknetTestUtils, operator: Contract):
        self.starknet_test_utils = StarknetTestUtils
        self.operator = operator
        self.starknet_test_utils = StarknetTestUtils
        self.accounts_number = 0

        self.account_contracts = {}
        self.account_public_keys = {}
        self.account_positions = {}
        self.account_salts = {}

        self.starknet_domain = Domain(
            name=PERPETUALS_NAME,
            version=PERPETUALS_VERSION,
            chain_id=self.starknet_test_utils.starknet.starknet_chain_id,
            revision=1,
        )


    async def new_account(self) -> Account:
        if self.accounts_number >= len(self.starknet_test_utils.starknet.accounts):
            raise ValueError("No more accounts available")
        account = self.starknet_test_utils.starknet.accounts[self.accounts_number]
        self.account_public_keys[account] = account.signer.public_key
        self.accounts_number += 1

        abi, cairo_version = await ContractAbiResolver(
            address=account.address,
            client=account.client,
            proxy_config=ProxyConfig(),
        ).resolve()
        account_contract = Contract(
            address=account.address,
            abi=abi,
            provider=account.client,
            cairo_version=cairo_version,
        )
        self.account_contracts[account] = account_contract
        return account_contract

    def get_account_public_key(self, account: Account) -> int:
        return self.account_public_keys[account]

    def get_account_address(self, account: Account) -> int:
        return account.address

    async def get_operator_nonce(self) -> int:
        (nonce,) = await self.operator.functions["get_operator_nonce"].call()
        return nonce
    
    async def new_position(self, account: Account) -> int:
        while True:
            position_id = random.randint(1, MAX_UINT64)
            try:
                invocation = await self.operator.functions["new_position"].invoke_v3(
                    await self.get_operator_nonce(), 
                    {"value": position_id}, 
                    self.get_account_public_key(account), 
                    self.get_account_address(account),
                    auto_estimate=True
                )
                await invocation.wait_for_acceptance(check_interval=0.1)
                # Success! Store and return the position_id
                self.account_positions[account] = position_id
                return position_id
            except Exception as e:
                print(f"Position {position_id} already exists, trying again with a new random ID")
                continue
    
    def get_position_id(self, account: Account) -> int:
        return self.account_positions[account]
    
    async def get_collateral_asset_id(self) -> int:
        (asset_id,) = await self.operator.functions["get_collateral_id"].call()
        return asset_id.as_dict()["value"]

    def generate_salt(self, account: Account) -> int:
        salt = random.randint(0, MAX_UINT64)
        self.account_salts[account].append(salt)
        return salt
    
    def consume_salt(self, account: Account) -> int:
        return self.account_salts[account].pop(0)
    
    async def deposit(self, account: Account, amount: int):
        salt = self.generate_salt(account)
        invocation = await self.account_contracts[account].functions["deposit"].invoke_v3(
            await self.get_collateral_asset_id(),
            self.get_account_address(account),
            {"value": self.get_position_id(account)},
            amount,
            salt,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def process_deposit(self, account: Account, amount: int):
        salt = self.consume_salt(account)
        invocation = await self.operator.functions["process_deposit"].invoke_v3(
            await self.get_operator_nonce(),
            await self.get_collateral_asset_id(),
            self.get_account_address(account),
            {"value": self.get_position_id(account)},
            amount,
            salt,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def add_vault_collateral_asset(self, erc20_contract_address: int, quantum: int, resolution_factor: int, risk_factor_tiers: list[int], risk_factor_first_tier_boundary: int, risk_factor_tier_size: int, quorum: int):
        while True:
            asset_id = random.randint(1, MAX_UINT64)
            try:
                invocation = await self.operator.functions["add_vault_collateral_asset"].invoke_v3(
                    asset_id,
                    erc20_contract_address,
                    quantum, 
                    resolution_factor,
                    risk_factor_tiers,
                    risk_factor_first_tier_boundary,
                    risk_factor_tier_size,
                    quorum,
                    auto_estimate=True
                )
                await invocation.wait_for_acceptance(check_interval=0.1)
                return asset_id
            except Exception as e:
                print(f"Asset {asset_id} already exists, trying again with a new random ID")
                continue

    async def register_vault(self, account: Account, vault_contract_address: int, vault_asset_id: int, expiration: int):
        position_id = self.get_position_id(account)
        payload = TypedData(
            types={
                "RegisterVaultArgs": [
                    {"name": "vault_position_id", "type": "PositionId"},
                    {"name": "vault_contract_address", "type": "ContractAddress"},
                    {"name": "vault_asset_id", "type": "AssetId"},
                    {"name": "expiration", "type": "Timestamp"},
                ],
            },
            primary_type="RegisterVaultArgs",
            domain=self.starknet_domain,
            message={
                "vault_position_id": {"value": position_id},
                "vault_contract_address": vault_contract_address,
                "vault_asset_id": vault_asset_id,
                "expiration": {"seconds": expiration},
            },
        )
        signature = account.sign_message(payload)   # TODO: looks like there is a mixup with public key and account address
        invocation = await self.operator.functions["register_vault"].invoke_v3(
            await self.get_operator_nonce(),
            signature,
            {"value": position_id},
            vault_contract_address,
            vault_asset_id,
            {"seconds": expiration},
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def deposit_into_vault(self, account: Account, vault_position_id: int, amount: int, expiration: int):
        position_id = self.get_position_id(account)
        salt = self.generate_salt(account)
        payload = TypedData(
            types={
                "DepositIntoVaultArgs": [
                    {"name": "position_id", "type": "PositionId"},
                    {"name": "vault_position_id", "type": "PositionId"},
                    {"name": "collateral_quantized_amount", "type": "u64"},
                    {"name": "expiration", "type": "Timestamp"},
                    {"name": "salt", "type": "felt252"},
                ],
            },
            primary_type="DepositIntoVaultArgs",
            domain=self.starknet_domain,
            message={
                "position_id": {"value": position_id},
                "vault_position_id": {"value": vault_position_id},
                "collateral_quantized_amount": amount,
                "expiration": {"seconds": expiration},
                "salt": salt,
            },
        )
        signature = account.sign_message(payload)   # TODO: looks like there is a mixup with public key and account address
        invocation = await self.account_contracts[account].functions["deposit_into_vault"].invoke_v3(
            await self.get_operator_nonce(),
            signature,
            {"value": position_id},
            {"value": vault_position_id},
            amount,
            {"seconds": expiration},
            salt,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def redeem_from_vault(self, account: Account, vault_position_id: int, number_of_shares: int, minimum_received_total_amount: int, vault_share_execution_price: int, expiration: int):
        position_id = self.get_position_id(account)
        salt = self.generate_salt(account)
        payload = TypedData(
            types={
                "RedeemFromVaultArgs": [
                    {"name": "position_id", "type": "PositionId"},
                    {"name": "vault_position_id", "type": "PositionId"},
                    {"name": "number_of_shares", "type": "u64"},
                    {"name": "minimum_received_total_amount", "type": "u64"},
                    {"name": "expiration", "type": "Timestamp"},
                    {"name": "salt", "type": "felt252"},
                ],
            },
            primary_type="RedeemFromVaultArgs",
            domain=self.starknet_domain,
            message={
                "position_id": {"value": position_id},
                "vault_position_id": {"value": vault_position_id},
                "number_of_shares": number_of_shares,   
                "minimum_received_total_amount": minimum_received_total_amount,
                "expiration": {"seconds": expiration},
                "salt": salt,
            },
        )
        user_signature = account.sign_message(payload)   # TODO: looks like there is a mixup with public key and account address
        vault_owner_signature = account.sign_message(payload)   # TODO: looks like there is a mixup with public key and account address
        invocation = await self.operator.functions["redeem_from_vault"].invoke_v3(
            await self.get_operator_nonce(),
            user_signature,
            {"value": position_id},
            vault_owner_signature,
            {"value": vault_position_id},
            number_of_shares,
            minimum_received_total_amount,
            vault_share_execution_price,
            {"seconds": expiration},
            salt,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)


        #TODO: Fix salt in deposit and redeem from vault and deposit in general