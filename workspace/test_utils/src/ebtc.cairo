// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^3.0.0

#[starknet::contract]
mod eBTC {
    use core::num::traits::Pow;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    // External
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress) {
        self.erc20.initializer("eBTC", "eBTC");
        self.erc20.mint(recipient, 2_u128.pow(127).try_into().unwrap());
    }

    impl ERC20ImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 12;
    }
}
