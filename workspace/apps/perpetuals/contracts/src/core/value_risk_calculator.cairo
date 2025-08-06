use core::num::traits::{One, Zero};
use core::panics::panic_with_byte_array;
use perpetuals::core::errors::{
    position_not_deleveragable, position_not_fair_deleverage, position_not_healthy_nor_healthier,
    position_not_liquidatable,
};
use perpetuals::core::types::asset::synthetic::SyntheticAsset;
use perpetuals::core::types::balance::{Balance, BalanceDiff};
use perpetuals::core::types::position::{PositionDiffEnriched, PositionId};
use perpetuals::core::types::price::{AssetValue, Price, PriceMulTrait};
use perpetuals::core::types::risk_factor::{AssetRisk, RiskFactorMulTrait, RiskFactorTrait};
use starkware_utils::errors::assert_with_byte_array;
use starkware_utils::math::abs::Abs;
use starkware_utils::math::fraction::FractionTrait;

// This is the result of Price::One().mul(balance: 1)
// which is actually 1e-6 USDC * 2^28 / 2^28 = 1
// aka the smallest unit of value we can have in Perps.
const EPSILON: i128 = 1_i128;




/// Represents the state of a position based on its total value and total risk.
/// - A position is **Deleveragable** (and also **Liquidatable**) if its total value is negative.
/// - A position is **Liquidatable** if its total value is less than its total risk.
/// - Otherwise, the position is considered **Healthy**.clear
#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum PositionState {
    Healthy,
    Liquidatable,
    Deleveragable,
}

/// The total value and total risk of a position.
#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionTVTR {
    pub total_value: i128,
    pub total_risk: u128,
}

/// The change in terms of total value and total risk of a position.
#[derive(Copy, Debug, Drop, Serde)]
pub struct TVTRChange {
    pub before: PositionTVTR,
    pub after: PositionTVTR,
}


/// Returns the state of a position based on its total value and total risk.
fn get_position_state(position_tvtr: PositionTVTR) -> PositionState {
    if position_tvtr.total_value < 0 {
        PositionState::Deleveragable
    } else if position_tvtr.total_value.abs() < position_tvtr.total_risk {
        // We apply abs() to total_value to be able to compare it with total_risk which is unsigned.
        // At this point, we've already ensured total_value is >= 0.
        PositionState::Liquidatable
    } else {
        PositionState::Healthy
    }
}

/// The position is fair if the total_value divided by the total_risk is the almost before and after
/// the change - the before_ratio needs to be between after_ratio-epsilon and after ratio.
fn is_fair_deleverage(before: PositionTVTR, after: PositionTVTR) -> bool {
    if after.total_risk == 0 {
        return after.total_value == 0;
    }
    let before_ratio = FractionTrait::new(
        numerator: before.total_value, denominator: before.total_risk,
    );
    let after_ratio = FractionTrait::new(
        numerator: after.total_value, denominator: after.total_risk,
    );
    let after_minus_epsilon_ratio = FractionTrait::new(
        numerator: after.total_value - EPSILON, denominator: after.total_risk,
    );
    after_minus_epsilon_ratio <= before_ratio && before_ratio <= after_ratio
}

/// Returns the state of a position.
pub fn evaluate_position(
    unchanged_synthetics: Span<SyntheticAsset>, collateral_balance: Balance,
) -> PositionState {
    let tvtr = calculate_position_tvtr(
        unchanged_synthetics: unchanged_synthetics, collateral_balance: collateral_balance,
    );
    get_position_state(position_tvtr: tvtr)
}

