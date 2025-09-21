use core::num::traits::zero::Zero;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactor;
use starknet::SyscallResultTrait;
use starknet::storage::StoragePointer0Offset;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::syscalls::storage_read_syscall;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct AssetId {
    value: felt252,
}

#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum AssetStatus {
    #[default]
    PENDING,
    ACTIVE,
    INACTIVE,
}

#[generate_trait]
pub impl AssetIdImpl of AssetIdTrait {
    fn new(value: felt252) -> AssetId {
        AssetId { value }
    }

    fn value(self: @AssetId) -> felt252 {
        *self.value
    }
}

pub impl FeltIntoAssetId of Into<felt252, AssetId> {
    fn into(self: felt252) -> AssetId {
        AssetId { value: self }
    }
}

pub impl AssetIdIntoFelt of Into<AssetId, felt252> {
    fn into(self: AssetId) -> felt252 {
        self.value
    }
}

impl AssetIdZero of Zero<AssetId> {
    fn zero() -> AssetId {
        AssetId { value: 0 }
    }
    fn is_zero(self: @AssetId) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @AssetId) -> bool {
        self.value.is_non_zero()
    }
}

impl AssetIdlOrd of PartialOrd<AssetId> {
    fn lt(lhs: AssetId, rhs: AssetId) -> bool {
        let l: u256 = lhs.value.into();
        let r: u256 = rhs.value.into();
        l < r
    }
}

const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct AssetConfig {
    version: u8,
    // Configurable
    pub status: AssetStatus,
    pub risk_factor_first_tier_boundary: u128,
    pub risk_factor_tier_size: u128,
    pub quorum: u8,
    // Smallest unit of a synthetic asset in the system.
    pub resolution_factor: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct AssetTimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
}

#[derive(Copy, Debug, Drop, Serde, PartialEq)]
pub struct Asset {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
    pub risk_factor: RiskFactor,
}

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct AssetDiffEnriched {
    pub asset_id: AssetId,
    pub balance_before: Balance,
    pub balance_after: Balance,
    pub price: Price,
    pub risk_factor_before: RiskFactor,
    pub risk_factor_after: RiskFactor,
}

#[generate_trait]
pub impl AssetImpl of AssetTrait {
    fn config(
        status: AssetStatus,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
    ) -> AssetConfig {
        AssetConfig {
            version: VERSION,
            status,
            risk_factor_first_tier_boundary,
            risk_factor_tier_size,
            quorum,
            resolution_factor,
        }
    }
    fn timely_data(
        price: Price, last_price_update: Timestamp, funding_index: FundingIndex,
    ) -> AssetTimelyData {
        AssetTimelyData { version: VERSION, price, last_price_update, funding_index }
    }


    /// Reads the Option<AssetTimelyData> from the storage.
    /// The offset is used to read specific fields of the struct.
    #[inline]
    fn read(
        entry: StoragePointer0Offset<Option<AssetTimelyData>>, offset: OptionAssetTimelyDataOffset,
    ) -> felt252 {
        storage_read_syscall(
            0,
            storage_address_from_base_and_offset(entry.__storage_pointer_address__, offset.into()),
        )
            .unwrap_syscall()
    }

    /// Reads the variant of the Option<AssetTimelyData>.
    /// The variant mark if the Option is Some or None.
    #[inline]
    fn read_variant(entry: StoragePointer0Offset<Option<AssetTimelyData>>) -> felt252 {
        Self::read(entry, OptionAssetTimelyDataOffset::VARIANT)
    }

    /// Returns true if the Option is Some, false if None.
    /// At the storage 1 indicates Some, 2 indicates None.
    #[inline]
    fn is_some(entry: StoragePointer0Offset<Option<AssetTimelyData>>) -> bool {
        let variant = Self::read_variant(entry);
        variant == 1
    }

    /// Returns true if the Option is None, false if Some.
    /// At the storage 1 indicates Some, 2 indicates None.
    #[inline]
    fn is_none(entry: StoragePointer0Offset<Option<AssetTimelyData>>) -> bool {
        let variant = Self::read_variant(entry);
        variant == 2
    }

    /// Reads the price from the Option<AssetTimelyData>.
    /// This function does not check if the Option is Some or None.
    fn at_price(entry: StoragePointer0Offset<Option<AssetTimelyData>>) -> Price {
        let price = Self::read(entry, OptionAssetTimelyDataOffset::PRICE);
        let price: u64 = price.try_into().unwrap();
        price.into()
    }

    /// Reads the funding index from the Option<AssetTimelyData>.
    /// This function does not check if the Option is Some or None.
    fn at_funding_index(entry: StoragePointer0Offset<Option<AssetTimelyData>>) -> FundingIndex {
        let funding_index = Self::read(entry, OptionAssetTimelyDataOffset::FUNDING_INDEX);
        let funding_index: i64 = funding_index.try_into().unwrap();
        funding_index.into()
    }

    /// Gets the price from the Option<AssetTimelyData>.
    /// Returns None if the Option is None.
    fn get_price(entry: StoragePointer0Offset<Option<AssetTimelyData>>) -> Option<Price> {
        if Self::is_none(entry) {
            return Option::None;
        }
        Option::Some(Self::at_price(entry))
    }

    /// Gets the funding index from the Option<AssetTimelyData>.
    /// Returns None if the Option is None.
    fn get_funding_index(
        entry: StoragePointer0Offset<Option<AssetTimelyData>>,
    ) -> Option<FundingIndex> {
        if Self::is_none(entry) {
            return Option::None;
        }
        Option::Some(Self::at_funding_index(entry))
    }
}


/// In the storage, the Option<AssetTimelyData> is stored as a struct with the following layout:
/// - variant: u8 (1 for Some, 2 for None)
/// - version: u8
/// - price: u64
/// - last_price_update: u64
/// - funding_index: i64
/// The offsets are used to read specific fields of the struct.
#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum OptionAssetTimelyDataOffset {
    VARIANT,
    VERSION,
    PRICE,
    LAST_PRICE_UPDATE,
    FUNDING_INDEX,
}

/// Convert the enum to u8 for storage access.
pub impl OptionAssetTimelyDataOffsetIntoU8 of Into<OptionAssetTimelyDataOffset, u8> {
    fn into(self: OptionAssetTimelyDataOffset) -> u8 {
        match self {
            OptionAssetTimelyDataOffset::VARIANT => 0_u8,
            OptionAssetTimelyDataOffset::VERSION => 1_u8,
            OptionAssetTimelyDataOffset::PRICE => 2_u8,
            OptionAssetTimelyDataOffset::LAST_PRICE_UPDATE => 3_u8,
            OptionAssetTimelyDataOffset::FUNDING_INDEX => 4_u8,
        }
    }
}
