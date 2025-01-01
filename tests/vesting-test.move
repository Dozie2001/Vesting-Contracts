module vesting::vesting_test {
    use std::signer;
    use aptos_framework::test;
    use aptos_framework::test_account;
    use aptos_framework::timestamp;
    use aptos_framework::error;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object;
    use aptos_std::option;
    use aptos_std::simple_map;
    use aptos_std::string;
    use aptos_std::debug;

    // Import everything we need from your vesting module
    use vesting::vesting::{
        Self as VestingModule,
        Vesting,
        VestingStream,
        create,
        add_stream,
        claim_tokens,
        claimable_balance,
        vested_balance,
        ERR_NOT_OWNER,
        ERR_INVALID_TIME,
        ERR_ZERO_AMOUNT,
        ERR_INVALID_DURATION,
        ERR_USER_STREAM_EXISTS,
        ERR_INSUFFICIENT_BALANCE,
        ERR_USER_STREAM_DOES_NOT_EXIST
    };

    // Helper function: create a dummy token metadata.
    // You can customize name/symbol/decimals.
    fun create_dummy_fa_metadata(): Metadata {
        let dummy_name = string::utf8(b"Dummy Token");
        let dummy_symbol = string::utf8(b"DUM");
        let dummy_decimals = 6;
        Metadata {
            name: dummy_name,
            symbol: dummy_symbol,
            decimals: dummy_decimals,
        }
    }

    // Helper function: create an `Object<Metadata>` in test context.
    fun create_fa_object(acct: &signer): object::Object<Metadata> {
        let metadata = create_dummy_fa_metadata();
        let obj = object::create_object(signer::address_of(acct));
        let tx_ref = object::generate_transfer_ref(&obj);
        object::disable_ungated_transfer(&tx_ref);

        let signer_for_obj = object::generate_signer(&obj);
        move_to(&signer_for_obj, metadata);

        // Return as an object
        object::Object<Metadata>{ id: object::object_address(&obj) }
    }

    // Helper function: mint tokens into an account’s primary_fungible_store.
    // Adjust to match how your actual token or faucet logic works in your system.
    fun mint_tokens(acct: &signer, fa_metadata: object::Object<Metadata>, amount: u64) {
        primary_fungible_store::deposit(acct, fa_metadata, amount);
    }

    // If your environment supports time simulation, you can use a helper to increment time:
    fun advance_time_by(seconds: u64) {
        // For local tests, this might be `timestamp::simulate_incr_time(seconds);`
        timestamp::simulate_incr_time(seconds);
    }

    /// 1) Test the creation of a Vesting object
    #[test]
    fun test_create_vesting() {
        let alice = test_account::create_test_account();
        let fa_metadata = create_fa_object(&alice);

        // Call the vesting::create function
        create(&alice, fa_metadata);

        // Ensure vesting resource was published by checking the object’s address
        let vesting_addr_opt = object::fetch_object_address_from_owner<Vesting>(
            signer::address_of(&alice)
        );
        assert!(vesting_addr_opt.is_some(), 100 /* arbitrary error code if not found */);

        debug::print(&string::utf8(b"Vesting object creation test passed."));
    }

    /// 2) Test adding a valid stream
    #[test]
    fun test_add_stream_valid() {
        let alice = test_account::create_test_account();
        let bob = test_account::create_test_account();

        let fa_metadata = create_fa_object(&alice);
        create(&alice, fa_metadata);

        // Mint tokens to Alice so she can add a stream
        let mint_amount = 1_000_000;
        mint_tokens(&alice, fa_metadata, mint_amount);

        // Get the vesting object address
        let vesting_addr_opt = object::fetch_object_address_from_owner<Vesting>(
            signer::address_of(&alice)
        );
        let vesting_addr = option::borrow(&vesting_addr_opt).copy();

        let now = timestamp::now_seconds();
        let start_time = now + 50; // must be >= now per the contract
        let duration = 1000;
        let cliff = 200;

        // Add stream
        add_stream(
            &alice,
            object::Object<Vesting>{ id: vesting_addr },
            signer::address_of(&bob),  // beneficiary
            10_000,                    // amount
            start_time,
            duration,
            cliff
        );

        // If we get here without abort, it worked!
        debug::print(&string::utf8(b"Added valid stream successfully."));
    }

    /// 3) Test adding a stream with insufficient token balance
    /// Expect: ERR_INSUFFICIENT_BALANCE
    #[test]
    fun test_add_stream_insufficient_balance() {
        let alice = test_account::create_test_account();
        let bob = test_account::create_test_account();

        let fa_metadata = create_fa_object
