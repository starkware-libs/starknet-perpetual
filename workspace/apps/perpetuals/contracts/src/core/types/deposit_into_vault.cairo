use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct VaultDepositArgs {
    pub position_id: PositionId,
    pub vault_position_id: PositionId,
    pub collateral_id: AssetId,
    pub quantized_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// Type hash for VaultDepositArgs struct
/// This is calculated using the selector! macro with the exact struct definition
/// selector!(
///   "\"VaultDepositArgs\"(
///    \"position_id\":\"PositionId\",
///    \"vault_position_id\":\"PositionId\",
///    \"collateral_id\":\"AssetId\",
///    \"quantized_amount\":\"u64\",
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
const VAULT_DEPOSIT_ARGS_TYPE_HASH: HashType =
    0x02fd0884bec28d3a73edd59e4a36a246a4e26b96e283617898a80323a769abba;

impl StructHashImpl of StructHash<VaultDepositArgs> {
    fn hash_struct(self: @VaultDepositArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(VAULT_DEPOSIT_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use openzeppelin_testing::common::IntoBase16String;
    use super::VAULT_DEPOSIT_ARGS_TYPE_HASH;

    #[test]
    fn test_vault_deposit_args_type_hash() {
        let expected = selector!(
            "\"VaultDepositArgs\"(\"position_id\":\"PositionId\",\"vault_position_id\":\"PositionId\",\"collateral_id\":\"AssetId\",\"quantized_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"AssetId\"(\"value\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            VAULT_DEPOSIT_ARGS_TYPE_HASH.into_base_16_string(), expected.into_base_16_string(),
        );
    }
}
