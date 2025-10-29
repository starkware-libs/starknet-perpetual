use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::Price;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct LiquidateVaultSharesArgs {
    pub position_id: PositionId,
    pub vault_position_id: PositionId,
    pub number_of_shares: u64,
    pub vault_share_execution_price: Price,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"LiquidateVaultSharesArgs\"(
///    \"position_id\":\"PositionId\",
///    \"vault_position_id\":\"PositionId\",
///    \"number_of_shares\":\"u64\",
///    \"vault_share_execution_price\":\"Price\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Price\"(
///    \"value\":\"u64\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )"
/// );
const LIQUIDATE_VAULT_SHARES_ARGS_TYPE_HASH: HashType =
    0x0141b4c09491cda786aa7d765d022e0a2a45ededc52f93227c12f2107810c9d1;

impl StructHashImpl of StructHash<LiquidateVaultSharesArgs> {
    fn hash_struct(self: @LiquidateVaultSharesArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(LIQUIDATE_VAULT_SHARES_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::LIQUIDATE_VAULT_SHARES_ARGS_TYPE_HASH;

    #[test]
    fn test_liquidate_vault_shares_args_type_hash() {
        let expected = selector!(
            "\"LiquidateVaultSharesArgs\"(\"position_id\":\"PositionId\",\"vault_position_id\":\"PositionId\",\"number_of_shares\":\"u64\",\"vault_share_execution_price\":\"Price\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Price\"(\"value\":\"u64\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(LIQUIDATE_VAULT_SHARES_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }
}
