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
MAX_UINT32 = 2**32 - 1

# Required for hash computation.
PERPETUALS_NAME = "Perpetuals"
PERPETUALS_VERSION = "v0"
STARKNET_CHAIN_ID = str(StarknetChainId.MAINNET)
REVISION = str(1)
DOMAIN = {
    "name": PERPETUALS_NAME,
    "version": PERPETUALS_VERSION,
    "chainId": STARKNET_CHAIN_ID,
    "revision": REVISION,
}

ORDER_TYPES = {
    "StarknetDomain": [
        {"name": "name", "type": "felt"},
        {"name": "version", "type": "felt"},
        {"name": "chainId", "type": "felt"},
        {"name": "revision", "type": "felt"},
    ],
    "PositionId": [
        {"name": "value", "type": "u128"},
    ],
    "AssetId": [
        {"name": "value", "type": "felt"},
    ],
    "Timestamp": [
        {"name": "seconds", "type": "u128"},
    ],
    "Order": [
        {"name": "position_id", "type": "PositionId"},
        {"name": "base_asset_id", "type": "AssetId"},
        {"name": "base_amount", "type": "i128"},
        {"name": "quote_asset_id", "type": "AssetId"},
        {"name": "quote_amount", "type": "i128"},
        {"name": "fee_asset_id", "type": "AssetId"},
        {"name": "fee_amount", "type": "u128"},
        {"name": "expiration", "type": "Timestamp"},
        {"name": "salt", "type": "felt"},
    ],
}
class PerpetualsTestUtils:
    def __init__(self, StarknetTestUtils: StarknetTestUtils, operator_contract: Contract):
        self.starknet_test_utils = StarknetTestUtils
        self.operator_contract = operator_contract
        self.accounts_number = 0

        self.account_contracts = {}
        self.account_public_keys = {}
        self.account_positions = {}


    async def new_account(self) -> Account:
        if self.accounts_number >= len(self.starknet_test_utils.starknet.accounts):
            raise ValueError("No more accounts available")
        account = self.starknet_test_utils.starknet.accounts[self.accounts_number]
        self.account_public_keys[account] = account.signer.public_key
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

    def get_account_public_key(self, account: Account) -> int:
        return self.account_public_keys[account]

    def get_account_address(self, account: Account) -> int:
        return account.address

    async def get_operator_nonce(self) -> int:
        (nonce,) = await self.operator_contract.functions["get_operator_nonce"].call()
        return nonce
    
    async def new_position(self, account: Account) -> int:
        while True:
            position_id = random.randint(1, MAX_UINT32)
            try:
                invocation = await self.operator_contract.functions["new_position"].invoke_v3(
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
                # print(e)
                print(f"Position {position_id} already exists, trying again with a new random ID")
                continue
    
    def get_position_id(self, account: Account) -> int:
        return self.account_positions[account]
    
    async def get_collateral_asset_id(self) -> int:
        (asset_id,) = await self.operator_contract.functions["get_collateral_id"].call()
        return asset_id["value"]

    async def get_collateral_token_contract(self) -> int:
        (token_contract,) = await self.operator_contract.functions["get_collateral_token_contract"].call()
        return token_contract["contract_address"]
    
    async def process_deposit(self, account: Account, amount: int, salt: int):
        invocation = await self.operator_contract.functions["process_deposit"].invoke_v3(
            await self.get_operator_nonce(),
            {"value": await self.get_collateral_asset_id()},
            self.get_account_address(account),
            {"value": self.get_position_id(account)},
            amount,
            salt,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def approve_deposit(self, account: Account, amount: int):
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
            self.operator_contract.address,
            amount,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)
    
    async def deposit(self, account: Account, amount: int):
        await self.approve_deposit(account, amount)
        salt = random.randint(0, MAX_UINT32)
        invocation = await self.account_contracts[account].functions["deposit"].invoke_v3(
            {"value": await self.get_collateral_asset_id()},
            self.get_account_address(account),
            {"value": self.get_position_id(account)},
            amount,
            salt,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)
        await self.process_deposit(account, amount, salt)

    async def get_position_total_value(self, position_id: int) -> int:
        (tv_tr,) = await self.operator_contract.functions["get_position_tv_tr"].call(
            {"value": position_id}
        )
        return tv_tr["total_value"]

    # async def add_vault_collateral_asset(self, erc20_contract_address: int, quantum: int, resolution_factor: int, risk_factor_tiers: list[int], risk_factor_first_tier_boundary: int, risk_factor_tier_size: int, quorum: int):
    #     while True:
    #         asset_id = random.randint(1, MAX_UINT32)
    #         try:
    #             invocation = await self.operator_contract.functions["add_vault_collateral_asset"].invoke_v3(
    #                 asset_id,
    #                 erc20_contract_address,
    #                 quantum, 
    #                 resolution_factor,
    #                 risk_factor_tiers,
    #                 risk_factor_first_tier_boundary,
    #                 risk_factor_tier_size,
    #                 quorum,
    #                 auto_estimate=True
    #             )
    #             await invocation.wait_for_acceptance(check_interval=0.1)
    #             return asset_id
    #         except Exception as e:
    #             print(f"Asset {asset_id} already exists, trying again with a new random ID")
    #             continue

    async def create_order(self, position_id: int, base_asset_id: int, base_amount: int, quote_amount: int, fee_amount: int, expiration: int):
        salt = random.randint(0, MAX_UINT32)
        collateral_asset_id = await self.get_collateral_asset_id()
        return  {
            "position_id": {"value": position_id},
            "base_asset_id": {"value": base_asset_id},
            "base_amount": base_amount,
            "quote_asset_id": {"value": collateral_asset_id},
            "quote_amount": quote_amount,
            "fee_asset_id": {"value": collateral_asset_id},
            "fee_amount": fee_amount,
            "expiration": {"seconds": expiration},
            "salt": salt,
        }

    # TODO(Omri): Fix trade, I think need support from software-mansion for signed ints
    async def trade(self, account_a: Account, account_b: Account, order_a: dict, order_b: dict, actual_amount_base_a: int, actual_amount_quote_a: int, actual_fee_a: int, actual_fee_b: int):
        payload_a = {
            "types": ORDER_TYPES,
            "primaryType": "Order",
            "domain": DOMAIN,
            "message": order_a,
        }
        signature_a = account_a.sign_message(payload_a)

        payload_b = {
            "types": ORDER_TYPES,
            "primaryType": "Order",
            "domain": DOMAIN,
            "message": order_b,
        }
        signature_b = account_b.sign_message(payload_b)
        
        invocation = await self.operator_contract.functions["trade"].invoke_v3(
            await self.get_operator_nonce(),
            signature_a,
            signature_b,
            order_a,
            order_b,
            actual_amount_base_a,
            actual_amount_quote_a,
            actual_fee_a,
            actual_fee_b,
            auto_estimate=True
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

        #TODO(Omri): Add wrapper functions for withdraw, add_asset (needs add_oracle_to_asset), price_tick, funding_tick