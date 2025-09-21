use core::num::traits::zero::Zero;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactor;
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

#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum AssetType {
    #[default]
    SYNTHETIC,
    SPOT_COLLATERAL,
    VAULT_SHARE_COLLATERAL,
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
    pub quantum: u64,
    pub asset_type: AssetType,
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
        quantum: u64,
        asset_type: AssetType,
    ) -> AssetConfig {
        AssetConfig {
            version: VERSION,
            status,
            risk_factor_first_tier_boundary,
            risk_factor_tier_size,
            quorum,
            resolution_factor,
            quantum,
            asset_type,
        }
    }
    fn timely_data(
        price: Price, last_price_update: Timestamp, funding_index: FundingIndex,
    ) -> AssetTimelyData {
        AssetTimelyData { version: VERSION, price, last_price_update, funding_index }
    }
}
