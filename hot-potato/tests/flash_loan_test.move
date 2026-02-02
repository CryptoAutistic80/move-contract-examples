#[test_only]
module hot_potato::flash_loan_test {
    use cedra_framework::fungible_asset::{Self, Metadata};
    use cedra_framework::object::{Self, Object};
    use cedra_framework::primary_fungible_store;
    use std::signer;
    use hot_potato::flash_loan;

    #[test_only]
    const FEE_BPS: u64 = 1_000; // 10%

    #[test_only]
    fun setup(
        asset: &signer,
        owner: &signer,
        borrower: &signer
    ): (Object<Metadata>, Object<flash_loan::Vault>) {
        let (creator_ref, metadata) = fungible_asset::create_test_token(asset);
        let (mint_ref, _transfer_ref, _burn_ref) =
            primary_fungible_store::init_test_metadata_with_primary_store_enabled(&creator_ref);

        let owner_address = signer::address_of(owner);
        let borrower_address = signer::address_of(borrower);

        primary_fungible_store::mint(&mint_ref, owner_address, 60);
        primary_fungible_store::mint(&mint_ref, borrower_address, 40);

        let fa_metadata: Object<Metadata> = object::convert(metadata);
        let vault_obj = flash_loan::create_vault(owner, fa_metadata, FEE_BPS);
        flash_loan::deposit_from(owner, vault_obj, fa_metadata, 40);

        (fa_metadata, vault_obj)
    }

    #[test(asset = @0xAAA, owner = @0xC0FFEE, borrower = @0xB0B0)]
    fun test_flash_loan_success(asset: &signer, owner: &signer, borrower: &signer) {
        let (fa_metadata, vault_obj) = setup(asset, owner, borrower);
        let borrower_address = signer::address_of(borrower);

        let borrow_amount = 20;
        let fee = (borrow_amount * FEE_BPS) / 10_000;

        let (loaned_assets, receipt) = flash_loan::borrow(vault_obj, borrow_amount);

        // Simulate use of the borrowed assets by routing through the borrower's primary store.
        primary_fungible_store::deposit(borrower_address, loaned_assets);
        let repayment = primary_fungible_store::withdraw(
            borrower,
            fa_metadata,
            borrow_amount + fee
        );

        flash_loan::repay(vault_obj, repayment, receipt);

        assert!(flash_loan::vault_balance(vault_obj) == 40 + fee);
        assert!(primary_fungible_store::balance(borrower_address, fa_metadata) == 40 - fee);
    }

    #[test(asset = @0xAAA, owner = @0xC0FFEE, borrower = @0xB0B0)]
    #[expected_failure(abort_code = 1, location = hot_potato::flash_loan)]
    fun test_insufficient_repayment(asset: &signer, owner: &signer, borrower: &signer) {
        let (fa_metadata, vault_obj) = setup(asset, owner, borrower);
        let borrower_address = signer::address_of(borrower);

        let borrow_amount = 20;
        let (loaned_assets, receipt) = flash_loan::borrow(vault_obj, borrow_amount);

        primary_fungible_store::deposit(borrower_address, loaned_assets);
        let repayment = primary_fungible_store::withdraw(borrower, fa_metadata, borrow_amount);

        flash_loan::repay(vault_obj, repayment, receipt);
    }
}
