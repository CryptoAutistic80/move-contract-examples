module hot_potato::flash_loan {
    use std::signer;
    use cedra_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, Metadata};
    use cedra_framework::object::{Self, ExtendRef, Object};
    use cedra_framework::primary_fungible_store;

    /// Error codes
    const E_INSUFFICIENT_REPAYMENT: u64 = 1;
    const E_VAULT_INSUFFICIENT_FUNDS: u64 = 2;
    const E_NOT_OWNER: u64 = 3;
    const E_INVALID_FEE_BPS: u64 = 4;
    const E_INVALID_AMOUNT: u64 = 5;
    const E_METADATA_MISMATCH: u64 = 6;

    /// The "Hot Potato" - no abilities.
    /// Enforces that the borrower must call `repay` in the same transaction.
    struct FlashReceipt {
        amount_borrowed: u64,
        fee: u64,
        metadata: Object<Metadata>,
    }

    #[resource_group_member(group = cedra_framework::object::ObjectGroup)]
    /// Flash loan vault for a single FA metadata.
    struct Vault has key {
        store: Object<FungibleStore>,
        store_extend_ref: ExtendRef,
        fee_bps: u64, // 100 = 1%
        owner: address,
    }

    /// Creates a new vault for the given FA metadata.
    public fun create_vault(
        owner: &signer,
        metadata: Object<Metadata>,
        fee_bps: u64
    ): Object<Vault> {
        assert!(fee_bps <= 10_000, E_INVALID_FEE_BPS);

        let constructor_ref = object::create_object(@0x0);
        let vault_address = object::address_from_constructor_ref(&constructor_ref);
        let vault_signer = object::generate_signer(&constructor_ref);

        let store_constructor_ref = object::create_object(vault_address);
        let store_extend_ref = object::generate_extend_ref(&store_constructor_ref);
        let store = fungible_asset::create_store(&store_constructor_ref, metadata);

        move_to(
            &vault_signer,
            Vault {
                store,
                store_extend_ref,
                fee_bps,
                owner: signer::address_of(owner),
            }
        );

        object::object_from_constructor_ref(&constructor_ref)
    }

    /// Entry wrapper for create_vault.
    public entry fun create_vault_entry(
        owner: &signer,
        metadata: Object<Metadata>,
        fee_bps: u64
    ) {
        create_vault(owner, metadata, fee_bps);
    }

    /// Deposit funds from the caller's primary store into the vault.
    public entry fun deposit_from(
        depositor: &signer,
        vault_obj: Object<Vault>,
        metadata: Object<Metadata>,
        amount: u64
    ) acquires Vault {
        assert!(amount > 0, E_INVALID_AMOUNT);

        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        let vault_metadata = fungible_asset::store_metadata(vault.store);
        assert!(
            object::object_address(&metadata) == object::object_address(&vault_metadata),
            E_METADATA_MISMATCH
        );

        let fa = primary_fungible_store::withdraw(depositor, metadata, amount);
        fungible_asset::deposit(vault.store, fa);
    }

    /// Borrow logic: returns the requested FA and the hot potato receipt.
    public fun borrow(
        vault_obj: Object<Vault>,
        amount: u64
    ): (FungibleAsset, FlashReceipt) acquires Vault {
        assert!(amount > 0, E_INVALID_AMOUNT);

        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        let available = fungible_asset::balance(vault.store);
        assert!(available >= amount, E_VAULT_INSUFFICIENT_FUNDS);

        let fee = (amount * vault.fee_bps) / 10_000;
        let metadata = fungible_asset::store_metadata(vault.store);

        let store_signer = object::generate_signer_for_extending(&vault.store_extend_ref);
        let loaned_assets = fungible_asset::withdraw(&store_signer, vault.store, amount);

        let receipt = FlashReceipt {
            amount_borrowed: amount,
            fee,
            metadata,
        };

        (loaned_assets, receipt)
    }

    /// Repay logic: consumes the hot potato and the assets + fee.
    public fun repay(
        vault_obj: Object<Vault>,
        repayment: FungibleAsset,
        receipt: FlashReceipt
    ) acquires Vault {
        let FlashReceipt { amount_borrowed, fee, metadata } = receipt;

        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        let vault_metadata = fungible_asset::store_metadata(vault.store);
        assert!(
            object::object_address(&metadata) == object::object_address(&vault_metadata),
            E_METADATA_MISMATCH
        );

        assert!(
            fungible_asset::amount(&repayment) >= (amount_borrowed + fee),
            E_INSUFFICIENT_REPAYMENT
        );

        fungible_asset::deposit(vault.store, repayment);
    }

    /// Update the vault fee (owner-only).
    public entry fun set_fee_bps(
        owner: &signer,
        vault_obj: Object<Vault>,
        new_fee_bps: u64
    ) acquires Vault {
        assert!(new_fee_bps <= 10_000, E_INVALID_FEE_BPS);

        let vault = borrow_global_mut<Vault>(object::object_address(&vault_obj));
        assert!(signer::address_of(owner) == vault.owner, E_NOT_OWNER);
        vault.fee_bps = new_fee_bps;
    }

    #[view]
    public fun vault_balance(vault_obj: Object<Vault>): u64 acquires Vault {
        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        fungible_asset::balance(vault.store)
    }

    #[view]
    public fun vault_metadata(vault_obj: Object<Vault>): Object<Metadata> acquires Vault {
        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        fungible_asset::store_metadata(vault.store)
    }

    #[view]
    public fun vault_fee_bps(vault_obj: Object<Vault>): u64 acquires Vault {
        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        vault.fee_bps
    }

    #[view]
    public fun vault_owner(vault_obj: Object<Vault>): address acquires Vault {
        let vault = borrow_global<Vault>(object::object_address(&vault_obj));
        vault.owner
    }
}
