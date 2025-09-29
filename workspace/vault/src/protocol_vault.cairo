#[starknet::contract]
pub mod ProtocolVault {
    use ERC4626Component::Fee;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::token::erc20::extensions::erc4626::{
        DefaultConfig, ERC4626Component, ERC4626DefaultNoFees, ERC4626DefaultNoLimits,
    };
    use openzeppelin::token::erc20::{
        DefaultConfig as ERC20DefaultConfig, ERC20Component, ERC20HooksEmptyImpl,
    };
    use perpetuals::core::components::positions::interface::{
        IPositionsDispatcher, IPositionsDispatcherTrait,
    };
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::math::abs::Abs;
    use vault::interface::IProtocolVault;

    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    const INVALID_CALLER: felt252 = 'INVALID_CALLER';

    #[abi(embed_v0)]
    impl ERC4626Impl = ERC4626Component::ERC4626Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC4626MetadataImpl = ERC4626Component::ERC4626MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;


    impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        perps_contract: ContractAddress,
        owning_position_id: u32,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC4626Event: ERC4626Component::Event,
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        pnl_collateral_contract: ContractAddress,
        perps_contract: ContractAddress,
        owning_position_id: u32,
        initial_supply: u256,
        recipient: ContractAddress,
    ) {
        self.perps_contract.write(perps_contract);
        self.owning_position_id.write(owning_position_id);
        self.erc20.initializer(:name, :symbol);
        self.erc20.mint(:recipient, amount: initial_supply);
        self.erc4626.initializer(asset_address: pnl_collateral_contract);
    }

    #[abi(embed_v0)]
    pub impl Impl of IProtocolVault<ContractState> {
        fn redeem_with_price(
            ref self: ContractState, shares: u256, value_of_shares: u256, receiver: ContractAddress,
        ) -> u256 {
            let caller = starknet::get_caller_address();
            self
                .erc4626
                ._withdraw(
                    :caller,
                    :receiver,
                    owner: caller,
                    assets: value_of_shares,
                    shares: shares,
                    fee: Option::None,
                );
            value_of_shares
        }

        fn get_owning_position_id(ref self: ContractState) -> u32 {
            self.owning_position_id.read()
        }
    }


    impl ERC4626ExternalAssetsManagement of ERC4626Component::AssetsManagementTrait<ContractState> {
        fn transfer_assets_in(
            ref self: ERC4626Component::ComponentState<ContractState>,
            from: ContractAddress,
            assets: u256,
        ) {
            let this = starknet::get_contract_address();
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(
                asset_dispatcher.transfer_from(from, this, assets),
                ERC4626Component::Errors::TOKEN_TRANSFER_FAILED,
            );
        }

        fn transfer_assets_out(
            ref self: ERC4626Component::ComponentState<ContractState>,
            to: ContractAddress,
            assets: u256,
        ) {
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(
                asset_dispatcher.transfer(to, assets),
                ERC4626Component::Errors::TOKEN_TRANSFER_FAILED,
            );
        }

        fn get_total_assets(self: @ERC4626Component::ComponentState<ContractState>) -> u256 {
            let asset_storage = self.get_contract().perps_contract.read();
            let asset_dispatcher = IPositionsDispatcher { contract_address: asset_storage };
            let position_tvtr = asset_dispatcher
                .get_position_tv_tr(self.get_contract().owning_position_id.read().into());
            return position_tvtr.total_value.abs().into();
        }
    }


    impl ERC4626Hooks of ERC4626Component::ERC4626HooksTrait<ContractState> {
        fn before_deposit(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {
            let perps_contract = self.get_contract().perps_contract.read();
            assert(perps_contract == get_caller_address(), INVALID_CALLER);
        }

        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        /// The fee is calculated via `FeeConfigTrait`. Assets and shares
        /// represent the actual amounts the user will spend and receive, respectively.
        /// Asset fees are included in assets; share fees are excluded from shares.
        fn after_deposit(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {
            let perps_contract = self.get_contract().perps_contract.read();

            // after a deposit we need to send back the underlying asset to the perps contract
            self.transfer_assets_out(to: perps_contract, :assets);
        }
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        /// The fee is calculated via `FeeConfigTrait`. Assets and shares
        /// represent the actual amounts the user will receive and spend, respectively.
        /// Asset fees are excluded from assets; share fees are included in shares.
        fn before_withdraw(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {
            let perps_contract = self.get_contract().perps_contract.read();
            assert(perps_contract == get_caller_address(), INVALID_CALLER);

            // before withdraw we need to pull the underlying asset from the perps contract
            self.transfer_assets_in(from: perps_contract, :assets);
        }
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic after burning shares and transferring assets.
        /// The fee is calculated via `FeeConfigTrait`. Assets and shares
        /// represent the actual amounts the user will receive and spend, respectively.
        /// Asset fees are excluded from assets; share fees are included in shares.
        fn after_withdraw(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {}
    }
}
