use perpetuals::core::types::asset::AssetId;
use starkware_utils::time::time::Seconds;
use starkware_utils::math::utils::mul_wide_and_floor_div;
use starkware_utils::math::abs::Abs;
use starknet::storage::StoragePointer0Offset;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::syscalls::storage_read_syscall;
use starknet::SyscallResultTrait;


#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct VaultConfig {
    pub version: u8,
    pub asset_id: AssetId,
    pub position_id: u32,
    pub last_tv_check_timestamp: Seconds,
    pub tv_at_check: i128,
    pub max_tv_loss: u128,
}

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde)]
pub struct VaultProtectionParams {
    pub tv_at_check: i128,
    pub max_tv_loss: u128,
}

#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum VaultConfigOffset {
    VERSION,
    ASSET_ID,
    POSITION_ID,
    LAST_TV_CHECK_TIMESTAMP,
    TV_AT_CHECK,
    MAX_TV_LOSS,
}

pub impl VaultConfigOffsetIntoU8 of Into<VaultConfigOffset, u8> {
    fn into(self: VaultConfigOffset) -> u8 {
        match self {
            VaultConfigOffset::VERSION => 0_u8,
            VaultConfigOffset::ASSET_ID => 1_8,
            VaultConfigOffset::POSITION_ID => 2_u8,
            VaultConfigOffset::LAST_TV_CHECK_TIMESTAMP => 3_u8,
            VaultConfigOffset::TV_AT_CHECK => 4_u8,
            VaultConfigOffset::MAX_TV_LOSS => 5_u8,
        }
    }
}

#[generate_trait]
pub impl VaultConfigImpl of VaultConfigTrait {
    
    #[inline]
    fn read(
        entry: StoragePointer0Offset<VaultConfig>, offset: VaultConfigOffset,
    ) -> felt252 {
        storage_read_syscall(
            0,
            storage_address_from_base_and_offset(entry.__storage_pointer_address__, offset.into()),
        )
            .unwrap_syscall()
    }

    #[inline]
    fn read_version(entry: StoragePointer0Offset<VaultConfig>) -> felt252 {
        Self::read(entry, VaultConfigOffset::VERSION)
    }

   /// Returns true if the Option is Some, false if None.
    /// At the storage 0 indicates None, 1 indicates Some.
    #[inline]
    fn is_some(entry: StoragePointer0Offset<VaultConfig>) -> bool {
        let version = Self::read_version(entry);
        version != 0
    }

    /// Returns true if the Option is None, false if Some.
    /// At the storage 0 indicates None, 1 indicates Some.
    #[inline]
    fn is_none(entry: StoragePointer0Offset<VaultConfig>) -> bool {
        let version = Self::read_version(entry);
        version == 0
    }

    #[inline]
    fn get_max_tv_loss(tv_at_check: i128, limit: u32) -> u128 {
        return mul_wide_and_floor_div(tv_at_check.abs(), limit.into() * 10, 1000).unwrap();
    }
}