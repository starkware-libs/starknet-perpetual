use core::num::traits::zero::Zero;
use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactor;
use starknet::storage::StoragePointer0Offset;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::syscalls::storage_read_syscall;
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_utils::time::time::Timestamp;


const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub enum AssetType {
    #[default]
    SYNTHETIC,
    SPOT_COLLATERAL,
    VAULT_SHARE_COLLATERAL,
}

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
    pub quantum: u64,
    pub token_contract: Option<ContractAddress>,
    pub asset_type: AssetType,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct TimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
}

impl TimelyDataDefault of Default<TimelyData> {
    fn default() -> TimelyData {
        TimelyData {
            version: VERSION,
            price: Zero::zero(),
            last_price_update: Zero::zero(),
            funding_index: Zero::zero(),
        }
    }
}

#[derive(Copy, Debug, Drop, Serde, PartialEq)]
pub struct AssetBalanceInfo {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
    pub risk_factor: RiskFactor,
    pub cached_funding_index: FundingIndex,
}

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct AssetBalanceDiffEnriched {
    pub asset_id: AssetId,
    pub balance_before: Balance,
    pub balance_after: Balance,
    pub price: Price,
    pub risk_factor_before: RiskFactor,
    pub risk_factor_after: RiskFactor,
}

#[generate_trait]
pub impl SyntheticImpl of SyntheticTrait {
    fn synthetic(
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
            quantum: 0,
            token_contract: None,
            asset_type: AssetType::SYNTHETIC,
        }
    }

    fn spot(
        status: AssetStatus,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
        quantum: u64,
        token_contract: ContractAddress,
    ) -> AssetConfig {
        AssetConfig {
            version: VERSION,
            status,
            risk_factor_first_tier_boundary,
            risk_factor_tier_size,
            quorum,
            resolution_factor,
            quantum: quantum,
            token_contract: Some(token_contract),
            asset_type: AssetType::SPOT_COLLATERAL,
        }
    }

    fn vault_share(
        status: AssetStatus,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
        quantum: u64,
        token_contract: ContractAddress,
    ) -> AssetConfig {
        AssetConfig {
            version: VERSION,
            status,
            risk_factor_first_tier_boundary,
            risk_factor_tier_size,
            quorum,
            resolution_factor,
            quantum: quantum,
            token_contract: Some(token_contract),
            asset_type: AssetType::VAULT_SHARE_COLLATERAL,
        }
    }

    fn timely_data(
        price: Price, last_price_update: Timestamp, funding_index: FundingIndex,
    ) -> TimelyData {
        TimelyData { version: VERSION, price, last_price_update, funding_index }
    }

    /// Reads the price from the Option<AssetTimelyData>.
    /// This function does not check if the Option is Some or None.
    fn at_price(entry: StoragePointer0Offset<Option<TimelyData>>) -> Price {
        let price = Self::read(entry, OptionTimelyDataOffset::PRICE);
        let price: u64 = price.try_into().unwrap();
        price.into()
    }

    /// Reads the funding index from the Option<TimelyData>.
    /// This function does not check if the Option is Some or None.
    fn at_funding_index(entry: StoragePointer0Offset<Option<TimelyData>>) -> FundingIndex {
        let funding_index = Self::read(entry, OptionTimelyDataOffset::FUNDING_INDEX);
        let funding_index: i64 = funding_index.try_into().unwrap();
        funding_index.into()
    }

    /// Reads the Option<AssetTimelyData> from the storage.
    /// The offset is used to read specific fields of the struct.
    #[inline]
    fn read(
        entry: StoragePointer0Offset<Option<TimelyData>>, offset: OptionTimelyDataOffset,
    ) -> felt252 {
        storage_read_syscall(
            0,
            storage_address_from_base_and_offset(entry.__storage_pointer_address__, offset.into()),
        )
            .unwrap_syscall()
    }
}


/// In the storage, the Option<TimelyData> is stored as a struct with the following layout:
/// - variant: u8 (1 for Some, 0 for None)
/// - version: u8
/// - price: u64
/// - last_price_update: u64
/// - funding_index: i64
/// The offsets are used to read specific fields of the struct.
#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum OptionTimelyDataOffset {
    VARIANT,
    VERSION,
    PRICE,
    LAST_PRICE_UPDATE,
    FUNDING_INDEX,
}

/// Convert the enum to u8 for storage access.
pub impl OptionTimelyDataOffsetIntoU8 of Into<OptionTimelyDataOffset, u8> {
    fn into(self: OptionTimelyDataOffset) -> u8 {
        match self {
            OptionTimelyDataOffset::VARIANT => 0_u8,
            OptionTimelyDataOffset::VERSION => 1_u8,
            OptionTimelyDataOffset::PRICE => 2_u8,
            OptionTimelyDataOffset::LAST_PRICE_UPDATE => 3_u8,
            OptionTimelyDataOffset::FUNDING_INDEX => 4_u8,
        }
    }
}

#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum OptionAssetConfigOffset {
    VARIANT,
    VERSION,
    STATUS,
    RISK_FACTOR_FIRST_TIER_BOUNDARY,
    RISK_FACTOR_TIER_SIZE,
    QUORUM,
    RESOLUTION_FACTOR,
    QUANTUM,
    TOKEN_CONTRACT,
    ASSET_TYPE,
}

pub impl OptionAssetConfigOffsetIntoU8 of Into<OptionAssetConfigOffset, u8> {
    fn into(self: OptionAssetConfigOffset) -> u8 {
        match self {
            OptionAssetConfigOffset::VARIANT => 0_u8,
            OptionAssetConfigOffset::VERSION => 1_u8,
            OptionAssetConfigOffset::STATUS => 2_u8,
            OptionAssetConfigOffset::RISK_FACTOR_FIRST_TIER_BOUNDARY => 3_u8,
            OptionAssetConfigOffset::RISK_FACTOR_TIER_SIZE => 4_u8,
            OptionAssetConfigOffset::QUORUM => 5_u8,
            OptionAssetConfigOffset::RESOLUTION_FACTOR => 6_u8,
            OptionAssetConfigOffset::QUANTUM => 7_u8,
            OptionAssetConfigOffset::TOKEN_CONTRACT => 8_u8,
            OptionAssetConfigOffset::ASSET_TYPE => 9_u8,
        }
    }
}
