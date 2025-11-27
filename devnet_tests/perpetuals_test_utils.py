import asyncio
import bisect
import os
import random
from poseidon_py.poseidon_hash import poseidon_hash_many
from starknet_py.cairo.felt import encode_shortstring
from starknet_py.contract import Contract
from starknet_py.hash.utils import message_signature, pedersen_hash
from starknet_py.net.account.account import Account
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
from test_utils.starknet_test_utils import StarknetTestUtils
from typing import Dict, Tuple, Optional
from conftest import NOW

# Required for hash computations.
WITHDEAW_ARGS_HASH = 0x250A5FA378E8B771654BD43DCB34844534F9D1E29E16B14760D7936EA7F4B1D
STARKNET_DOMAIN_HASH = 0x1FF2F602E42168014D405A94F75E8A93D640751D71D16311266E140D8B0A210
PERPETUALS_NAME = "Perpetuals"
PERPETUALS_VERSION = "v0"
STARKNET_CHAIN_ID = StarknetChainId.MAINNET
REVISION = 1

MAX_UINT32 = 2**32 - 1  # Maximum value for a 32-bit unsigned integer
TWO_POW_40 = 2**40  # 2^40
TWO_POW_32 = 2**32  # 2^32

# Required for funding tick when forking from mainnet.
# This list is relavent for block number 3861835.
# When changing the forked block number, this list needs to be updated to support funding tick.
# This list must be sorted in ascending order.
EXTENDED_SYNTHETIC_ASSET_IDS = [
    255399919616426605400900257294843904,
    255399919633304379671818952480129024,
    255399919636945194886730150859243520,
    270915948027776046540867925536931840,
    338824487460085561411166284290195456,
    338883663474438343746899177019277312,
    338905303280690764515996647076921344,
    339127382605583335846376969292742656,
    339128557725978860634015450544472064,
    339167696437051981397172032081231872,
    339189412421329087967425821086318592,
    339248760150559911178053148269871104,
    339249788878727834962578719796887552,
    344097595806435454645696181259206656,
    344278863660798979802850626929426432,
    344400637349001255728961162330505216,
    349208209667358115027548008674754560,
    349553874717371921940984895618678784,
    354684143347689286618180522700963840,
    359653178029624005735478030701166592,
    359754745788483493062461101120159744,
    359855675003405245145646005674311680,
    359977924063000458297011360688504832,
    359998998794517018713123529349398528,
    364785659509114736355216580319117312,
    370260563196593831237922481296637952,
    370321410161845694364216165796937728,
    375656867931341909315028931361898496,
    380625508329364671305743144700608512,
    380663843873413173657742089127985152,
    385960324586951584765944650413375488,
    390746430762672347138718348219514880,
    396000038112596647361460946256003072,
    396101378379648832210803477251620864,
    396101380212403101135280116273774592,
    396323605930722754555422238098587648,
    401211989740530901651818111897174016,
    401212385921352564110845035577081856,
    401334549526471356934815741500194816,
    401395555207980563015918882817835008,
    401415362247400203280702639630712832,
    401415448619475043208479622807158784,
    406403816491335810657189215283970048,
    411778891792336016648512811332272128,
    411817625024622139428925067103305728,
    416789435879299995223824283975286784,
    416789436818522072078212394507042816,
    416992418108949182116875998607704064,
    417113878881044044170394349040828416,
    427174429141597609995520190256775168,
    431877150642355703025313311742754816,
    432365923161760081025958177373421568,
    432549653271839585844452234968956928,
    432568984945910917982054318042251264,
    432590218091046889185300129471528960,
    432590218096110157059814614722674688,
    432670881640427675234041645227835392,
    432690441716627433572355962568704000,
    437477565754482165017662333485318144,
    437557744680566327621078168874516480,
    437638715834618327041098343530889216,
    437761440258352922500030743109959680,
    437822852025511902434950189083000832,
    437823079767580094335063891128614912,
    442933058567680452956063953642848256,
    448024668544195796360802891422760960,
    453216002551035381248377800238301184,
    453276691323521307730974454904258560,
    453276858440817581570030792557461504,
    458247228599093253039736795210711040,
    458267273324209361917147961830146048,
    458550751644561930336286859415519232,
    458591633377628216554099757268598784,
    468711525804946640478875348763672576,
    468915544507303112068184696028135424,
    468976147866535357546823156383088640,
]


