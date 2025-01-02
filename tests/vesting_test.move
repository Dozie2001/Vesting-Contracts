#[test_only]
module vesting::vesting_test {

    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{BurnRef, Metadata, MintRef};
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use vesting::vesting::Vesting;

    struct TestTokenInfo has key {
        metadata: Object<Metadata>,
        mint_ref: MintRef,
        burn_ref: BurnRef
    }

    fun initialize_test(): Object<Metadata> {
        // Initialize aptos time
        timestamp::set_time_has_started_for_testing(&framework_signer());

        let test_metadata = init_test_metadata();
        test_metadata
    }

    public fun init_test_metadata(): Object<Metadata> {
        let pkg_signer = pkg_signer();
        let constructor_ref = object::create_named_object(&pkg_signer, b"TEST");

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::some(100_000_000_000), // max supply
            string::utf8(b"TEST COIN"),
            string::utf8(b"TEST"),
            0,
            string::utf8(b"http://test.com/icon"),
            string::utf8(b"http://test.com"),
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        move_to(&pkg_signer(), TestTokenInfo { metadata, burn_ref, mint_ref });
        metadata
    }


    fun pkg_signer(): signer {
        account::create_signer_for_test(@vesting)
    }

    fun framework_signer(): signer {
        account::create_signer_for_test(@aptos_framework)
    }

    fun create_vesting(account: &signer, fa_metadata: Object<Metadata>): Object<Vesting> {
        vesting::vesting::create(account, fa_metadata);
        let vesting_maybe = vesting::vesting::last_created_vesting();
        assert!(option::is_some(&vesting_maybe), 0);
        option::destroy_some(vesting_maybe)
    }

    fun mint_test_token_to_account(account: &signer, amount: u64) acquires TestTokenInfo {
        let token_info = borrow_global<TestTokenInfo>(@vesting);

        let account_addr = signer::address_of(account);
        primary_fungible_store::ensure_primary_store_exists(account_addr, token_info.metadata);
        primary_fungible_store::mint(&token_info.mint_ref, account_addr, amount);
    }

    #[test(account = @0xFaDe)]
    public fun test_create_vesting(account: &signer) {
        let test_metadata = initialize_test();
        let vesting = create_vesting(account, test_metadata);

        assert!(vesting::vesting::total_streams(vesting) == 0, 0);
        assert!(vesting::vesting::fa_metadata(vesting) == test_metadata, 0);
    }

    #[test(account = @0xFaDe)]
    public fun test_create_vesting_add_stream(account: &signer) acquires TestTokenInfo {
        let test_metadata = initialize_test();
        let vesting = create_vesting(account, test_metadata);

        let cliff = 90;
        let amount = 10000;
        let duration = 10000;
        let beneficiary = @0xDade;
        let start_time = timestamp::now_seconds();

        mint_test_token_to_account(account, amount);
        vesting::vesting::add_stream(account, vesting, beneficiary, amount, start_time, duration, cliff);

        assert!(vesting::vesting::total_streams(vesting) == 1, 0);
        assert!(vesting::vesting::vested_balance(vesting, beneficiary) == 0, 0);
    }

    #[test(account = @0xFaDe)]
    #[expected_failure(abort_code = vesting::vesting::ERR_NOT_OWNER)]
    public fun test_add_stream_not_owner_failure(account: &signer) acquires TestTokenInfo {
        let test_metadata = initialize_test();
        let vesting = create_vesting(account, test_metadata);

        let cliff = 90;
        let amount = 10000;
        let duration = 10000;
        let beneficiary = @0xDade;
        let start_time = timestamp::now_seconds();

        mint_test_token_to_account(account, amount);

        let beneficiary_signer = account::create_signer_for_test(beneficiary);
        vesting::vesting::add_stream(&beneficiary_signer, vesting, beneficiary, amount, start_time, duration, cliff);
    }

    #[test(account = @0xFaDe)]
    public fun test_claim_stream(account: &signer) acquires TestTokenInfo {
        let test_metadata = initialize_test();
        let vesting = create_vesting(account, test_metadata);

        let cliff = 90;
        let amount = 10000;
        let duration = 10000;
        let beneficiary = @0xDade;
        let start_time = timestamp::now_seconds();

        mint_test_token_to_account(account, amount);
        vesting::vesting::add_stream(account, vesting, beneficiary, amount, start_time, duration, cliff);

        let beneficiary_signer = account::create_signer_for_test(beneficiary);

        timestamp::fast_forward_seconds(duration / 2);
        assert!(vesting::vesting::vested_balance(vesting, beneficiary) == amount / 2, 0);
        assert!(vesting::vesting::claimable_balance(vesting, beneficiary) == amount / 2, 0);

        vesting::vesting::claim_tokens(&beneficiary_signer, vesting);

        timestamp::fast_forward_seconds(duration / 2);
        assert!(vesting::vesting::vested_balance(vesting, beneficiary) == amount, 0);
        assert!(vesting::vesting::claimable_balance(vesting, beneficiary) == amount / 2, 0);

        vesting::vesting::claim_tokens(&beneficiary_signer, vesting);
        assert!(vesting::vesting::claimable_balance(vesting, beneficiary) == 0, 0);
    }
}