use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde, Debug)]
pub struct WithdrawArgs {
    pub recipient: ContractAddress,
    pub position_id: PositionId,
    pub asset_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"WithdrawArgs\"(
///    \"recipient\":\"ContractAddress\",
///    \"position_id\":\"PositionId\",
///    \"asset_id\":\"AssetId\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\"
///    \"salt\":\"felt\",
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
const WITHDRAW_ARGS_TYPE_HASH: HashType =
    0x036195e985ae51bb7274543be4a98cd9f2ca66accf58baf1c19f8422e3c30030;

impl WithdrawArgsStructHashImpl of StructHash<WithdrawArgs> {
    fn hash_struct(self: @WithdrawArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(WITHDRAW_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Copy, Drop, Hash, Serde, Debug)]
pub struct ForcedWithdrawArgs {
    pub withdraw_args_hash: HashType,
}

/// selector!(
///   "\"ForcedWithdrawArgs\"(
///    \"withdraw_args_hash\":\"HashType\",
///    )
/// );
const FORCED_WITHDRAW_ARGS_TYPE_HASH: HashType =
    0x9178e6792dcaaa6e712c83d5a34ff15f5c6a8158887dfb66d7f0956f557b0e;

impl ForcedWithdrawArgsStructHashImpl of StructHash<ForcedWithdrawArgs> {
    fn hash_struct(self: @ForcedWithdrawArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(FORCED_WITHDRAW_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}


#[cfg(test)]
mod tests {
    use perpetuals::core::types::asset::AssetIdTrait;
    use starkware_utils::math::utils::to_base_16_string;
    use super::*;

    #[test]
    fn test_withdraw_type_hash() {
        let expected = selector!(
            "\"WithdrawArgs\"(\"recipient\":\"ContractAddress\",\"position_id\":\"PositionId\",\"asset_id\":\"AssetId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(to_base_16_string(WITHDRAW_ARGS_TYPE_HASH), to_base_16_string(expected));
    }

    #[test]
    fn test_forced_withdraw_type_hash() {
        let expected = selector!("\"ForcedWithdrawArgs\"(\"withdraw_args_hash\":\"HashType\")");
        assert_eq!(to_base_16_string(FORCED_WITHDRAW_ARGS_TYPE_HASH), to_base_16_string(expected));
    }

    #[test]
    fn test_withdraw_hash_struct() {
        let withdraw_args = WithdrawArgs {
            position_id: PositionId { value: 1_u32 },
            salt: 123,
            expiration: Timestamp { seconds: 5 },
            asset_id: AssetIdTrait::new(4),
            amount: 1000,
            recipient: 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da
                .try_into()
                .unwrap(),
        };
        let withdraw_args_hash = withdraw_args.hash_struct();
        assert_eq!(
            to_base_16_string(withdraw_args_hash),
            "0x04dfddd6e9b9885160f479f400577fd2f24c72160f0f5801ce278d855cc3eb1a",
        );

        let forced_withdraw_args_hash = ForcedWithdrawArgs { withdraw_args_hash }.hash_struct();
        assert_eq!(
            to_base_16_string(forced_withdraw_args_hash),
            "0x00faa1fafff058d9a37fb5d8c35ec4c607c2b6df2221d0531292c81c7f2874c7",
        );
    }
}
