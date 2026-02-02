module hot_potato::demo {
    use std::signer;
    use std::option;
    use std::string;
    use cedra_framework::object::{Self, Object};
    use cedra_framework::fungible_asset::{Self, Metadata, MintRef, TransferRef, BurnRef};
    use cedra_framework::primary_fungible_store;
    use hot_potato::flash_loan;

    const TEST_COIN_SEED: vector<u8> = b"TEST_COIN_LIVE_3";

    /// Restored for backward compatibility
    struct TestCoinCapabilities has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    /// Stores the latest created vault for easy retrieval in the demo
    struct LatestVault has key {
        vault: Object<flash_loan::Vault>
    }

    /// initialize the demo: create coin, mint to user, create vault, deposit logic.
    public entry fun init_demo(sender: &signer) {
        // 1. Create the Test Coin Object
        let constructor_ref = object::create_named_object(sender, TEST_COIN_SEED);
        
        // 2. Create FA Metadata
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"Hot Potato Test Coin"),
            string::utf8(b"HPT"),
            6,
            string::utf8(b"http://example.com/icon.png"),
            string::utf8(b"http://example.com"),
        );

        // 3. Generate Refs
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);

        let metadata_obj = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        // 4. Mint initial supply to sender (1M tokens)
        let sender_addr = signer::address_of(sender);
        primary_fungible_store::mint(&mint_ref, sender_addr, 1_000_000_000_000);

        // 5. Store refs (Compat + Good practice)
        let coin_signer = object::generate_signer(&constructor_ref);
        move_to(&coin_signer, TestCoinCapabilities {
            mint_ref,
            transfer_ref,
            burn_ref
        });

        // 6. Create Flash Loan Vault (Fee: 0.1% = 10 bps)
        let vault_obj = flash_loan::create_vault(sender, metadata_obj, 10);

        // 7. Deposit liquidity into vault (500k tokens)
        flash_loan::deposit_from(sender, vault_obj, metadata_obj, 500_000_000_000);
        
        // 8. Store the Vault object wrapper on the sender for easy access
        move_to(sender, LatestVault { vault: vault_obj });
    }

    /// Legacy manual function (kept for compatibility)
    public entry fun run_flash_loan(
        borrower: &signer, 
        vault_obj: Object<flash_loan::Vault>, 
        amount: u64
    ) {
        let borrower_addr = signer::address_of(borrower);
        
        let (loaned_assets, receipt) = flash_loan::borrow(vault_obj, amount);
        let metadata = flash_loan::vault_metadata(vault_obj);

        primary_fungible_store::deposit(borrower_addr, loaned_assets);

        let fee_bps = flash_loan::vault_fee_bps(vault_obj);
        let fee = (amount * fee_bps) / 10_000;
        let total_repay = amount + fee;

        let repayment_assets = primary_fungible_store::withdraw(borrower, metadata, total_repay);
        flash_loan::repay(vault_obj, repayment_assets, receipt);
    }

    /// AUTO function: Uses LatestVault
    public entry fun run_flash_loan_auto(
        borrower: &signer, 
        amount: u64
    ) acquires LatestVault {
        let borrower_addr = signer::address_of(borrower);
        
        let vault_wrapper = borrow_global<LatestVault>(borrower_addr);
        run_flash_loan(borrower, vault_wrapper.vault, amount);
    }
}