pub fn assert_healthy_or_healthier(
    position_id: PositionId,
    tvtr: TVTRChange,
    allowed_bps_slippage: u16,
) {
    let position_state_after_change = get_position_state(position_tvtr: tvtr.after);
    if position_state_after_change == PositionState::Healthy {
        // If the position is healthy we can return.
        return;
    }

    if tvtr.before.total_risk.is_zero() || tvtr.after.total_risk.is_zero() {
        panic_with_byte_array(@position_not_healthy_nor_healthier(:position_id, :tvtr));
    }

    /// This is checked only when the after is not healthy:
    /// The position is healthier if the total_value divided by the total_risk
    /// is equal or higher after the change and the total_risk is lower.
    /// Formal definition:
    /// total_value_after / total_risk_after >= total_value_before / total_risk_before
    /// AND total_risk_after < total_risk_before.
    if tvtr.after.total_risk >= tvtr.before.total_risk {
        panic_with_byte_array(@position_not_healthy_nor_healthier(:position_id, :tvtr));
    }
    let before_ratio = FractionTrait::new(tvtr.before.total_value, tvtr.before.total_risk);

     //if tv <0 we want to increase tr so that tv/tr is a smaller negative number in absolute value
    let (nominator, denominator) = if (tvtr.after.total_value < 0) {
        (10000_u128 + allowed_bps_slippage.into(), 10000_u128)
    } else {
        (10000_u128, 10000_u128 + allowed_bps_slippage.into())
    };

    let scaled_tr: u128 = (tvtr.after.total_risk.into() * nominator) / denominator;

    let after_ratio = FractionTrait::new(
        tvtr.after.total_value, // allow negative 1bps change
        max(scaled_tr, 1_u128),
    );

    assert_with_byte_array(
        after_ratio >= before_ratio, position_not_healthy_nor_healthier(:position_id, :tvtr),
    );
}

fn max(a: u128, b: u128) -> u128 {
    if a >= b {
        return a;
    } else {
        return b;
    }
}

pub fn liquidated_position_validations(
    position_id: PositionId,
    unchanged_synthetics: Span<SyntheticAsset>,
    position_diff_enriched: PositionDiffEnriched,
) {
    let tvtr = calculate_position_tvtr_change(:unchanged_synthetics, :position_diff_enriched);
    let position_state_before_change = get_position_state(position_tvtr: tvtr.before);

    // Validate that the position isn't healthy before the change.
    assert_with_byte_array(
        position_state_before_change == PositionState::Liquidatable
            || position_state_before_change == PositionState::Deleveragable,
        position_not_liquidatable(:position_id, :tvtr),
    );
    assert_healthy_or_healthier(
        :position_id,
        :tvtr,
        allowed_bps_slippage: 10,
    );
}

pub fn deleveraged_position_validations(
    position_id: PositionId,
    unchanged_synthetics: Span<SyntheticAsset>,
    position_diff_enriched: PositionDiffEnriched,
) {
    let tvtr = calculate_position_tvtr_change(:unchanged_synthetics, :position_diff_enriched);
    let position_state_before_change = get_position_state(position_tvtr: tvtr.before);

    assert_with_byte_array(
        position_state_before_change == PositionState::Deleveragable,
        position_not_deleveragable(:position_id, :tvtr),
    );

    assert_healthy_or_healthier(
        :position_id,
        :tvtr,
        allowed_bps_slippage: 10,
    );
    assert_with_byte_array(
        is_fair_deleverage(before: tvtr.before, after: tvtr.after),
        position_not_fair_deleverage(:position_id, :tvtr),
    );
}

pub fn calculate_position_tvtr(
    unchanged_synthetics: Span<SyntheticAsset>, collateral_balance: Balance,
) -> PositionTVTR {
    let position_diff_enriched = PositionDiffEnriched {
        collateral_enriched: BalanceDiff { before: collateral_balance, after: collateral_balance },
        synthetic_enriched: Option::None,
    };
    calculate_position_tvtr_change(:unchanged_synthetics, :position_diff_enriched).before
}

