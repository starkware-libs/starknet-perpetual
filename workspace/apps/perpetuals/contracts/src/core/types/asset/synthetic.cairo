use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactor;
use starkware_utils::time::time::Timestamp;


const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub enum AssetType {
    #[default]
    SYNTHETIC,
    SPOT_COLLATERAL,
    VAULT_SHARE_COLLATERAL
}

#[derive(Copy, Drop, Serde, starknet::Store)]
// probably need to change name to AssetConfig or something similar as it will be used also for non
// PnL collateral assets
pub struct AssetConfig {
    pub version: u8,
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

// this is for non PnL collateral assets (or maybe use the SyntheticTimelyData struct for all assets
// but zero for funding_index for non PnL collateral assets)
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralTimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticTimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
}

// change name to Asset as it will be used for all assets
#[derive(Copy, Debug, Drop, Serde, PartialEq)]
pub struct SyntheticAsset {
    // we need to have a mapping between AssetId and the corresponding ContractAddress of the
    // underlying token in case of collateral assets (or just use the id as the ContractAddress)
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
    ) -> AssetConfig {
        AssetConfig {
            version: VERSION,
            status,
            risk_factor_first_tier_boundary,
            risk_factor_tier_size,
            quorum,
            resolution_factor,
            quantum: 0,
            asset_type: AssetType::SYNTHETIC,
        }
    }
    fn timely_data(
        price: Price, last_price_update: Timestamp, funding_index: FundingIndex,
    ) -> SyntheticTimelyData {
        SyntheticTimelyData { version: VERSION, price, last_price_update, funding_index }
    }
}
