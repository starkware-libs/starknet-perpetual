use core::num::traits::Zero;
use perpetuals::core::types::asset::synthetic::{AssetBalanceDiffEnriched, AssetBalanceInfo};
use perpetuals::core::types::asset::{AssetId, AssetIdFelt};
use perpetuals::core::types::balance::{Balance, BalanceDiff};
use perpetuals::core::types::funding::FundingIndex;
use starknet::ContractAddress;
use starknet::storage::{Mutable, StoragePath, StoragePointerReadAccess};
use starkware_utils::signature::stark::PublicKey;
use starkware_utils::storage::iterable_map::{
    IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
};
use starkware_utils::storage::linked_iterable_map_felt::LinkedIterableMapFelt;
use starkware_utils::storage::utils::{Castable160, Castable64};
use starkware_utils::time::time::Timestamp;

pub const POSITION_VERSION: u8 = 1;

#[starknet::storage_node]
pub struct Position {
    pub version: u8,
    pub owner_account: Option<ContractAddress>,
    pub owner_public_key: PublicKey,
    pub collateral_balance: Balance,
    #[rename("synthetic_balance")]
    pub asset_balances: IterableMap<AssetId, AssetBalance>,
    pub spot_balances: LinkedIterableMapFelt<AssetId, SpotBalance>,
    pub owner_protection_enabled: bool,
    pub last_interest_applied_time: Timestamp,
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


#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SpotBalance {
    pub version: u8,
    pub balance: Balance,
}

pub impl SpotBalanceZeroImpl of Zero<SpotBalance> {
    fn zero() -> SpotBalance {
        SpotBalance { version: POSITION_VERSION, balance: Zero::zero() }
    }
    fn is_zero(self: @SpotBalance) -> bool {
        self.balance.is_zero()
    }
    fn is_non_zero(self: @SpotBalance) -> bool {
        !self.is_zero()
    }
}

pub impl SpotBalanceDefault of Default<SpotBalance> {
    fn default() -> SpotBalance {
        Zero::zero()
    }
}

pub impl Castable160SpotBalance of Castable160<SpotBalance> {
    fn encode(value: SpotBalance) -> (u128, u32) {
        (Castable64::encode(value.balance).into(), value.version.into())
    }

    fn decode(value: (u128, u32)) -> SpotBalance {
        let (balance, version) = value;
        let balance_u64: u64 = balance.try_into().unwrap();
        let version_u8: u8 = version.try_into().unwrap();
        SpotBalance { balance: Castable64::decode(balance_u64), version: version_u8 }
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