/// Calculates the total value and total risk change for a position, taking into account both
/// unchanged assets and position changes (collateral and synthetic assets).
///
/// # Arguments
///
/// * `unchanged_assets` - Assets in the position that have not changed
/// * `position_diff_enriched` - Changes in collateral and synthetic assets for the position
///
/// # Returns
///
/// * `TVTRChange` - Contains the total value and total risk before and after the changes
///
/// # Logic Flow
/// 1. Calculates value and risk for unchanged assets
/// 2. Calculates value and risk changes for collateral assets
/// 3. Calculates value and risk changes for synthetic assets
/// 4. Combines all calculations into final before/after totals
pub fn calculate_position_tvtr_change(
    unchanged_synthetics: Span<SyntheticAsset>, position_diff_enriched: PositionDiffEnriched,
) -> TVTRChange {
    // Calculate the value and risk of the position data.
    let mut unchanged_synthetics_value: AssetValue = Default::default();
    let mut unchanged_synthetics_risk: AssetRisk = Default::default();
    for synthetic in unchanged_synthetics {
        // asset_value is in units of 10^-6 USD.
        let asset_value = (*synthetic.price).mul(rhs: *synthetic.balance);
        unchanged_synthetics_value += asset_value;
        unchanged_synthetics_risk += (*synthetic.risk_factor).mul(asset_value);
    }

    let mut total_value_before = unchanged_synthetics_value;
    let mut total_risk_before = unchanged_synthetics_risk;
    let mut total_value_after = unchanged_synthetics_value;
    let mut total_risk_after = unchanged_synthetics_risk;

    if let Option::Some(asset_diff) = position_diff_enriched.synthetic_enriched {
        // asset_value is in units of 10^-6 USD.
        let asset_value_before = asset_diff.price.mul(rhs: asset_diff.balance_before);
        let asset_value_after = asset_diff.price.mul(rhs: asset_diff.balance_after);

        total_value_before += asset_value_before;
        total_value_after += asset_value_after;

        total_risk_before += asset_diff.risk_factor_before.mul(asset_value_before);
        total_risk_after += asset_diff.risk_factor_after.mul(asset_value_after);
    }

    // Collateral price is always "One" in Perps - "One" is 10^-6 USD which means 2^28 same as the
    // PRICE_SCALE.
    let price: Price = One::one();
    // asset_value is in units of 10^-6 USD.
    total_value_before += price.mul(rhs: position_diff_enriched.collateral_enriched.before);
    total_value_after += price.mul(rhs: position_diff_enriched.collateral_enriched.after);

    TVTRChange {
        before: PositionTVTR {
            total_value: total_value_before.into(), total_risk: total_risk_before.into(),
        },
        after: PositionTVTR {
            total_value: total_value_after.into(), total_risk: total_risk_after.into(),
        },
    }
}


#[cfg(test)]
mod tests {
    use perpetuals::core::types::asset::synthetic::{SyntheticAsset, SyntheticDiffEnriched};
    use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
    use perpetuals::core::types::balance::BalanceTrait;
    use perpetuals::core::types::funding::FundingIndex;
    use perpetuals::core::types::price::{Price, PriceTrait};
    use perpetuals::core::types::risk_factor::RiskFactor;
    use super::*;


    /// Prices
    fn PRICE_1() -> Price {
        PriceTrait::new(value: 900_u64)
    }
    fn PRICE_2() -> Price {
        PriceTrait::new(value: 900_u64)
    }
    fn PRICE_3() -> Price {
        PriceTrait::new(value: 900_u64)
    }
    fn PRICE_4() -> Price {
        PriceTrait::new(value: 900_u64)
    }
    fn PRICE_5() -> Price {
        PriceTrait::new(value: 900_u64)
    }

    /// Risk factors
    fn RISK_FACTOR_1() -> RiskFactor {
        RiskFactorTrait::new(500)
    }
    fn RISK_FACTOR_2() -> RiskFactor {
        RiskFactorTrait::new(500)
    }
    fn RISK_FACTOR_3() -> RiskFactor {
        RiskFactorTrait::new(500)
    }
    fn RISK_FACTOR_4() -> RiskFactor {
        RiskFactorTrait::new(500)
    }
    fn RISK_FACTOR_5() -> RiskFactor {
        RiskFactorTrait::new(500)
    }

    /// Assets IDs
    fn SYNTHETIC_ASSET_ID_1() -> AssetId {
        AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_1"))
    }
    fn SYNTHETIC_ASSET_ID_2() -> AssetId {
        AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_2"))
    }
    fn SYNTHETIC_ASSET_ID_3() -> AssetId {
        AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_3"))
    }
    fn SYNTHETIC_ASSET_ID_4() -> AssetId {
        AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_4"))
    }
    fn SYNTHETIC_ASSET_ID_5() -> AssetId {
        AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_5"))
    }

    #[test]
    fn test_calculate_position_tvtr_change_basic_case() {
        // Create a position with a single asset entry.
        let asset = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: 60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let position_data = array![].span();
        let asset_diff = SyntheticDiffEnriched {
            asset_id: asset.id,
            balance_before: asset.balance,
            balance_after: BalanceTrait::new(value: 80),
            price: asset.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let position_diff_enriched = PositionDiffEnriched {
            collateral_enriched: Default::default(), synthetic_enriched: Option::Some(asset_diff),
        };

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before *
        /// price`
        /// (`60 * 900`).
        assert!(position_tvtr_change.before.total_value == 54_000);

        /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(60) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 27_000);

        /// Ensures `total_value` after the change is `72,000`, calculated as `balance_after *
        /// price`
        /// (`80 * 900`).
        assert!(position_tvtr_change.after.total_value == 72_000);

        /// Ensures `total_risk` after the change is `36,000`, calculated as `abs(balance_after) *
        /// price * risk_factor` (`abs(80) * 900 * 0.5`).
        assert!(position_tvtr_change.after.total_risk == 36_000);
    }

