use core::num::traits::zero::Zero;

pub mod synthetic;

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct AssetId {
    value: felt252,
}

#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum AssetStatus {
    #[default]
    PENDING,
    ACTIVE,
    INACTIVE,
}

#[generate_trait]
pub impl AssetIdImpl of AssetIdTrait {
    fn new(value: felt252) -> AssetId {
        AssetId { value }
    }

    fn value(self: @AssetId) -> felt252 {
        *self.value
    }
}

pub impl FeltIntoAssetId of Into<felt252, AssetId> {
    fn into(self: felt252) -> AssetId {
        AssetId { value: self }
    }
}

pub impl AssetIdIntoFelt of Into<AssetId, felt252> {
    fn into(self: AssetId) -> felt252 {
        self.value
    }
}

impl AssetIdZero of Zero<AssetId> {
    fn zero() -> AssetId {
        AssetId { value: 0 }
    }
    fn is_zero(self: @AssetId) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @AssetId) -> bool {
        self.value.is_non_zero()
    }
}

impl AssetIdlOrd of PartialOrd<AssetId> {
    fn lt(lhs: AssetId, rhs: AssetId) -> bool {
        let l: u256 = lhs.value.into();
        let r: u256 = rhs.value.into();
        l < r
    }
}
