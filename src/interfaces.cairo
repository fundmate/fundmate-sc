use crate::FundMateRequest;
use core::starknet::ContractAddress;

#[starknet::interface]
pub trait IFundMate<TContractState> {
    fn create_request(ref self: TContractState, request: FundMateRequest) -> felt252;

    fn execute_signed_request(
        ref self: TContractState, request: FundMateRequest, signatures: Array<felt252>,
    );

    fn pay_contribution(ref self: TContractState, request_id: felt252);

    fn refund(ref self: TContractState, request_id: felt252) -> Option<bool>;

    fn check_contribution(self: @TContractState, request_id: felt252) -> Option<felt252>;

    fn compute_request_id(
        self: @TContractState, topic: felt252, coordinator: ContractAddress,
    ) -> felt252;
}
