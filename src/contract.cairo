#[starknet::contract]
pub mod FundMate {
    use core::{
        bool,
        starknet::{
            get_caller_address, get_block_timestamp, get_contract_address, ContractAddress,
            event::EventEmitter,
        },
    };

    use openzeppelin::{
        account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait},
        utils::{
            snip12::{OffchainMessageHash, SNIP12Metadata}, cryptography::nonces::NoncesComponent,
            cryptography::nonces::NoncesComponent::InternalImpl,
        },
        token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait},
    };

    use crate::{types::{FundMateRequest, StructHashImpl}, interfaces::IFundMate};

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        SplitPaymentExecuted: SplitPaymentExecuted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SplitPaymentExecuted {
        #[key]
        pub topic: felt252,
        #[key]
        pub coordinator: ContractAddress,
        pub token_address: ContractAddress,
    }

    pub mod Errors {
        pub const EXPIRED_SIGNATURE: felt252 = 'Signature: Expired';
        pub const INVALID_SIGNATURES_LENGTH: felt252 = 'Signature: Invalid length';
        pub const INVALID_SIGNATURE: felt252 = 'Signature: Invalid signature';
        pub const NOT_ENOUGH_FUNDS_COLLECTED: felt252 = 'Amount: Not enough collected';
        pub const TOKEN_TRANSFER_FAILED: felt252 = 'Token transfer: Failed';
    }


    const APP_NAME: felt252 = 'FUND_MATE';
    const APP_VERSION: felt252 = 'v0.1.0';


    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            APP_NAME
        }

        fn version() -> felt252 {
            APP_VERSION
        }
    }

    #[abi(embed_v0)]
    impl FundMateImpl of IFundMate<ContractState> {
        fn execute_signed_request(
            ref self: ContractState, request: FundMateRequest, signatures: Array<Array<felt252>>,
        ) {
            assert(get_block_timestamp() <= request.expiry, Errors::EXPIRED_SIGNATURE);
            let coordinator = get_caller_address();
            self.nonces.use_checked_nonce(coordinator, request.nonce);

            assert(
                signatures.len() == request.participants_info.len(),
                Errors::INVALID_SIGNATURES_LENGTH,
            );

            let mut total_amount: u256 = 0;
            for participant_info in request.participants_info {
                total_amount += (*participant_info).amount;
            };

            assert(total_amount >= request.amount, Errors::NOT_ENOUGH_FUNDS_COLLECTED);

            let participants_len: usize = request.participants_info.len();

            // check signatures
            let i: usize = 0;
            while i != participants_len {
                let signer = (*request.participants_info[i]).address;
                let hash = request.get_message_hash(signer);
                assert(
                    ISRC6Dispatcher { contract_address: signer }
                        .is_valid_signature(hash, signatures[i].clone()) == starknet::VALIDATED,
                    Errors::INVALID_SIGNATURE,
                );
            };

            let token_dispatcher = ERC20ABIDispatcher { contract_address: request.token_address };

            let this_address = get_contract_address();
            // transfer tokens from each user account to this contract
            let i: usize = 0;
            while i != participants_len {
                let payer = (*request.participants_info[i]).address;
                assert(
                    token_dispatcher
                        .transfer_from(
                            payer, this_address, (*request.participants_info[i]).amount,
                        ) == bool::True,
                    Errors::TOKEN_TRANSFER_FAILED,
                );
            };

            // after payments are collected, trasfer to the receiver
            token_dispatcher.transfer(request.receiver, request.amount);

            self
                .emit(
                    SplitPaymentExecuted {
                        topic: request.topic,
                        coordinator: coordinator,
                        token_address: request.token_address,
                    },
                )
        }
    }
}
