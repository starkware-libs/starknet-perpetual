use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactor;
use starknet::ContractAddress;
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
}
