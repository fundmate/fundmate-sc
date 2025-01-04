use crate::types::{FundMateRequest, ParticipantInfo};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IFundMate<TContractState> {
    fn execute_signed_request(
        ref self: TContractState, request: FundMateRequest, signatures: Array<Array<felt252>>,
    );

    fn create_split_payment_request(
        ref self: TContractState,
        receiver: ContractAddress,
        topic: felt252,
        amount: u256,
        expiration: u64,
        token_payment_address: ContractAddress,
        participants_info: Array<ParticipantInfo>,
    );

    fn finalize_payment(ref self: TContractState, request_id: felt252);

    fn pay_contribution(ref self: TContractState, request_id: felt252, amount: u256);

    fn refund(ref self: TContractState, request_id: felt252);


    fn check_contribution(
        self: @TContractState, payer: ContractAddress, request_id: felt252,
    ) -> u256;
}

