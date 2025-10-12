use core::hash::{HashStateExTrait, HashStateTrait};
use core::panics::panic_with_byte_array;
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::errors::{illegal_base_to_quote_ratio_err, illegal_fee_to_quote_ratio_err};
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::math::abs::Abs;
use starkware_utils::math::fraction::FractionTrait;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Hash, Serde)]
// An order to buy or sell a synthetic asset for a collateral asset.
// The base amount and quote amount have opposite signs.
pub struct Order {
    pub position_id: PositionId,
    // The synthetic asset to be bought or sold.
    pub base_asset_id: AssetId,
    // The amount of the synthetic asset to be bought or sold.
    pub base_amount: i64,
    // The collateral asset.
    pub quote_asset_id: AssetId,
    // The amount of the collateral asset to be paid or received.
    pub quote_amount: i64,
    // The collateral asset.
    pub fee_asset_id: AssetId,
    // The amount of the collateral asset to be paid.
    pub fee_amount: u64,
    // The expiration time of the order.
    pub expiration: Timestamp,
    // A random value to make each order unique.
    pub salt: felt252,
}

/// selector!(
///   "\"Order\"(
///    \"position_id\":\"PositionId\",
///    \"base_asset_id\":\"AssetId\",
///    \"base_amount\":\"i64\",
///    \"quote_asset_id\":\"AssetId\",
///    \"quote_amount\":\"i64\",
///    \"fee_asset_id\":\"AssetId\",
///    \"fee_amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );

const ORDER_TYPE_HASH: HashType = 0x36da8d51815527cabfaa9c982f564c80fa7429616739306036f1f9b608dd112;

impl StructHashImpl of StructHash<Order> {
    fn hash_struct(self: @Order) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(ORDER_TYPE_HASH).update_with(*self).finalize()
    }
}

#[generate_trait]
pub impl OrderImpl of OrderTrait {
    /// Validates order variables against actual amounts:
    /// - Validate the order base-to-quote ratio does not exceed the actual base-to-quote ratio.
    /// - Validate the actual fee-to-quote ratio does not exceed the ordered fee-to-quote ratio.
    fn validate_against_actual_amounts(
        self: @Order, actual_amount_base: i64, actual_amount_quote: i64, actual_fee: u64,
    ) {
        let order_base_to_quote_ratio = FractionTrait::new(
            numerator: (*self.base_amount).into(), denominator: (*self.quote_amount).abs().into(),
        );
        let actual_base_to_quote_ratio = FractionTrait::new(
            numerator: actual_amount_base.into(), denominator: actual_amount_quote.abs().into(),
        );
        if (order_base_to_quote_ratio > actual_base_to_quote_ratio) {
            let err = @illegal_base_to_quote_ratio_err(*self.position_id);
            panic_with_byte_array(:err);
        }

        // Validating the fee-to-quote ratio enables increasing in both the user's quote and the
        // operator's fee.
        let actual_fee_to_quote_ratio = FractionTrait::new(
            numerator: actual_fee.into(), denominator: actual_amount_quote.abs().into(),
        );
        let order_fee_to_quote_ratio = FractionTrait::new(
            numerator: (*self.fee_amount).into(), denominator: (*self.quote_amount).abs().into(),
        );
        if (actual_fee_to_quote_ratio > order_fee_to_quote_ratio) {
            let err = @illegal_fee_to_quote_ratio_err(*self.position_id);
            panic_with_byte_array(:err);
        }
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::ORDER_TYPE_HASH;

    #[test]
    fn test_order_type_hash() {
        let expected = selector!(
            "\"Order\"(\"position_id\":\"felt\",\"base_asset_id\":\"AssetId\",\"base_amount\":\"i64\",\"quote_asset_id\":\"AssetId\",\"quote_amount\":\"i64\",\"fee_asset_id\":\"AssetId\",\"fee_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert!(to_base_16_string(ORDER_TYPE_HASH) == to_base_16_string(expected));
    }
}
