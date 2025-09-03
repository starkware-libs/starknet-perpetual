use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactor;
use starkware_utils::time::time::Timestamp;


const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticConfig {
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
pub struct SyntheticTimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
}

#[derive(Copy, Debug, Drop, Serde, PartialEq)]
pub struct SyntheticAsset {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
    pub risk_factor: RiskFactor,
}

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct SyntheticDiffEnriched {
    pub asset_id: AssetId,
    pub balance_before: Balance,
    pub balance_after: Balance,
    pub price: Price,
    pub risk_factor_before: RiskFactor,
    pub risk_factor_after: RiskFactor,
}

#[generate_trait]
pub impl SyntheticImpl of SyntheticTrait {
    fn config(
        status: AssetStatus,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
    ) -> SyntheticConfig {
        SyntheticConfig {
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
    ) -> SyntheticTimelyData {
        SyntheticTimelyData { version: VERSION, price, last_price_update, funding_index }
    }
}
