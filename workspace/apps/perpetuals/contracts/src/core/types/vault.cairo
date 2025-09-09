use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
/// An order to buy vault shares.
pub struct InvestInVault {
    // user position (source)
    pub from_position_id: PositionId,
    // vault position (target)
    pub vault_id: PositionId,
    // The amount of the collateral asset to be invest.
    pub amount: u64,
    // The expiration time of the order.
    pub expiration: Timestamp,
    // A random value to make each order unique.
    pub salt: felt252,
}


#[derive(Copy, Drop, Hash, Serde)]
/// An order to move collateral back from a vault to a user position (redeem).
pub struct RedeemFromVault {
    // vault position (source).
    pub vault_id: PositionId,
    // user position (target)
    pub to_position_id: PositionId,
    // The amount of the collateral asset to be redeem.
    pub amount: u64,
    // The expiration time of the order.
    pub expiration: Timestamp,
    // A random value to make each order unique.
    pub salt: felt252,
}


#[derive(Copy, Drop, Hash, Serde)]
/// An order to convert a position into a vault.
pub struct ConvertPositionToVault {
    // the position being converted into a vault
    pub position_to_convert: PositionId,
    // the position that receives the initial shares
    pub position_receiving_shares: PositionId,
    // amount of initial shares allocated
    pub initial_shares: u64,
    // The expiration time of the order.
    pub expiration: Timestamp,
}

/// selector!(
///   "\"InvestInVault\"(
///    \"from_position_id\":\"PositionId\",
///    \"vault_id\":\"PositionId\",
///    \"amount\":\"u64\",
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
const INVEST_IN_VAULT_TYPE_HASH: HashType =
    0x02a65ee4e1411742e955f29a41e4044248c9cc87058cc9c45c18fb0361caf810;

/// selector!(
///   "\"RedeemFromVault\"(
///    \"vault_id\":\"PositionId\",
///    \"to_position_id\":\"PositionId\",
///    \"amount\":\"u64\",
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
const REDEEM_FROM_VAULT_TYPE_HASH: HashType =
    0x037fe967135296cbf99efc8ebf99277f9cdc036093d4fe6ff661588245d80a28;

/// selector!(
///   "\"ConvertPositionToVault\"(
///    \"position_to_convert\":\"PositionId\",
///    \"position_receiving_shares\":\"PositionId\",
///    \"initial_shares\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const CONVERT_POSITION_TO_VAULT_TYPE_HASH: HashType =
    0x01d9423fdc501a97387f677c15ee120dac505554e85b445253d63f5d150faccd;


impl InvestInVaultStructHashImpl of StructHash<InvestInVault> {
    fn hash_struct(self: @InvestInVault) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(INVEST_IN_VAULT_TYPE_HASH).update_with(*self).finalize()
    }
}

impl RedeemFromVaultStructHashImpl of StructHash<RedeemFromVault> {
    fn hash_struct(self: @RedeemFromVault) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(REDEEM_FROM_VAULT_TYPE_HASH).update_with(*self).finalize()
    }
}

impl ConvertPositionToVaultStructHashImpl of StructHash<ConvertPositionToVault> {
    fn hash_struct(self: @ConvertPositionToVault) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CONVERT_POSITION_TO_VAULT_TYPE_HASH).update_with(*self).finalize()
    }
}


#[cfg(test)]
mod tests {
    use openzeppelin_testing::common::IntoBase16String;
    use super::{
        CONVERT_POSITION_TO_VAULT_TYPE_HASH, INVEST_IN_VAULT_TYPE_HASH, REDEEM_FROM_VAULT_TYPE_HASH,
    };

    #[test]
    fn test_invest_in_vault_type_hash() {
        let expected = selector!(
            "\"InvestInVault\"(\"from_position_id\":\"PositionId\",\"vault_id\":\"PositionId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(INVEST_IN_VAULT_TYPE_HASH.into_base_16_string(), expected.into_base_16_string());
    }

    #[test]
    fn test_redeem_from_vault_type_hash() {
        let expected = selector!(
            "\"RedeemFromVault\"(\"vault_id\":\"PositionId\",\"to_position_id\":\"PositionId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            REDEEM_FROM_VAULT_TYPE_HASH.into_base_16_string(), expected.into_base_16_string(),
        );
    }

    #[test]
    fn test_convert_position_to_vault_type_hash() {
        let expected = selector!(
            "\"ConvertPositionToVault\"(\"position_to_convert\":\"PositionId\",\"position_receiving_shares\":\"PositionId\",\"initial_shares\":\"u64\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            CONVERT_POSITION_TO_VAULT_TYPE_HASH.into_base_16_string(),
            expected.into_base_16_string(),
        );
    }
}