def formatted_position_id(value: int) -> dict:
    return {"value": value}


def formatted_asset_id(value: int) -> dict:
    return {"value": value}


def formatted_timestamp(seconds: int) -> dict:
    return {"seconds": seconds}


def formatted_funding_index(value: int) -> dict:
    return {"value": value}


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
        self.asset_ids = EXTENDED_SYNTHETIC_ASSET_IDS
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

    def create_signed_price(
        self, account: Account, oracle_price: int, timestamp: int, asset_name: int, oracle_name: int
    ):
        asset_oracle_payload = TWO_POW_40 * asset_name + oracle_name
        price_timestamp_payload = oracle_price * TWO_POW_32 + timestamp
        msg_hash = pedersen_hash(asset_oracle_payload, price_timestamp_payload)

        signature = message_signature(msg_hash, self.account_key_pairs[account][1])
        return {
            "signature": signature,
            "signer_public_key": self.get_account_public_key(account),
            "timestamp": timestamp,
            "oracle_price": oracle_price,
        }

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

    async def get_base_collateral_token_contract(self) -> int:
        (token_contract,) = await self.operator_contract.functions[
            "get_base_collateral_token_contract"
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

    async def get_asset_timely_data(self, asset_id: int) -> dict:
        (asset_timely_data,) = await self.operator_contract.functions["get_timely_data"].call(
            formatted_asset_id(asset_id)
        )
        return asset_timely_data

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
                address=await self.get_base_collateral_token_contract(),
                client=self.rich_usdc_holder_account.client,
                proxy_config=ProxyConfig(),
            ).resolve()

            erc20_contract = Contract(
                address=await self.get_base_collateral_token_contract(),
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
                self.operator_contract.address, amount, auto_estimate=True
            )
            await invocation.wait_for_acceptance(check_interval=0.1)

        await _approve_deposit(account, amount)

        # Deposit
        salt = random.randint(0, MAX_UINT32)
        invocation = (
            await self.account_contracts[account]
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

    async def price_tick(self, asset_id: int, oracle_price: int, signed_prices: list[dict]):
        invocation = await self.operator_contract.functions["price_tick"].invoke_v3(
            await self.get_operator_nonce(),
            formatted_asset_id(asset_id),
            oracle_price,
            signed_prices,
            auto_estimate=True,
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
            invocation = await self.app_governor_contract.functions[
                "add_synthetic_asset"
            ].invoke_v3(
                formatted_asset_id(asset_id),
                risk_factor_tiers,
                risk_factor_first_tier_boundary,
                risk_factor_tier_size,
                quorum,
                resolution_factor,
                auto_estimate=True,
            )
            await invocation.wait_for_acceptance(check_interval=0.1)
            bisect.insort(self.asset_ids, asset_id)
            return asset_id
        except Exception as e:
            raise Exception(f"Failed to add synthetic asset {asset_id}: {e}")

    async def add_oracle_to_asset(
        self, asset_id: int, oracle_public_key: int, oracle_name: int, asset_name: int
    ):
        invocation = await self.app_governor_contract.functions["add_oracle_to_asset"].invoke_v3(
            formatted_asset_id(asset_id),
            oracle_public_key,
            oracle_name,
            asset_name,
            auto_estimate=True,
        )
        await invocation.wait_for_acceptance(check_interval=0.1)

    async def funding_tick(self, funding_ticks_diffs: dict):
        FUNDING_INDEX_STR = "funding_index"
        FUNDING_INDEX_VALUE_STR = "value"
        ASSET_ID_STR = "asset_id"

        # Get all funding indices
        async def _get_all_funding_indices() -> Dict[int, int]:
            async def fetch_funding_index(asset_id: int) -> Tuple[int, Optional[int]]:
                try:
                    timely_data = await self.get_asset_timely_data(asset_id)
                    funding_index_value = timely_data[FUNDING_INDEX_STR][FUNDING_INDEX_VALUE_STR]
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
        invocation = await self.operator_contract.functions["funding_tick"].invoke_v3(
            await self.get_operator_nonce(),
            new_funding_indices,
            formatted_timestamp(NOW),
            auto_estimate=True,
        )
        await invocation.wait_for_acceptance(check_interval=0.1)
