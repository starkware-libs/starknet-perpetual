use core::num::traits::Pow;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::{SyntheticAsset, SyntheticDiffEnriched};
use perpetuals::core::types::balance::{Balance, BalanceDiff};
use perpetuals::core::types::funding::{Felt252TryIntoFundingIndex, FundingIndex};
use starknet::storage::{Mutable, StoragePath, StoragePointerReadAccess};
use starknet::storage_access::{
    StorageBaseAddress, Store, storage_address_from_base, storage_address_from_base_and_offset,
};
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
use starknet::{ContractAddress, SyscallResult};
use starkware_utils::signature::stark::PublicKey;
use starkware_utils::storage::iterable_map::{
    IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
};


pub const POSITION_VERSION: u8 = 2;
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
    pub synthetic_balance: IterableMap<AssetId, SyntheticBalance>,
}

/// Synthetic asset in a position.
/// - balance: The amount of the synthetic asset held in the position.
/// - funding_index: The funding index at the time of the last update.
#[derive(Copy, Drop, Serde)]
pub struct SyntheticBalance {
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

fn pack(value: SyntheticBalance) -> felt252 {
    let version: felt252 = value.version.into();
    let balance: i64 = value.balance.into();
    let funding_index: i64 = value.funding_index.value;
    version
        + TWO_POW_8.into() * i64_to_u64_as_felt(balance)
        + TWO_POW_72.into() * i64_to_u64_as_felt(funding_index)
}

fn unpack(value: felt252) -> SyntheticBalance {
    let u256 { low, high } = value.into();

    let version: u8 = (low & MASK_8.into()).try_into().unwrap();
    let balance: i64 = u64_as_felt_to_i64((low / TWO_POW_8.into() & MASK_64.into()).into());
    let x = (low / TWO_POW_72.into()) + (high * TWO_POW_56.into());
    let funding_index: i64 = u64_as_felt_to_i64((x & MASK_64.into()).into());

    SyntheticBalance {
        version: version,
        balance: balance.into(),
        funding_index: FundingIndex { value: funding_index },
    }
}

impl StoreSyntheticBalance of Store<SyntheticBalance> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<SyntheticBalance> {
        let result = storage_read_syscall(address_domain, storage_address_from_base(base))?;
        let return_value: SyscallResult<SyntheticBalance> = if result == 1 {
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
                    SyntheticBalance { version: 1, balance: balance, funding_index: funding_index },
                )
            }
        } else {
            Ok(unpack(result))
        };
        return_value
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: SyntheticBalance,
    ) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base(base), pack(value))
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<SyntheticBalance> {
        let result = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset),
        )?;
        let return_value: SyscallResult<SyntheticBalance> = if result == 1 {
            let option_balance = storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 1),
            )?;

            let option_funding_index = storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 2),
            )?;

            let balance: Option<Balance> = option_balance.try_into();
            let funding_index: Option<FundingIndex> = option_funding_index.try_into();

            if balance.is_none() || funding_index.is_none() {
                SyscallResult::Err(array!['asdf'])
            } else {
                let balance = balance.unwrap();
                let funding_index = funding_index.unwrap();
                SyscallResult::Ok(
                    SyntheticBalance { version: 1, balance: balance, funding_index: funding_index },
                )
            }
        } else {
            Ok(unpack(result))
        };
        return_value
    }


    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: SyntheticBalance,
    ) -> SyscallResult<()> {
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset), pack(value),
        )
    }

    fn size() -> u8 {
        1_u8
    }
}

#[derive(Copy, Debug, Drop, Hash, PartialEq, Serde)]
pub struct PositionId {
    pub value: u32,
}

#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiff {
    pub collateral_diff: Balance,
    pub synthetic_diff: Option<(AssetId, Balance)>,
}

#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiffEnriched {
    pub collateral_enriched: BalanceDiff,
    pub synthetic_enriched: Option<SyntheticDiffEnriched>,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionData {
    pub synthetics: Span<SyntheticAsset>,
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
