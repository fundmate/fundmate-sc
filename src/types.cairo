use core::{
    {starknet::{ContractAddress}, poseidon::PoseidonTrait},
    hash::{Hash, HashStateTrait, HashStateExTrait},
};

use openzeppelin::utils::snip12::StructHash;

// TODO: Check this type hash
pub const REQUEST_TYPE_HASH: felt252 = selector!(
    "\"FundMateRequest\"(\"receiver\":\"ContractAddress\",\"token_address\":\"ContractAddress\",\"amount\":\"u256\",\"topic\":\"felt252\",\"participants_info\":\"Span<ParticipantInfo>\",\"expiry\":\"u64\",\"nonce\":\"felt252\")",
);


#[derive(Serde, Copy, Drop, Hash, starknet::Store)]
pub struct ParticipantInfo {
    pub address: ContractAddress,
    pub amount: u256,
}

pub impl HashSpanParticipantInfoImpl<
    S, +HashStateTrait<S>, +Drop<S>,
> of Hash<Span<ParticipantInfo>, S> {
    #[must_use]
    fn update_state(mut state: S, value: Span<ParticipantInfo>) -> S {
        for element in value {
            let el: ParticipantInfo = *element;
            let addr: felt252 = el.address.into();
            let low: felt252 = el.amount.low.into();
            let high: felt252 = el.amount.high.into();
            state = state.update_with(addr).update_with(low).update_with(high);
        };
        state
    }
}

#[derive(Serde, Copy, Drop, Hash)]
pub struct FundMateRequest {
    pub receiver: ContractAddress,
    pub token_address: ContractAddress,
    pub amount: u256,
    pub topic: felt252,
    pub participants_info: Span<ParticipantInfo>,
    pub expiry: u64,
    pub nonce: felt252,
    // pub callback: Option<ByteArray> // not used
}


pub impl StructHashImpl of StructHash<FundMateRequest> {
    fn hash_struct(self: @FundMateRequest) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(REQUEST_TYPE_HASH).update_with(*self).finalize()
    }
}
