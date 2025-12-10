use core::num::traits::Pow;
use core::num::traits::Zero;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::{AssetBalanceDiffEnriched, AssetBalanceInfo};
use perpetuals::core::types::balance::{Balance, BalanceDiff};
use starknet::storage::{Mutable, StoragePath, StoragePointerReadAccess};
use starkware_utils::signature::stark::PublicKey;
use starkware_utils::storage::iterable_map::{
    IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
};
use starknet::storage_access::{
    StorageBaseAddress, Store, storage_address_from_base, storage_address_from_base_and_offset,
};
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
use starknet::{ContractAddress, SyscallResult};
use perpetuals::core::types::funding::{Felt252TryIntoFundingIndex, FundingIndex};



pub const POSITION_VERSION: u8 = 1;
pub const TWO_POW_64: u128 = 2_u128.pow(64);
pub const TWO_POW_72: u128 = 2_u128.pow(72);

pub const TWO_POW_63: u64 = 2_u64.pow(63);
pub const TWO_POW_8: u64 = 2_u64.pow(8);
pub const TWO_POW_56: u64 = 2_u64.pow(56);


const TWO_POW_40: u128 = 0x10000000000;

const MASK_8: u128 = 0xff;
const MASK_32: u128 = 0xffffffff;
const MASK_64: u128 = 0xffffffffffffffff;



#[starknet::storage_node]
pub struct Position {
    pub version: u8,
    pub owner_account: Option<ContractAddress>,
    pub owner_public_key: PublicKey,
    pub collateral_balance: Balance,
    #[rename("synthetic_balance")]
    pub asset_balances: IterableMap<AssetId, AssetBalance>,
    pub owner_protection_enabled: bool,
}

/// Synthetic asset in a position.
/// - balance: The amount of the synthetic asset held in the position.
/// - funding_index: The funding index at the time of the last update.
#[derive(Copy, Drop, Serde)]
pub struct AssetBalance {
    pub version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
}


fn u64_as_felt_to_i64(value: felt252) -> i64 {
    let x: felt252 = value - TWO_POW_63.into();
    x.try_into().unwrap()
}

fn i64_to_u64_as_felt(value: i64) -> felt252 {
    value.into() + TWO_POW_63.into()
}

fn pack(value: AssetBalance) -> felt252 {
    let version: felt252 = value.version.into();
    let balance: i64 = value.balance.into();
    let funding_index: i64 = value.funding_index.value;
    version
        + TWO_POW_8.into() * i64_to_u64_as_felt(balance)
        + TWO_POW_72.into() * i64_to_u64_as_felt(funding_index)
}

fn unpack(value: felt252) -> AssetBalance {
    let u256 { low, high } = value.into();

    let version: u8 = (low & MASK_8.into()).try_into().unwrap();
    let balance: i64 = u64_as_felt_to_i64((low / TWO_POW_8.into() & MASK_64.into()).into());
    let x = (low / TWO_POW_72.into()) + (high * TWO_POW_56.into());
    let funding_index: i64 = u64_as_felt_to_i64((x & MASK_64.into()).into());

    AssetBalance {
        version: version,
        balance: balance.into(),
        funding_index: FundingIndex { value: funding_index },
    }
}


impl StoreAssetBalance of Store<AssetBalance> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<AssetBalance> {
        let result = storage_read_syscall(address_domain, storage_address_from_base(base))?;
        let return_value: SyscallResult<AssetBalance> = if result == 1 {
            let option_balance = storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 1),
            )?;

            let option_funding_index = storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 2),
            )?;

            let balance: Option<Balance> = option_balance.try_into();
            let funding_index: Option<FundingIndex> = option_funding_index.try_into();

            if balance.is_none() || funding_index.is_none() {
                SyscallResult::Err(array!['asdf'])
            } else {
                let balance = balance.unwrap();
                let funding_index = funding_index.unwrap();
                SyscallResult::Ok(
                    AssetBalance { version: 1, balance: balance, funding_index: funding_index },
                )
            }
        } else {
            Ok(unpack(result))
        };
        return_value
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: AssetBalance,
    ) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base(base), pack(value))
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<AssetBalance> {
        let result = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset),
        )?;
        let return_value: SyscallResult<AssetBalance> = if result == 1 {
            let option_balance = storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 1),
            )?;

            let option_funding_index = storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 2),
            )?;

            let balance: Option<Balance> = option_balance.try_into();
            let funding_index: Option<FundingIndex> = option_funding_index.try_into();

            if balance.is_none() || funding_index.is_none() {
                SyscallResult::Err(array![''])
            } else {
                let balance = balance.unwrap();
                let funding_index = funding_index.unwrap();
                SyscallResult::Ok(
                    AssetBalance { version: 1, balance: balance, funding_index: funding_index },
                )
            }
        } else {
            Ok(unpack(result))
        };
        return_value
    }


    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: AssetBalance,
    ) -> SyscallResult<()> {
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset), pack(value),
        )
    }

    fn size() -> u8 {
        1_u8
    }
}




