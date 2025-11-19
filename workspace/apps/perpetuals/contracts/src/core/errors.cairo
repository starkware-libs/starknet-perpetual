use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::value_risk_calculator::TVTRChange;
use starkware_utils::errors::{Describable, ErrorDisplay};
#[derive(Drop)]
pub enum Error {
    // Simple error constants
    AMOUNT_OVERFLOW,
    ASSET_ID_NOT_COLLATERAL,
    CANT_TRADE_WITH_FEE_POSITION,
    CANT_LIQUIDATE_IF_POSITION,
    DIFFERENT_BASE_ASSET_IDS,
    INVALID_ACTUAL_BASE_SIGN,
    INVALID_ACTUAL_QUOTE_SIGN,
    INVALID_AMOUNT_SIGN,
    INVALID_BASE_CHANGE,
    INVALID_QUOTE_AMOUNT_SIGN,
    INVALID_QUOTE_FEE_AMOUNT,
    INVALID_SAME_POSITIONS,
    INVALID_ZERO_AMOUNT,
    SYNTHETIC_IS_ACTIVE,
    TRANSFER_FAILED,
    SAME_BASE_QUOTE_ASSET_IDS,
    // Error functions with parameters
    FULFILLMENT_EXCEEDED: PositionId,
    ILLEGAL_BASE_TO_QUOTE_RATIO: PositionId,
    ILLEGAL_FEE_TO_QUOTE_RATIO: PositionId,
    INVALID_FUNDING_RATE: AssetId,
    ORDER_EXPIRED: PositionId,
    POSITION_NOT_DELEVERAGABLE: (PositionId, TVTRChange),
    POSITION_NOT_FAIR_DELEVERAGE: (PositionId, TVTRChange),
    POSITION_NOT_HEALTHY_NOR_HEALTHIER: (PositionId, TVTRChange),
    POSITION_NOT_LIQUIDATABLE: (PositionId, TVTRChange),
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            // Simple error constants
            Error::AMOUNT_OVERFLOW => "AMOUNT_OVERFLOW",
            Error::ASSET_ID_NOT_COLLATERAL => "QUOTE_ASSET_ID_NOT_COLLATERAL",
            Error::CANT_TRADE_WITH_FEE_POSITION => "CANT_TRADE_WITH_FEE_POSITION",
            Error::CANT_LIQUIDATE_IF_POSITION => "CANT_LIQUIDATE_IF_POSITION",
            Error::DIFFERENT_BASE_ASSET_IDS => "DIFFERENT_BASE_ASSET_IDS",
            Error::INVALID_ACTUAL_BASE_SIGN => "INVALID_ACTUAL_BASE_SIGN",
            Error::INVALID_ACTUAL_QUOTE_SIGN => "INVALID_ACTUAL_QUOTE_SIGN",
            Error::INVALID_AMOUNT_SIGN => "INVALID_AMOUNT_SIGN",
            Error::INVALID_BASE_CHANGE => "INVALID_BASE_CHANGE",
            Error::INVALID_QUOTE_AMOUNT_SIGN => "INVALID_QUOTE_AMOUNT_SIGN",
            Error::INVALID_QUOTE_FEE_AMOUNT => "INVALID_QUOTE_FEE_AMOUNT",
            Error::INVALID_SAME_POSITIONS => "INVALID_SAME_POSITIONS",
            Error::INVALID_ZERO_AMOUNT => "INVALID_ZERO_AMOUNT",
            Error::SYNTHETIC_IS_ACTIVE => "SYNTHETIC_IS_ACTIVE",
            Error::TRANSFER_FAILED => "TRANSFER_FAILED",
            Error::SAME_BASE_QUOTE_ASSET_IDS => "SAME_BASE_QUOTE_ASSET_IDS",
            // Error functions with parameters
            Error::FULFILLMENT_EXCEEDED(position_id) => format!(
                "FULFILLMENT_EXCEEDED position_id: {:?}", *position_id,
            ),
            Error::ILLEGAL_BASE_TO_QUOTE_RATIO(position_id) => format!(
                "ILLEGAL_BASE_TO_QUOTE_RATIO position_id: {:?}", *position_id,
            ),
            Error::ILLEGAL_FEE_TO_QUOTE_RATIO(position_id) => format!(
                "ILLEGAL_FEE_TO_QUOTE_RATIO position_id: {:?}", *position_id,
            ),
            Error::INVALID_FUNDING_RATE(synthetic_id) => format!(
                "INVALID_FUNDING_RATE synthetic_id: {:?}", *synthetic_id,
            ),
            Error::ORDER_EXPIRED(position_id) => format!(
                "ORDER_EXPIRED position_id: {:?}", *position_id,
            ),
            Error::POSITION_NOT_DELEVERAGABLE((
                position_id, tvtr,
            )) => format!(
                "POSITION_IS_NOT_DELEVERAGABLE position_id: {:?} TV before {:?}, TR before {:?}, TV after {:?}, TR after {:?}",
                *position_id,
                *tvtr.before.total_value,
                *tvtr.before.total_risk,
                *tvtr.after.total_value,
                *tvtr.after.total_risk,
            ),
            Error::POSITION_NOT_FAIR_DELEVERAGE((
                position_id, tvtr,
            )) => format!(
                "POSITION_IS_NOT_FAIR_DELEVERAGE position_id: {:?} TV before {:?}, TR before {:?}, TV after {:?}, TR after {:?}",
                *position_id,
                *tvtr.before.total_value,
                *tvtr.before.total_risk,
                *tvtr.after.total_value,
                *tvtr.after.total_risk,
            ),
            Error::POSITION_NOT_HEALTHY_NOR_HEALTHIER((
                position_id, tvtr,
            )) => format!(
                "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: {:?} TV before {:?}, TR before {:?}, TV after {:?}, TR after {:?}",
                *position_id,
                *tvtr.before.total_value,
                *tvtr.before.total_risk,
                *tvtr.after.total_value,
                *tvtr.after.total_risk,
            ),
            Error::POSITION_NOT_LIQUIDATABLE((
                position_id, tvtr,
            )) => format!(
                "POSITION_IS_NOT_LIQUIDATABLE position_id: {:?} TV before {:?}, TR before {:?}, TV after {:?}, TR after {:?}",
                *position_id,
                *tvtr.before.total_value,
                *tvtr.before.total_risk,
                *tvtr.after.total_value,
                *tvtr.after.total_risk,
            ),
        }
    }
}
