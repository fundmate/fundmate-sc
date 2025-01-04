use crate::types::FundMateRequest;

#[starknet::interface]
pub trait IFundMate<TContractState> {
    fn execute_signed_request(
        ref self: TContractState, request: FundMateRequest, signatures: Array<Array<felt252>>,
    );
}