pub impl AssetBalanceZeroImpl of Zero<AssetBalance> {
    fn zero() -> AssetBalance {
        AssetBalance {
            version: POSITION_VERSION, balance: Zero::zero(), funding_index: Zero::zero(),
        }
    }
    fn is_zero(self: @AssetBalance) -> bool {
        self.balance.is_zero()
    }
    fn is_non_zero(self: @AssetBalance) -> bool {
        !self.is_zero()
    }
}

pub impl AssetBalanceDefault of Default<AssetBalance> {
    fn default() -> AssetBalance {
        Zero::zero()
    }
}

#[derive(Copy, Debug, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct PositionId {
    pub value: u32,
}

pub impl PositionIdZeroImpl of Zero<PositionId> {
    fn zero() -> PositionId {
        PositionId { value: 0 }
    }
    fn is_zero(self: @PositionId) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @PositionId) -> bool {
        self.value.is_non_zero()
    }
}

/// Diff where both collateral and synthetic are raw (not enriched).
#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiff {
    pub collateral_diff: Balance,
    pub asset_diff: Option<(AssetId, Balance)>,
}

/// Diff where synthetic is enriched but collateral is still raw.
#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct AssetEnrichedPositionDiff {
    pub collateral_diff: Balance,
    pub asset_diff_enriched: Option<AssetBalanceDiffEnriched>,
}

/// Diff where both collateral and synthetic are enriched.
#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiffEnriched {
    pub collateral_enriched: BalanceDiff,
    pub asset_diff_enriched: Option<AssetBalanceDiffEnriched>,
}

pub impl PositionDiffEnrichedIntoSyntheticEnrichedPositionDiff of Into<
    PositionDiffEnriched, AssetEnrichedPositionDiff,
> {
    fn into(self: PositionDiffEnriched) -> AssetEnrichedPositionDiff {
        AssetEnrichedPositionDiff {
            collateral_diff: self.collateral_enriched.after - self.collateral_enriched.before,
            asset_diff_enriched: self.asset_diff_enriched,
        }
    }
}

#[derive(Copy, Debug, Drop, Serde, PartialEq)]
pub struct PositionData {
    pub assets: Span<AssetBalanceInfo>,
    pub collateral_balance: Balance,
}


pub impl U32IntoPositionId of Into<u32, PositionId> {
    fn into(self: u32) -> PositionId {
        PositionId { value: self }
    }
}

pub impl PositionIdIntoU32 of Into<PositionId, u32> {
    fn into(self: PositionId) -> u32 {
        self.value
    }
}

#[generate_trait]
pub impl PositionImpl of PositionTrait {
    fn get_owner_account(self: StoragePath<Position>) -> Option<ContractAddress> {
        self.owner_account.read()
    }

    fn get_owner_public_key(self: StoragePath<Position>) -> PublicKey {
        self.owner_public_key.read()
    }
    fn get_version(self: StoragePath<Position>) -> u8 {
        self.version.read()
    }
}

#[generate_trait]
pub impl PositionMutableImpl of PositionMutableTrait {
    fn get_owner_account(self: StoragePath<Mutable<Position>>) -> Option<ContractAddress> {
        self.owner_account.read()
    }

    fn get_owner_public_key(self: StoragePath<Mutable<Position>>) -> PublicKey {
        self.owner_public_key.read()
    }
    fn get_version(self: StoragePath<Mutable<Position>>) -> u8 {
        self.version.read()
    }
}
