#[starknet::contract]
pub mod FundMate {
    use core::num::traits::Zero;
    use starknet::storage::StoragePointerWriteAccess;
    use starknet::storage::StoragePathEntry;
    use NoncesComponent::InternalTrait;
    use core::{
        bool,
        starknet::{
            get_caller_address, get_block_timestamp, get_contract_address, ContractAddress,
            event::EventEmitter,
            storage::{Vec, MutableVecTrait, Map, StorageMapReadAccess, StoragePointerReadAccess},
        },
        poseidon::{PoseidonTrait, PoseidonImpl}, hash::{HashStateTrait, HashStateExTrait},
    };

    use openzeppelin::{
        account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait},
        utils::{
            snip12::{OffchainMessageHash, SNIP12Metadata}, cryptography::nonces::NoncesComponent,
            cryptography::nonces::NoncesComponent::InternalImpl,
        },
        token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait},
    };

    use crate::{types::{FundMateRequest, ParticipantInfo, StructHashImpl}, interfaces::IFundMate};

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        split_payment_info: Map<felt252, SplitPaymentInfo>,
        split_payment_participants_amounts: Map<felt252, Map<ContractAddress, u256>>,
        split_payment_payers: Map<felt252, Map<ContractAddress, bool>>,
        split_payment_participants: Map<felt252, Vec<ContractAddress>>,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        SplitPaymentCreated: SplitPaymentCreated,
        SignedSplitPaymentExecuted: SignedSplitPaymentExecuted,
        ContributionPayed: ContributionPayed,
        SplitPaymentFinalised: SplitPaymentFinalised,
        RefundContributor: RefundContributor,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SignedSplitPaymentExecuted {
        #[key]
        pub topic: felt252,
        #[key]
        pub coordinator: ContractAddress,
        pub token_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SplitPaymentCreated {
        pub request_id: felt252,
        #[key]
        pub coordinator: ContractAddress,
        #[key]
        pub topic: felt252,
        pub receiver: ContractAddress,
        pub amount: u256,
        pub participants_info: Array<ParticipantInfo>,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContributionPayed {
        #[key]
        pub request_id: felt252,
        #[key]
        pub payer: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SplitPaymentFinalised {
        #[key]
        pub request_id: felt252,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RefundContributor {
        #[key]
        pub contributor: ContractAddress,
        #[key]
        pub request_id: felt252,
        pub amount: u256,
    }

    pub mod Errors {
        pub const EXPIRED_SIGNATURE: felt252 = 'Signature: Expired';
        pub const INVALID_SIGNATURES_LENGTH: felt252 = 'Signature: Invalid length';
        pub const INVALID_SIGNATURE: felt252 = 'Signature: Invalid signature';
        pub const NOT_ENOUGH_FUNDS_COLLECTED: felt252 = 'Amount: Not enough collected';
        pub const AMOUNTS_DONT_ADD_UP: felt252 = 'Amount: Amounts don\'t add up';
        pub const TOKEN_TRANSFER_FAILED: felt252 = 'Token transfer: Failed';
        pub const PARTICIPANTS_AMOUNTS_NOT_MATCH: felt252 = 'Participant: Amount not match';
        pub const INVALID_EXPIRATION_TIMESTAMP: felt252 = 'Expiration: Invalid expiration';
        pub const PAYMENT_REQUEST_EXPIRED: felt252 = 'Expiration: Request expired';
        pub const NOT_EXPIRED: felt252 = 'Expiration: Not expired';
        pub const INVALID_PAYMENT_REQUEST_ID: felt252 = 'Payment: Invalid Request ID';
        pub const PARTICIPANT_NOT_PAID: felt252 = 'Payment: Participant not paid';
        pub const PAYMENT_IS_FINALISED: felt252 = 'Payment: Finalised';
        pub const PAYMENT_NOT_PAID: felt252 = 'Payment: Not paid';
        pub const ALREADY_REFUNDED: felt252 = 'Refund: Already refunded';
    }

    #[derive(Drop, starknet::Store)]
    struct SplitPaymentInfo {
        coordinator: ContractAddress,
        amount: u256,
        token_payment_address: ContractAddress,
        receiver: ContractAddress,
        topic: felt252,
        expiration: u64,
        finalised: bool,
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
                    SignedSplitPaymentExecuted {
                        topic: request.topic,
                        coordinator: coordinator,
                        token_address: request.token_address,
                    },
                )
        }


        fn create_split_payment_request(
            ref self: ContractState,
            receiver: ContractAddress,
            topic: felt252,
            amount: u256,
            expiration: u64,
            token_payment_address: ContractAddress,
            participants_info: Array<ParticipantInfo>,
        ) {
            assert(get_block_timestamp() < expiration, Errors::INVALID_EXPIRATION_TIMESTAMP);
            let coordinator = get_caller_address();
            let nonce = self.nonces.use_nonce(coordinator);

            let request_id = compute_request_id(coordinator, topic, nonce);
            let participants_amounts_storage_path = self
                .split_payment_participants_amounts
                .entry(request_id);

            let split_payment_participants_path = self.split_payment_participants.entry(request_id);

            let mut total_amount: u256 = 0;
            for participant_info in participants_info.clone() {
                total_amount += participant_info.amount;
                participants_amounts_storage_path
                    .entry(participant_info.address)
                    .write(participant_info.amount);
                split_payment_participants_path.append().write(participant_info.address);
            };

            assert(total_amount >= amount, Errors::AMOUNTS_DONT_ADD_UP);

            self
                .split_payment_info
                .entry(request_id)
                .write(
                    SplitPaymentInfo {
                        coordinator: coordinator,
                        amount: amount,
                        token_payment_address: token_payment_address,
                        receiver: receiver,
                        topic: topic,
                        expiration: expiration,
                        finalised: bool::False,
                    },
                );

            self
                .emit(
                    SplitPaymentCreated {
                        request_id: request_id,
                        coordinator: coordinator,
                        amount: amount,
                        receiver: receiver,
                        topic: topic,
                        participants_info: participants_info,
                    },
                );
        }

        fn pay_contribution(ref self: ContractState, request_id: felt252, amount: u256) {
            let split_payment_info = self.split_payment_info.entry(request_id).read();
            assert(
                split_payment_info.coordinator.is_non_zero(), Errors::INVALID_PAYMENT_REQUEST_ID,
            );
            assert(split_payment_info.finalised == bool::False, Errors::PAYMENT_IS_FINALISED);
            assert(
                split_payment_info.expiration > get_block_timestamp(),
                Errors::PAYMENT_REQUEST_EXPIRED,
            );

            let payer = get_caller_address();

            let amount_owe = self
                .split_payment_participants_amounts
                .entry(request_id)
                .entry(payer)
                .read();

            assert(amount_owe == amount, Errors::PARTICIPANTS_AMOUNTS_NOT_MATCH);

            let token_dispatcher = ERC20ABIDispatcher {
                contract_address: split_payment_info.token_payment_address,
            };

            let this_address = get_contract_address();

            assert(
                token_dispatcher.transfer_from(payer, this_address, amount) == bool::True,
                Errors::TOKEN_TRANSFER_FAILED,
            );

            self.split_payment_payers.entry(request_id).entry(payer).write(bool::True);

            self.emit(ContributionPayed { request_id: request_id, payer: payer, amount: amount });
        }

        fn finalize_payment(ref self: ContractState, request_id: felt252) {
            let split_payment_info = self.split_payment_info.read(request_id);
            assert(
                split_payment_info.expiration > get_block_timestamp(),
                Errors::PAYMENT_REQUEST_EXPIRED,
            );
            assert(split_payment_info.finalised == bool::False, Errors::PAYMENT_IS_FINALISED);
            assert(
                split_payment_info.coordinator.is_non_zero(), Errors::INVALID_PAYMENT_REQUEST_ID,
            );

            let participants_storage_path = self.split_payment_participants.entry(request_id);
            let participants_len = participants_storage_path.len();

            let mut i = 0;

            while i < participants_len {
                let participant_address = participants_storage_path.at(i).read();
                let participant_paid: bool = self
                    .split_payment_payers
                    .entry(request_id)
                    .entry(participant_address)
                    .read();

                assert(participant_paid == bool::True, Errors::PARTICIPANT_NOT_PAID);
                i += 1;
            };

            let token_dispatcher = ERC20ABIDispatcher {
                contract_address: split_payment_info.token_payment_address,
            };

            assert(
                token_dispatcher
                    .transfer(split_payment_info.receiver, split_payment_info.amount) == bool::True,
                Errors::TOKEN_TRANSFER_FAILED,
            );

            self.split_payment_info.entry(request_id).finalised.write(bool::True);

            self
                .emit(
                    SplitPaymentFinalised {
                        request_id: request_id, amount: split_payment_info.amount,
                    },
                )
        }

        fn refund(ref self: ContractState, request_id: felt252) {
            let split_payment_info = self.split_payment_info.read(request_id);

            assert(split_payment_info.expiration < get_block_timestamp(), Errors::NOT_EXPIRED);

            let contributor = get_caller_address();

            assert(
                self.split_payment_payers.entry(request_id).entry(contributor).read() == bool::True,
                Errors::PAYMENT_NOT_PAID,
            );

            let paid_amount = self
                .split_payment_participants_amounts
                .entry(request_id)
                .entry(contributor)
                .read();

            assert(paid_amount.is_non_zero(), Errors::ALREADY_REFUNDED);

            self.split_payment_participants_amounts.entry(request_id).entry(contributor).write(0);

            let token_dispatcher = ERC20ABIDispatcher {
                contract_address: split_payment_info.token_payment_address,
            };

            assert(
                token_dispatcher.transfer(contributor, paid_amount) == bool::True,
                Errors::TOKEN_TRANSFER_FAILED,
            );

            self
                .emit(
                    RefundContributor {
                        contributor: contributor, request_id: request_id, amount: paid_amount,
                    },
                )
        }


        fn check_contribution(
            self: @ContractState, payer: ContractAddress, request_id: felt252,
        ) -> u256 {
            let amount_owe = self
                .split_payment_participants_amounts
                .entry(request_id)
                .entry(payer)
                .read();
            amount_owe
        }
    }

    fn compute_request_id(coordinator: ContractAddress, topic: felt252, nonce: felt252) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(coordinator).update_with(topic).update_with(nonce).finalize()
    }
}