    #[test]
    fn test_assert_healthy_or_healthier_accepts_less_than_negative_10bps_change() {
        // Create a position with a single asset entry.
        let position_tvtr_change = TVTRChange {
            before: PositionTVTR { total_value: 15000, total_risk: 20000 },
            after: PositionTVTR { total_value: 7499, total_risk: 10000 },
        };

        assert_healthy_or_healthier(
            PositionId { value: 42 },
            position_tvtr_change,
            allowed_bps_slippage: 10,
        );
    }

    #[test]
    #[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: PositionId { value: 42 } TV before 15000, TR before 20000, TV after 7400, TR after 10000")]
    fn test_assert_healthy_or_healthier_rejects_more_than_negative_10bps_change() {
        // Create a position with a single asset entry.
        let position_tvtr_change = TVTRChange {
            before: PositionTVTR { total_value: 15000, total_risk: 20000 },
            after: PositionTVTR { total_value: 7400, total_risk: 10000 },
        };

        assert_healthy_or_healthier(
                PositionId { value: 42 },
                position_tvtr_change,
                allowed_bps_slippage: 10,
        );
    }

    /// Test the `calculate_position_tvtr_change` function for the case where the balance is
    /// negative.
    ///
    /// This test verifies the correctness of total value and total risk calculations before and
    /// after a position change in a scenario with one asset entry and one asset diff, where the
    /// balance is negative.
    #[test]
    fn test_calculate_position_tvtr_change_negative_balance() {
        // Create a position with a single asset entry.
        let asset = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: -60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let position_data = array![].span();
        let asset_diff = SyntheticDiffEnriched {
            asset_id: asset.id,
            balance_before: asset.balance,
            balance_after: BalanceTrait::new(value: 20),
            price: asset.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let position_diff_enriched = PositionDiffEnriched {
            collateral_enriched: Default::default(), synthetic_enriched: Option::Some(asset_diff),
        };

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `-54,000`, calculated as `balance_before *
        /// price`
        /// (`-60 * 900`).
        assert!(position_tvtr_change.before.total_value == -54_000);

        /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(-60) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 27_000);

        /// Ensures `total_value` after the change is `-18,000`, calculated as `balance_after *
        /// price`
        /// (`20 * 900`).
        assert!(position_tvtr_change.after.total_value == 18_000);

        /// Ensures `total_risk` after the change is `9,000`, calculated as `abs(balance_after) *
        /// price * risk_factor` (`abs(20) * 900 * 0.5`).
        assert!(position_tvtr_change.after.total_risk == 9_000);
    }

