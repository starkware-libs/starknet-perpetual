use core::num::traits::Zero;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::{AssetBalanceDiffEnriched, AssetBalanceInfo};
use perpetuals::core::types::balance::{Balance, BalanceDiff};
use perpetuals::core::types::funding::FundingIndex;
use starknet::storage::{Mutable, StoragePath, StoragePointer0Offset, StoragePointerReadAccess};
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::syscalls::storage_read_syscall;
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_utils::signature::stark::PublicKey;
use starkware_utils::storage::iterable_map::{
    IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
};


pub const POSITION_VERSION: u8 = 1;

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
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct AssetBalance {
    pub version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
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

#[generate_trait]
pub impl OptionAssetBalanceReadAccessImpl of OptionAssetBalanceReadAccessTrait {
    /// Reads the Option<AssetBalance> from the storage.
    /// The offset is used to read specific fields of the struct.
    #[inline]
    fn read(
        entry: StoragePointer0Offset<Option<AssetBalance>>, offset: OptionAssetBalanceOffset,
    ) -> felt252 {
        storage_read_syscall(
            0,
            storage_address_from_base_and_offset(entry.__storage_pointer_address__, offset.into()),
        )
            .unwrap_syscall()
    }

    /// Reads the variant of the Option<AssetBalance>.
    /// The variant mark if the Option is Some or None.
    #[inline]
    fn read_variant(entry: StoragePointer0Offset<Option<AssetBalance>>) -> felt252 {
        Self::read(entry, OptionAssetBalanceOffset::VARIANT)
    }

    /// Returns true if the Option is Some, false if None.
    /// At the storage 0 indicates None, 1 indicates Some.
    #[inline]
    fn is_some(entry: StoragePointer0Offset<Option<AssetBalance>>) -> bool {
        let variant = Self::read_variant(entry);
        variant == 1
    }

    /// Returns true if the Option is None, false if Some.
    /// At the storage 0 indicates None, 1 indicates Some.
    #[inline]
    fn is_none(entry: StoragePointer0Offset<Option<AssetBalance>>) -> bool {
        let variant = Self::read_variant(entry);
        variant == 0
    }

    /// Reads the funding index from the Option<AssetBalance>.
    /// This function does not check if the Option is Some or None.
    fn at_funding_index(entry: StoragePointer0Offset<Option<AssetBalance>>) -> FundingIndex {
        let funding_index = Self::read(entry, OptionAssetBalanceOffset::FUNDING_INDEX);
        let funding_index: i64 = funding_index.try_into().unwrap();
        funding_index.into()
    }

    /// Gets the funding index from the Option<AssetBalance>.
    /// Returns None if the Option is None.
    fn get_funding_index(
        entry: StoragePointer0Offset<Option<AssetBalance>>,
    ) -> Option<FundingIndex> {
        if Self::is_none(entry) {
            return Option::None;
        }
        Option::Some(Self::at_funding_index(entry))
    }

    /// Reads the balance from the Option<AssetBalance>.
    /// This function does not check if the Option is Some or None.
    fn at_balance(entry: StoragePointer0Offset<Option<AssetBalance>>) -> Balance {
        let balance = Self::read(entry, OptionAssetBalanceOffset::BALANCE);
        let balance: i64 = balance.try_into().unwrap();
        balance.into()
    }

    /// Gets the balance from the Option<AssetBalance>.
    /// Returns None if the Option is None.
    fn get_balance(entry: StoragePointer0Offset<Option<AssetBalance>>) -> Option<Balance> {
        if Self::is_none(entry) {
            return Option::None;
        }
        Option::Some(Self::at_balance(entry))
    }

    /// Reads the version from the Option<AssetBalance>.
    /// This function does not check if the Option is Some or None.
    fn at_version(entry: StoragePointer0Offset<Option<AssetBalance>>) -> u8 {
        let version = Self::read(entry, OptionAssetBalanceOffset::VERSION);
        let version: u8 = version.try_into().unwrap();
        version
    }

    /// Gets the version from the Option<AssetBalance>.
    /// Returns None if the Option is None.
    fn get_version(entry: StoragePointer0Offset<Option<AssetBalance>>) -> Option<u8> {
        if Self::is_none(entry) {
            return Option::None;
        }
        Option::Some(Self::at_version(entry))
    }
}

/// In the storage, the Option<AssetBalance> is stored as a struct with the following layout:
/// - variant: u8 (1 for Some, 0 for None)
/// - version: u8
/// - balance: i64
/// - funding_index: i64
/// The offsets are used to read specific fields of the struct.
#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum OptionAssetBalanceOffset {
    VARIANT,
    VERSION,
    BALANCE,
    FUNDING_INDEX,
}


/// Convert the enum to u8 for storage access.
pub impl OptionAssetBalanceOffsetIntoU8 of Into<OptionAssetBalanceOffset, u8> {
    fn into(self: OptionAssetBalanceOffset) -> u8 {
        match self {
            OptionAssetBalanceOffset::VARIANT => 0_u8,
            OptionAssetBalanceOffset::VERSION => 1_u8,
            OptionAssetBalanceOffset::BALANCE => 2_u8,
            OptionAssetBalanceOffset::FUNDING_INDEX => 3_u8,
        }
    }
}
