use perpetuals::core::types::asset::AssetId;
use starkware_utils::time::time::Seconds;
use starknet::storage::StoragePointer0Offset;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::syscalls::storage_read_syscall;
use starknet::SyscallResultTrait;


#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct VaultConfig {
    pub version: u8,
    pub asset_id: AssetId,
    pub position_id: u32,
    pub last_tv_check: Seconds,
    pub tv_at_check: i128,
    pub max_tv_loss: u128,
}

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde)]
pub struct VaultProtectionParams {
    pub tv_at_check: i128,
    pub max_tv_loss: u128,
}

#[generate_trait]
pub impl VaultConfigImpl of VaultConfigTrait {
    
    #[inline]
    fn read(
        entry: StoragePointer0Offset<VaultConfig>, offset: u8,
    ) -> felt252 {
        storage_read_syscall(
            0,
            storage_address_from_base_and_offset(entry.__storage_pointer_address__, offset),
        )
            .unwrap_syscall()
    }

    #[inline]
    fn read_version(entry: StoragePointer0Offset<VaultConfig>) -> felt252 {
        Self::read(entry, 0)
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
}
