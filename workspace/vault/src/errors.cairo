use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum Error {
    // Simple error constants
    INVALID_ZERO_ADDRESS,
    INVALID_ZERO_POSITION_ID,
    NEGATIVE_TOTAL_VALUE,
    ONLY_PERPS_CAN_DEPOSIT,
    ONLY_PERPS_CAN_OWN,
    ONLY_PERPS_CAN_RECEIVE,
    ONLY_PERPS_CAN_WITHDRAW,
    INITIAL_ASSETS_MUST_BE_POSITIVE,
    RECIPIENT_CANNOT_BE_PERPS,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            // Simple error constants
            Error::INVALID_ZERO_ADDRESS => "INVALID_ZERO_ADDRESS",
            Error::INVALID_ZERO_POSITION_ID => "INVALID_ZERO_POSITION_ID",
            Error::NEGATIVE_TOTAL_VALUE => "NEGATIVE_TOTAL_VALUE",
            Error::ONLY_PERPS_CAN_DEPOSIT => "ONLY_PERPS_CAN_DEPOSIT",
            Error::ONLY_PERPS_CAN_OWN => "ONLY_PERPS_CAN_OWN",
            Error::ONLY_PERPS_CAN_RECEIVE => "ONLY_PERPS_CAN_RECEIVE",
            Error::ONLY_PERPS_CAN_WITHDRAW => "ONLY_PERPS_CAN_WITHDRAW",
            Error::INITIAL_ASSETS_MUST_BE_POSITIVE => "INITIAL_ASSETS_MUST_BE_POSITIVE",
            Error::RECIPIENT_CANNOT_BE_PERPS => "RECIPIENT_CANNOT_BE_PERPS",
        }
    }
}
