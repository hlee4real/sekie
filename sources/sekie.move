module admin::sekie{
    use std::signer;
    use std::string::{String};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_token::token::{Self,check_collection_exists,direct_transfer};
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::bcs::to_bytes;

    struct CollectionPool has key {
        //this collection name can be whitelisted by module manager
        collection_name: String,
        creator: address,
        apy: u64,
        days: u64,
        state: bool,
        total_amount: u64,
        cap: account::SignerCapability,
    }

    struct Lender has drop, key {
        borrower: address,
        collection_name: String,
        offer_amount: u64,
        start_time: u64,
        offered_is_made: bool,
        apy: u64,
        days: u64,
    }

    struct Borrower has drop, key {
        lender: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        receiver_amount: u64,
        start_time: u64,
        apy: u64,
        days: u64,
    }

    struct ResourceInfo has key {
        resource_map : SimpleMap<String, address>,
    }

    const E_NO_COLLECCION: u64 = 0;
    const E_NOT_INITIALIZED: u64 = 1;
    const E_NOT_ADDRESS: u64 = 2;
    const E_NO_TOKEN_IN_TOKEN_STORE:u64=3;
    const E_STOPPED:u64=4;
    const E_ALREADY_INITIALIZED:u64=5;
    const E_ADDRESS_MISMATCH:u64=6;
    const E_INSUFFICIENT_FUND:u64=7;
    const E_NOT_MODULE_CREATOR:u64=8;
    const E_COLLECTION_MISMATCH:u64=9;
    const E_LOAN_TAKEN:u64=10;
    const E_LOAN_NOT_TAKEN:u64=11;
    const E_DAYS_PASSED:u64=12;

    //only module manager call it, to create a new pool with collection creator address, collection name, apy and number of days
    public entry fun init_collection_pool(owner: &signer,creator_addr: address, collection_name: String, apy: u64, days: u64) acquires ResourceInfo{
        let owner_address = signer::address_of(owner);
        assert!(owner_address == @admin, E_NOT_MODULE_CREATOR);
        assert!(check_collection_exists(creator_addr,collection_name), E_NO_COLLECCION);

        let (collection_pool, collection_cap) = account::create_resource_account(owner, to_bytes(&collection_name));
        let collection_pool_signer_cap = account::create_signer_with_capability(&collection_cap);
        let collection_pool_address = signer::address_of(&collection_pool);
        assert!(!exists<CollectionPool>(collection_pool_address), E_ALREADY_INITIALIZED);

        if (!exists<ResourceInfo>(owner_address)) {
            move_to(owner, ResourceInfo { resource_map: simple_map::create() })
        };
        let maps = borrow_global_mut<ResourceInfo>(owner_address);
        simple_map::add(&mut maps.resource_map, collection_name,collection_pool_address);

        //create resource in collection pool signer cap with resource is CollectionPool
        move_to<CollectionPool>(&collection_pool_signer_cap, CollectionPool{
            collection_name,
            creator: creator_addr,
            apy,
            days,
            state: true,
            total_amount: 0,
            cap: collection_cap,
        });
    }

    //use to update apy, days and state of collection pool
    public entry fun update_pool(owner: &signer, collection_name: String, apy: u64, days: u64,state: bool) acquires ResourceInfo, CollectionPool{
        let owner_address = signer::address_of(owner);
        let collection_pool_address = get_resource_address(owner_address, collection_name);
        assert!(exists<CollectionPool>(collection_pool_address), E_NOT_INITIALIZED);

        let data = borrow_global_mut<CollectionPool>(collection_pool_address);
        data.apy = apy;
        data.days = days;
        data.state = state;
    }

    public entry fun lender_offer<CoinType>(lender: &signer, collection_name: String, offer_amount: u64) acquires CollectionPool, ResourceInfo{
        let collection_pool_address = get_resource_address(@admin,collection_name);

        //verify if collection pool is initialized
        assert!(exists<CollectionPool>(collection_pool_address), E_NOT_INITIALIZED);
        let data = borrow_global_mut<CollectionPool>(collection_pool_address);
        //verify if collection pool is stopped
        assert!(data.state, E_STOPPED);
        data.total_amount = data.total_amount + offer_amount;
        let pool_signer_from_cap = account::create_signer_with_capability(&data.cap);

        //register coinstore for resource account in each collection pool
        if(!coin::is_account_registered<CoinType>(collection_pool_address)){
            managed_coin::register<CoinType>(&pool_signer_from_cap);
        };
        coin::transfer<CoinType>(lender, collection_pool_address, offer_amount);
        move_to<Lender>(lender, Lender{
            borrower: @admin,
            collection_name,
            offer_amount,
            start_time: 0,
            offered_is_made: false,
            apy: 0,
            days: 0,
        });
    }

    public entry fun lender_revoke<CoinType>(lender: &signer, collection_name:String) acquires ResourceInfo, Lender, CollectionPool{
        let lender_address = signer::address_of(lender);
        let collection_pool_address = get_resource_address(@admin,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address), E_NOT_INITIALIZED);
        let data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&data.cap);
        assert!(data.state, E_STOPPED);
        let lender_data = borrow_global_mut<Lender>(lender_address);
        assert!(lender_data.collection_name == collection_name, E_COLLECTION_MISMATCH);
        assert!(lender_data.offered_is_made == false, E_LOAN_TAKEN);
        data.total_amount = data.total_amount - lender_data.offer_amount;
        coin::transfer<CoinType>(&pool_signer_from_cap, lender_address, lender_data.offer_amount);
        let revoke_data = move_from<Lender>(lender_address);
        let Lender{
            borrower:_,
            collection_name:_,
            offer_amount:_,
            start_time:_,
            offered_is_made:_,
            apy:_,
            days:_,
        } = revoke_data;
    }

    public entry fun borrow_select<CoinType>(borrower: &signer, collection_name: String, token_name: String, property_version: u64, lender: address) acquires CollectionPool, ResourceInfo, Lender{
        let borrower_address = signer::address_of(borrower);
        let collection_pool_address = get_resource_address(@admin,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address), E_NOT_INITIALIZED);

        let data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&data.cap);
        assert!(data.state, E_STOPPED);

        let now = aptos_framework::timestamp::now_seconds();
        assert!(exists<Lender>(lender), E_NOT_INITIALIZED);

        let lender_data = borrow_global_mut<Lender>(lender);
        assert!(lender_data.collection_name == collection_name, E_COLLECTION_MISMATCH);
        assert!(lender_data.offered_is_made == false, E_LOAN_TAKEN);
        lender_data.offered_is_made = true;
        lender_data.start_time = now;
        lender_data.apy = data.apy;
        lender_data.days = data.days;
        lender_data.borrower = borrower_address;

        let token_id = token::create_token_id_raw(data.creator,collection_name, token_name, property_version);
        assert!(token::balance_of(borrower_address, token_id) >= 1, E_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(borrower, &pool_signer_from_cap, token_id, 1);
        move_to<Borrower>(borrower, Borrower{
            lender,
            collection_name,
            start_time: now,
            apy: data.apy,
            days: data.days,
            receiver_amount: lender_data.offer_amount,
            property_version,
            token_name,
        });
        coin::transfer<CoinType>(&pool_signer_from_cap, borrower_address, lender_data.offer_amount);
    }

    public entry fun borrower_pay_loan<CoinType>(borrower: &signer, collection_name: String, token_name: String) acquires CollectionPool, ResourceInfo, Borrower, Lender{
        let borrower_address = signer::address_of(borrower);
        let now = aptos_framework::timestamp::now_seconds();
        assert!(exists<Borrower>(borrower_address),E_LOAN_NOT_TAKEN);

        let borrower_data = borrow_global_mut<Borrower>(borrower_address);
        let collection_pool_address = get_resource_address(@admin,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address), E_NOT_INITIALIZED);

        let data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&data.cap);
        assert!(data.state, E_STOPPED);
        assert!(exists<Lender>(borrower_data.lender), E_NOT_INITIALIZED);

        let lender_data = borrow_global_mut<Lender>(borrower_data.lender);
        assert!(lender_data.offered_is_made==true, E_LOAN_NOT_TAKEN);

        let days = (now - borrower_data.start_time) / 86400;
        assert!(days <= borrower_data.days, E_DAYS_PASSED);

        if (days < borrower_data.days && days % 86400 != 0) {
            //to-do: handle rounding, example: days = 8000/86400 -> days = 0 but it should be 1
            days = days + 1;
        };

        let interest_amt =  days * borrower_data.apy / 100 / 365 * borrower_data.receiver_amount; //example: APY = 160% and days = 10, receiver_amount = 98864000 then interest_amt = 160/100/365 * 10 * 98864000 = 4333764
        let total_amt = interest_amt + borrower_data.receiver_amount;
        let token_id = token::create_token_id_raw(data.creator,collection_name, token_name, borrower_data.property_version);
        assert!(token::balance_of(collection_pool_address, token_id) >= 1, E_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(&pool_signer_from_cap, borrower, token_id, 1);
        coin::transfer<CoinType>(borrower,  borrower_data.lender, total_amt);
        data.total_amount = data.total_amount - borrower_data.receiver_amount;

        let lender_drop_data = move_from<Lender>(borrower_data.lender);
        let Lender{
            borrower:_,
            collection_name:_,
            offer_amount:_,
            start_time:_,
            offered_is_made:_,
            apy:_,
            days:_,
        } = lender_drop_data;

        let borrower_drop_data = move_from<Borrower>(borrower_address);
        let Borrower{
            lender:_,
            collection_name:_,
            start_time:_,
            apy:_,
            days:_,
            receiver_amount:_,
            property_version:_,
            token_name:_,
        } = borrower_drop_data;
    }

    public entry fun lender_claim_token(lender: &signer, collection_name: String, token_name: String) acquires CollectionPool, Lender, Borrower, ResourceInfo{
        let lender_address = signer::address_of(lender);
        let collection_pool_address = get_resource_address(@admin,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address), E_NOT_INITIALIZED);

        let data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&data.cap);
        assert!(data.state, E_STOPPED);
        assert!(exists<Lender>(lender_address), E_NOT_INITIALIZED);

        let lender_data = borrow_global_mut<Lender>(lender_address);
        assert!(lender_data.offered_is_made == true, E_LOAN_NOT_TAKEN);
        let now = aptos_framework::timestamp::now_seconds();
        let days = (now - lender_data.start_time) / 86400;
        assert!(days >= lender_data.days, E_DAYS_PASSED);
        assert!(exists<Borrower>(lender_data.borrower), E_LOAN_NOT_TAKEN);
        let borrower_data = borrow_global_mut<Borrower>(lender_data.borrower);
        data.total_amount = data.total_amount - borrower_data.receiver_amount;

        let token_id = token::create_token_id_raw(data.creator,collection_name, token_name, borrower_data.property_version);
        assert!(token::balance_of(collection_pool_address, token_id) >= 1, E_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(&pool_signer_from_cap, lender, token_id, 1);

        let borrower_drop_data = move_from<Borrower>(lender_data.borrower);
        let Borrower{
            lender:_,
            collection_name:_,
            start_time:_,
            apy:_,
            days:_,
            receiver_amount:_,
            property_version:_,
            token_name:_,
        } = borrower_drop_data;

        let lender_drop_data = move_from<Lender>(lender_address);
        let Lender{
            borrower:_,
            collection_name:_,
            offer_amount:_,
            start_time:_,
            offered_is_made:_,
            apy:_,
            days:_,
        } = lender_drop_data;
    }

    fun get_resource_address(addr:address,string:String): address acquires ResourceInfo {
        assert!(exists<ResourceInfo>(addr), E_NOT_ADDRESS);
        let maps = borrow_global<ResourceInfo>(addr);
        let res_address = *simple_map::borrow(&maps.resource_map, &string);
        res_address
    }
}