use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct RegisterVaultArgs {
    pub vault_position_id: PositionId,
    pub vault_contract_address: ContractAddress,
    pub vault_asset_id: AssetId,
    pub expiration: Timestamp,
}

/// selector!(
///   "\"RegisterVaultArgs\"(
///    \"vault_position_id\":\"PositionId\",
///    \"vault_contract_address\":\"ContractAddress\",
///    \"vault_asset_id\":\"AssetId\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const REGISTER_VAULT_ARGS_TYPE_HASH: HashType =
    0x027f24d3d07fa5bd64ec07df95d1209508ae64f4ff4f690444f68b7d4cb5c309;

impl StructHashImpl of StructHash<RegisterVaultArgs> {
    fn hash_struct(self: @RegisterVaultArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(REGISTER_VAULT_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use openzeppelin_testing::common::IntoBase16String;
    use super::REGISTER_VAULT_ARGS_TYPE_HASH;

    #[test]
    fn test_register_vault_type_hash() {
        let expected = selector!(
            "\"RegisterVaultArgs\"(\"vault_position_id\":\"PositionId\",\"vault_contract_address\":\"ContractAddress\",\"vault_asset_id\":\"AssetId\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            REGISTER_VAULT_ARGS_TYPE_HASH.into_base_16_string(), expected.into_base_16_string(),
        );
    }
}
