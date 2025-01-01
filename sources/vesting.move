module vesting::vesting {
    use std::signer;
    use aptos_std::math64;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Self, ExtendRef, Object, ObjectGroup};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    #[resource_group_member(group = ObjectGroup)]
    struct Vesting has key {
        extend_ref: ExtendRef,
        /// Identifies type of datat to be transferred
        fa_metadata: Object<Metadata>,
        streams: SimpleMap<address, VestingStream>,
    }

    struct VestingStream has store {
        /// Beneficiary of the stream
        beneficiary: address,
        /// Total amount of tokens to be vested
        amount: u64,
        /// Start time of the stream
        start_time: u64,
        /// Cliff time (in seconds from start_time)
        cliff: u64,
        /// Total duration of the vesting (in seconds)
        duration: u64,
        /// Amount of tokens claimed
        claimed: u64,
    }


    const ERR_NOT_OWNER: u64 = 0;
    const ERR_INVALID_TIME: u64 = 1;
    const ERR_ZERO_AMOUNT: u64 = 2;
    const ERR_INVALID_DURATION: u64 = 3;
    const ERR_USER_STREAM_EXISTS: u64 = 4;
    const ERR_INSUFFICIENT_BALANCE: u64 = 5;
    const ERR_USER_STREAM_DOES_NOT_EXIST: u64 = 6;

    /// Create a new Vesting
    public fun create(account: &signer, fa_metadata: Object<Metadata>) {
        /// acount address of signer
        let account_addr = signer::address_of(account);
        let constructor_ref = object::create_object(account_addr);
        object::disable_ungated_transfer(&object::generate_transfer_ref(&constructor_ref));

        let object_signer = object::generate_signer(&constructor_ref);

        move_to(&object_signer, Vesting {
            fa_metadata,
            streams: simple_map::new(),
            extend_ref: object::generate_extend_ref(&constructor_ref)
        });
    }

    public fun add_stream(
        account: &signer,
        vesting: Object<Vesting>,
        beneficiary: address,
        amount: u64,
        start_time: u64,
        duration: u64,
        cliff: u64
    ) acquires Vesting {
        let account_addr = signer::address_of(account);

        assert!(object::is_owner(vesting, account_addr), ERR_NOT_OWNER);
        assert!(start_time >= timestamp::now_seconds(), ERR_INVALID_TIME);
        assert!(duration != 0, ERR_INVALID_DURATION);
        assert!(duration >= cliff, ERR_INVALID_TIME);
        assert!(amount != 0, ERR_ZERO_AMOUNT);

        let vesting_address = object::object_address(&vesting);
        let vesting_mut_ref = borrow_global_mut<Vesting>(vesting_address);
        /// check if vesting stream exists already
        assert!(!simple_map::contains_key(&vesting_mut_ref.streams, &beneficiary), ERR_USER_STREAM_EXISTS);

        let stream = VestingStream {
            beneficiary,
            amount,
            duration,
            cliff,
            start_time,
            claimed: 0
        };

        simple_map::add(&mut vesting_mut_ref.streams, beneficiary, stream);

        let fa_balance = primary_fungible_store::balance(account_addr, vesting_mut_ref.fa_metadata);
        assert!(fa_balance >= amount, ERR_INSUFFICIENT_BALANCE);

        primary_fungible_store::transfer(account, vesting_mut_ref.fa_metadata, vesting_address, amount);
    }

    public entry fun claim_tokens(account: &signer, vesting: Object<Vesting>) acquires Vesting {
        let beneficiary = signer::address_of(account);
        let claimable = claimable_balance(vesting, beneficiary);

        let vesting_address = object::object_address(&vesting);
        let vesting_mut_ref = borrow_global_mut<Vesting>(vesting_address);
        let stream_ref_mut = simple_map::borrow_mut(&mut vesting_mut_ref.streams, &beneficiary);

        stream_ref_mut.claimed = stream_ref_mut.claimed + claimable;

        let vesting_signer = object::generate_signer_for_extending(&vesting_mut_ref.extend_ref);
        let fa_balance = primary_fungible_store::balance(vesting_address, vesting_mut_ref.fa_metadata);
        assert!(fa_balance >= claimable, ERR_INSUFFICIENT_BALANCE);

        primary_fungible_store::transfer(&vesting_signer, vesting_mut_ref.fa_metadata, vesting_address, claimable);
    }

    public fun claimable_balance(vesting: Object<Vesting>, beneficiary: address): u64 acquires Vesting {
        let vesting_address = object::object_address(&vesting);
        let vesting_ref = borrow_global<Vesting>(vesting_address);

        assert!(simple_map::contains_key(&vesting_ref.streams, &beneficiary), ERR_USER_STREAM_DOES_NOT_EXIST);

        let stream_ref = simple_map::borrow(&vesting_ref.streams, &beneficiary);
        let vested = compute_vested_amount(stream_ref);
        if (vested > stream_ref.claimed) {
            return vested - stream_ref.claimed
        };

        return 0
    }

    public fun vested_balance(vesting: Object<Vesting>, beneficiary: address): u64 acquires Vesting {
        let vesting_address = object::object_address(&vesting);
        let vesting_ref = borrow_global_mut<Vesting>(vesting_address);

        assert!(simple_map::contains_key(&vesting_ref.streams, &beneficiary), ERR_USER_STREAM_DOES_NOT_EXIST);

        let stream_ref = simple_map::borrow_mut(&mut vesting_ref.streams, &beneficiary);
        compute_vested_amount(stream_ref)
    }

    fun compute_vested_amount(stream: &VestingStream): u64 {
        let now = timestamp::now_seconds();
        if (stream.start_time > now) return 0;

        let elapsed = now - stream.start_time;
        if (elapsed < stream.cliff) return 0;

        if (elapsed >= stream.duration) return stream.amount;

        let vested = math64::mul_div(stream.amount, elapsed, stream.duration);
        math64::min(vested, stream.amount)
    }
}