#[starknet::contract]
pub mod FundMate {
    use crate::{IFundMate, FundMateRequest};
    use core::{bool, starknet::ContractAddress};


    #[storage]
    struct Storage {}


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}


    #[abi(embed_v0)]
    impl FundMateImpl of IFundMate<ContractState> {
        fn create_request(ref self: ContractState, request: FundMateRequest) -> felt252 {
            0
        }

        fn execute_signed_request(
            ref self: ContractState, request: FundMateRequest, signatures: Array<felt252>,
        ) {}

        fn pay_contribution(ref self: ContractState, request_id: felt252) {}

        fn refund(ref self: ContractState, request_id: felt252) -> Option<bool> {
            Option::Some(bool::True)
        }

        fn check_contribution(self: @ContractState, request_id: felt252) -> Option<felt252> {
            Option::Some(0)
        }

        fn compute_request_id(
            self: @ContractState, topic: felt252, coordinator: ContractAddress,
        ) -> felt252 {
            0
        }
    }
}