    /// Test the `calculate_position_tvtr_change` function for the case where there are multiple
    /// assets
    ///
    /// This test verifies the correctness of total value and total risk calculations before and
    /// after a position change in a scenario with multiple assets and a single asset diff.
    #[test]
    fn test_calculate_position_tvtr_change_multiple_assets() {
        // Create a position with multiple assets.
        let asset_1 = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: 60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let asset_2 = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_2(),
            balance: BalanceTrait::new(value: 40),
            price: PRICE_2(),
            risk_factor: RISK_FACTOR_2(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let asset_3 = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_3(),
            balance: BalanceTrait::new(value: 20),
            price: PRICE_3(),
            risk_factor: RISK_FACTOR_3(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let asset_4 = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_4(),
            balance: BalanceTrait::new(value: 10),
            price: PRICE_4(),
            risk_factor: RISK_FACTOR_4(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let asset_5 = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_5(),
            balance: BalanceTrait::new(value: 5),
            price: PRICE_5(),
            risk_factor: RISK_FACTOR_5(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let position_data = array![asset_2, asset_3, asset_4, asset_5].span();

        // Create a position diff with two assets diff.
        let asset_diff_1 = SyntheticDiffEnriched {
            asset_id: asset_1.id,
            balance_before: asset_1.balance,
            balance_after: BalanceTrait::new(value: 80),
            price: asset_1.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };

        let position_diff_enriched = PositionDiffEnriched {
            collateral_enriched: Default::default(), synthetic_enriched: Option::Some(asset_diff_1),
        };

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `121,500`, calculated as `balance_1_before *
        /// price + balance_2_before * price + balance_3_before * price + balance_4_before * price +
        /// balance_5_before * price` (`60 * 900 + 40 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
        assert!(position_tvtr_change.before.total_value == 121_500);

        /// Ensures `total_risk` before the change is `60,750`, calculated as `abs(balance_1_before)
        /// *
        /// price * risk_factor_1 + abs(balance_2_before) * price * risk_factor_2 +
        /// abs(balance_3_before) *
        /// price * risk_factor_3 + abs(balance_4_before) * price * risk_factor_4 +
        /// abs(balance_5_before) *
        /// price * risk_factor_5` (`abs(60) * 900 * 0.5 + abs(40) * 900 * 0.5 + abs(20) * 900 * 0.5
        /// +
        /// abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 60_750);

        /// Ensures `total_value` after the change is `139,500`, calculated as `balance_1_after *
        /// price + balance_2_after * price` + balance_3_after * price + balance_4_after * price +
        /// balance_5_after * price` (`80 * 900 + 40 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
        /// The balance of the other assets remains the same, so balance_2_after = 40,
        /// balance_3_after = 20, balance_4_after = 10, balance_5_after = 5.
        assert!(position_tvtr_change.after.total_value == 139_500);

        /// Ensures `total_risk` after the change is `69,750`, calculated as `abs(balance_1_after) *
        /// price * risk_factor_1 + abs(balance_2_after) * price * risk_factor_2 +
        /// abs(balance_3_after) * price * risk_factor_3 + abs(balance_4_after) * price *
        /// risk_factor_4 + abs(balance_5_after) * price * risk_factor_5` (`abs(80) * 900 * 0.5 +
        /// abs(40) * 900 * 0.5 + abs(20) * 900 * 0.5 + abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
        /// The balance of the other assets remains the same, so balance_2_after = 40,
        /// balance_3_after = 20, balance_4_after = 10, balance_5_after = 5.
        assert!(position_tvtr_change.after.total_risk == 69_750);
    }

    /// Test the `calculate_position_tvtr_change` function for the case where the diff is empty.
    #[test]
    fn test_calculate_position_tvtr_empty_diff() {
        // Create a position with a single asset entry.
        let asset = SyntheticAsset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: 60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
            cached_funding_index: FundingIndex { value: 38654705 },
        };
        let position_data = array![asset].span();

        // Create an empty position diff.
        let position_diff_enriched = Default::default();

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before *
        /// price`
        /// (`60 * 900`).
        assert!(position_tvtr_change.before.total_value == 54_000);

        /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(60) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 27_000);

        /// Ensures `total_value` after the change is `54,000`, calculated as `balance_before *
        /// price`
        /// (`60 * 900`).
        assert!(position_tvtr_change.after.total_value == 54_000);

        /// Ensures `total_risk` after the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(60) * 900 * 0.5`).
        assert!(position_tvtr_change.after.total_risk == 27_000);
    }


    /// Test the `calculate_position_tvtr_change` function for the case where the position is empty,
    /// and no diff is provided.
    #[test]
    fn test_calculate_position_tvtr_empty_position_and_diff() {
        // Create an empty position.
        let position_data = array![].span();

        // Create an empty position diff.
        let position_diff_enriched = Default::default();

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `0`.
        assert!(position_tvtr_change.before.total_value == 0);

        /// Ensures `total_risk` before the change is `0`.
        assert!(position_tvtr_change.before.total_risk == 0);

        /// Ensures `total_value` after the change is `0`.
        assert!(position_tvtr_change.after.total_value == 0);

        /// Ensures `total_risk` after the change is `0`.
        assert!(position_tvtr_change.after.total_risk == 0);
    }


    /// Test the `evaluate_position` function for the case where the position is empty.
    #[test]
    fn test_evaluate_position_empty_position_and_empty_diff() {
        // Create an empty position.

        let evaluated_position = evaluate_position(
            unchanged_synthetics: array![].span(), collateral_balance: Zero::zero(),
        );
        assert!(evaluated_position == PositionState::Healthy);
    }
}
