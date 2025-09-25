use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::Price;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct VaultWithdrawUserArgs {
    pub position_id: PositionId,
    pub vault_position_id: PositionId,
    pub number_of_shares: u64,
    pub minimum_quantized_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"VaultWithdrawUserArgs\"(
///    \"position_id\":\"PositionId\",
///    \"vault_position_id\":\"PositionId\",
///    \"number_of_shares\":\"u64\",
///    \"minimum_quantized_amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const VAULT_WITHDRAW_USER_ARGS_TYPE_HASH: HashType =
    0x037eda11fb5eb7545f1a7688f1af3e7f4772768f8b048b5dd2ed1e05f18ced34;

impl UserStructHashImpl of StructHash<VaultWithdrawUserArgs> {
    fn hash_struct(self: @VaultWithdrawUserArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(VAULT_WITHDRAW_USER_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}


#[derive(Copy, Drop, Hash, Serde)]
pub struct VaultWithdrawOwnerArgs {
    pub vault_withdraw_user_hash: HashType,
    pub vault_share_execution_price: Price,
}

/// selector!(
///   "\"VaultWithdrawOwnerArgs\"(
///    \"vault_withdraw_user_hash\":\"HashType\",
///    \"vault_share_execution_price\":\"Price\",
///    )
///    \"Price\"(
///    \"value\":\"u64\"
///    )"
/// );
const VAULT_WITHDRAW_OWNER_ARGS_TYPE_HASH: HashType =
    0x0088e44b1155ce2bfce8d122e37685de202ad5c29864122e51bb1ae3351d48df;

impl OwnerStructHashImpl of StructHash<VaultWithdrawOwnerArgs> {
    fn hash_struct(self: @VaultWithdrawOwnerArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(VAULT_WITHDRAW_OWNER_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::{VAULT_WITHDRAW_OWNER_ARGS_TYPE_HASH, VAULT_WITHDRAW_USER_ARGS_TYPE_HASH};

    #[test]
    fn test_vault_withdraw_user_args_type_hash() {
        let expected = selector!(
            "\"VaultWithdrawUserArgs\"(\"position_id\":\"PositionId\",\"vault_position_id\":\"PositionId\",\"number_of_shares\":\"u64\",\"minimum_quantized_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(VAULT_WITHDRAW_USER_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }


    #[test]
    fn test_vault_withdraw_owner_args_type_hash() {
        let expected = selector!(
            "\"VaultWithdrawOwnerArgs\"(\"vault_withdraw_user_hash\":\"TypeHash\",\"vault_share_execution_price\":\"Price\")\"Price\"(\"value\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(VAULT_WITHDRAW_OWNER_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }
}

