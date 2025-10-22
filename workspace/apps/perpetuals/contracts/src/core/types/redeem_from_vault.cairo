use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::Price;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct RedeemFromVaultUserArgs {
    pub position_id: PositionId,
    pub vault_position_id: PositionId,
    pub number_of_shares: u64,
    pub minimum_received_total_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"RedeemFromVaultUserArgs\"(
///    \"position_id\":\"PositionId\",
///    \"vault_position_id\":\"PositionId\",
///    \"number_of_shares\":\"u64\",
///    \"minimum_received_total_amount\":\"u64\",
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
const REDEEM_FROM_VAULT_USER_ARGS_TYPE_HASH: HashType =
    0x035ee416f9106a417cfa6ad065eb591c02a8fee1643852a8ad5b1c54deb99e94;

impl UserStructHashImpl of StructHash<RedeemFromVaultUserArgs> {
    fn hash_struct(self: @RedeemFromVaultUserArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(REDEEM_FROM_VAULT_USER_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct RedeemFromVaultOwnerArgs {
    pub redeem_from_vault_user_hash: HashType,
    pub vault_share_execution_price: Price,
}

/// selector!(
///   "\"RedeemFromVaultOwnerArgs\"(
///    \"redeem_from_vault_user_hash\":\"HashType\",
///    \"vault_share_execution_price\":\"Price\",
///    )
///    \"Price\"(
///    \"value\":\"u64\"
///    )"
/// );
const REDEEM_FROM_VAULT_OWNER_ARGS_TYPE_HASH: HashType =
    0x020ac0ef5909382358d9a6b8d0030d7e03ddd39ddf1b674558284d1cee13d373;

impl OwnerStructHashImpl of StructHash<RedeemFromVaultOwnerArgs> {
    fn hash_struct(self: @RedeemFromVaultOwnerArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(REDEEM_FROM_VAULT_OWNER_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::{REDEEM_FROM_VAULT_OWNER_ARGS_TYPE_HASH, REDEEM_FROM_VAULT_USER_ARGS_TYPE_HASH};

    #[test]
    fn test_redeem_from_vault_user_args_type_hash() {
        let expected = selector!(
            "\"RedeemFromVaultUserArgs\"(\"position_id\":\"PositionId\",\"vault_position_id\":\"PositionId\",\"number_of_shares\":\"u64\",\"minimum_received_total_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(REDEEM_FROM_VAULT_USER_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }


    #[test]
    fn test_redeem_from_vault_owner_args_type_hash() {
        let expected = selector!(
            "\"RedeemFromVaultOwnerArgs\"(\"redeem_from_vault_user_hash\":\"HashType\",\"vault_share_execution_price\":\"Price\")\"Price\"(\"value\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(REDEEM_FROM_VAULT_OWNER_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }
}

