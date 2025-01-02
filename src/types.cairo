use core::starknet::ContractAddress;


#[derive(Serde, Drop)]
pub enum SplitType {
    Even,
    Custom: Array<felt252>,
}

#[derive(Serde, Drop)]
pub struct FundMateRequest {
    receiver: ContractAddress,
    amount: felt252,
    split_type: SplitType,
    participants: Array<felt252>,
    expiration: u64,
    //callback: felt252 // not used atm
}
