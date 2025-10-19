use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct VaultDepositArgs {
    pub position_id: PositionId,
    pub vault_position_id: PositionId,
    pub collateral_quantized_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// Type hash for VaultDepositArgs struct
/// This is calculated using the selector! macro with the exact struct definition
/// selector!(
///   "\"VaultDepositArgs\"(
///    \"position_id\":\"PositionId\",
///    \"vault_position_id\":\"PositionId\",
///    \"collateral_quantized_amount\":\"u64\",
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
const VAULT_DEPOSIT_ARGS_TYPE_HASH: HashType =
    0x0159d929b2c1c81a4c7ef04c80f05e4e2cd2c0e08844fa772c38b9a69230a47d;

impl StructHashImpl of StructHash<VaultDepositArgs> {
    fn hash_struct(self: @VaultDepositArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(VAULT_DEPOSIT_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::VAULT_DEPOSIT_ARGS_TYPE_HASH;

    #[test]
    fn test_vault_deposit_args_type_hash() {
        let expected = selector!(
            "\"VaultDepositArgs\"(\"position_id\":\"PositionId\",\"vault_position_id\":\"PositionId\",\"collateral_quantized_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(to_base_16_string(VAULT_DEPOSIT_ARGS_TYPE_HASH), to_base_16_string(expected));
    }
}
