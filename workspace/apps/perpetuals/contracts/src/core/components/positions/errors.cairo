use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum Error {
    // Simple error constants
    ASSET_BALANCE_NEGATIVE,
    POSITION_DOESNT_EXIST,
    ALREADY_INITIALIZED,
    CALLER_IS_NOT_OWNER_ACCOUNT,
    SET_PUBLIC_KEY_EXPIRED,
    NO_OWNER_ACCOUNT,
    POSITION_ALREADY_EXISTS,
    POSITION_HAS_OWNER_ACCOUNT,
    INVALID_ZERO_PUBLIC_KEY,
    INVALID_ZERO_OWNER_ACCOUNT,
    SAME_PUBLIC_KEY,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            // Simple error constants
            Error::ASSET_BALANCE_NEGATIVE => "ASSET_BALANCE_NEGATIVE",
            Error::POSITION_DOESNT_EXIST => "POSITION_DOESNT_EXIST",
            Error::ALREADY_INITIALIZED => "ALREADY_INITIALIZED",
            Error::CALLER_IS_NOT_OWNER_ACCOUNT => "CALLER_IS_NOT_OWNER_ACCOUNT",
            Error::SET_PUBLIC_KEY_EXPIRED => "SET_PUBLIC_KEY_EXPIRED",
            Error::NO_OWNER_ACCOUNT => "NO_OWNER_ACCOUNT",
            Error::POSITION_ALREADY_EXISTS => "POSITION_ALREADY_EXISTS",
            Error::POSITION_HAS_OWNER_ACCOUNT => "POSITION_HAS_OWNER_ACCOUNT",
            Error::INVALID_ZERO_PUBLIC_KEY => "INVALID_ZERO_PUBLIC_KEY",
            Error::INVALID_ZERO_OWNER_ACCOUNT => "INVALID_ZERO_OWNER_ACCOUNT",
            Error::SAME_PUBLIC_KEY => "SAME_PUBLIC_KEY",
        }
    }
}
