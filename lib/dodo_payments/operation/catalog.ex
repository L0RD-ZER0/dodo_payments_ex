defmodule DodoPayments.Operation.Catalog do
  @moduledoc false
  alias DodoPayments.Operation

  # Dodo's numbered APIs are zero-based. The official Stainless SDK's shared
  # paginator currently assumes 1 when callers omit page_number; do not copy it.
  @page %{kind: :page_number, initial: 0}
  @cursor %{kind: :cursor}

  # Source: dodopayments npm package 2.47.0. The small handwritten policy overlay
  # is deliberate: Stainless' generated transport cannot express Dodo's public
  # license boundary, mutation ambiguity, page-zero endpoints, or CSV response.
  @operations [
    # Catalogue and checkout
    Operation.new(:addons_list, :get, "/addons",
      pagination: @page,
      item_schema: DodoPayments.Addon
    ),
    Operation.new(:addons_create, :post, "/addons",
      required: [:currency, :name, :price, :tax_category],
      response_schema: DodoPayments.Addon
    ),
    Operation.new(:addons_retrieve, :get, "/addons/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Addon
    ),
    Operation.new(:addons_update, :patch, "/addons/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Addon
    ),
    Operation.new(:addons_update_images, :put, "/addons/{id}/images",
      path_params: [:id],
      input: :none,
      response_schema: DodoPayments.PresignedImageUpload
    ),
    Operation.new(:brands_list, :get, "/brands", response_schema: DodoPayments.BrandListResponse),
    Operation.new(:brands_create, :post, "/brands", response_schema: DodoPayments.Brand),
    Operation.new(:brands_retrieve, :get, "/brands/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Brand
    ),
    Operation.new(:brands_update, :patch, "/brands/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Brand
    ),
    Operation.new(:brands_update_images, :put, "/brands/{id}/images",
      path_params: [:id],
      input: :none,
      response_schema: DodoPayments.PresignedImageUpload
    ),
    Operation.new(:brands_archive, :post, "/brands/{id}/archive",
      path_params: [:id],
      response_schema: DodoPayments.BrandArchiveResponse,
      reconciliation:
        "List brands with include_archived and inspect the exact brand ID before repeating an ambiguous permanent archive."
    ),
    Operation.new(:checkout_sessions_create, :post, "/checkouts",
      required: [:product_cart],
      response_schema: DodoPayments.CheckoutSession,
      reconciliation:
        "Use the returned checkout URL; if delivery is unknown, reconcile from Payments before creating another checkout."
    ),
    Operation.new(:checkout_sessions_retrieve, :get, "/checkouts/{id}",
      path_params: [:id],
      response_schema: DodoPayments.CheckoutSessionStatus
    ),
    Operation.new(:checkout_sessions_preview, :post, "/checkouts/preview",
      required: [:product_cart],
      replay: :safe,
      consequential: false,
      response_schema: DodoPayments.CheckoutSessionPreview
    ),
    Operation.new(:supported_countries_list, :get, "/checkout/supported_countries",
      auth: :public,
      item_schema: {:enum, :country_code}
    ),

    # Products and product collections
    Operation.new(:products_list, :get, "/products",
      pagination: @page,
      item_schema: DodoPayments.Product
    ),
    Operation.new(:products_create, :post, "/products",
      required: [:name, :price, :tax_category],
      response_schema: DodoPayments.Product
    ),
    Operation.new(:products_retrieve, :get, "/products/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Product
    ),
    Operation.new(:products_update, :patch, "/products/{id}",
      path_params: [:id],
      response_mode: :empty
    ),
    Operation.new(:products_archive, :delete, "/products/{id}",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:products_unarchive, :post, "/products/{id}/unarchive",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:products_update_files, :put, "/products/{id}/files",
      path_params: [:id],
      required: [:file_name],
      response_schema: DodoPayments.PresignedFileUpload
    ),
    Operation.new(:product_images_update, :put, "/products/{id}/images",
      path_params: [:id],
      input: :query,
      response_schema: DodoPayments.PresignedImageUpload
    ),
    Operation.new(:product_short_links_list, :get, "/products/short_links",
      pagination: @page,
      item_schema: DodoPayments.ShortLink
    ),
    Operation.new(:product_short_links_create, :post, "/products/{id}/short_links",
      path_params: [:id],
      required: [:slug],
      response_schema: DodoPayments.ShortLinkCreateResponse
    ),
    Operation.new(:localized_prices_list, :get, "/products/{product_id}/localized-prices",
      path_params: [:product_id],
      response_schema: DodoPayments.LocalizedPriceListResponse
    ),
    Operation.new(:localized_prices_create, :post, "/products/{product_id}/localized-prices",
      path_params: [:product_id],
      required: [:amount, :currency],
      response_schema: DodoPayments.LocalizedPrice
    ),
    Operation.new(
      :localized_prices_retrieve,
      :get,
      "/products/{product_id}/localized-prices/{id}",
      path_params: [:product_id, :id],
      response_schema: DodoPayments.LocalizedPrice
    ),
    Operation.new(
      :localized_prices_update,
      :patch,
      "/products/{product_id}/localized-prices/{id}",
      path_params: [:product_id, :id],
      response_schema: DodoPayments.LocalizedPrice
    ),
    Operation.new(
      :localized_prices_archive,
      :delete,
      "/products/{product_id}/localized-prices/{id}",
      path_params: [:product_id, :id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:product_collections_list, :get, "/product-collections",
      pagination: @page,
      item_schema: DodoPayments.ProductCollectionListItem
    ),
    Operation.new(:product_collections_create, :post, "/product-collections",
      required: [:groups, :name],
      response_schema: DodoPayments.ProductCollection
    ),
    Operation.new(:product_collections_retrieve, :get, "/product-collections/{id}",
      path_params: [:id],
      response_schema: DodoPayments.ProductCollection
    ),
    Operation.new(:product_collections_archive, :delete, "/product-collections/{id}",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:product_collections_update, :patch, "/product-collections/{id}",
      path_params: [:id],
      response_mode: :empty
    ),
    Operation.new(:product_collections_update_images, :put, "/product-collections/{id}/images",
      path_params: [:id],
      input: :query,
      response_schema: DodoPayments.PresignedImageUpload
    ),
    Operation.new(:product_collections_unarchive, :post, "/product-collections/{id}/unarchive",
      path_params: [:id],
      input: :none,
      response_schema: DodoPayments.ProductCollectionUnarchiveResponse
    ),
    Operation.new(:collection_groups_create, :post, "/product-collections/{id}/groups",
      path_params: [:id],
      required: [:products],
      response_schema: DodoPayments.ProductCollectionGroup
    ),
    Operation.new(
      :collection_groups_delete,
      :delete,
      "/product-collections/{id}/groups/{group_id}",
      path_params: [:id, :group_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(
      :collection_groups_update,
      :patch,
      "/product-collections/{id}/groups/{group_id}",
      path_params: [:id, :group_id],
      response_mode: :empty
    ),
    Operation.new(
      :collection_group_items_create,
      :post,
      "/product-collections/{id}/groups/{group_id}/items",
      path_params: [:id, :group_id],
      required: [:products],
      item_schema: DodoPayments.ProductCollectionProduct
    ),
    Operation.new(
      :collection_group_items_delete,
      :delete,
      "/product-collections/{id}/groups/{group_id}/items/{item_id}",
      path_params: [:id, :group_id, :item_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(
      :collection_group_items_update,
      :patch,
      "/product-collections/{id}/groups/{group_id}/items/{item_id}",
      path_params: [:id, :group_id, :item_id],
      required: [:status],
      response_mode: :empty
    ),
    Operation.new(:discounts_list, :get, "/discounts",
      pagination: @page,
      item_schema: DodoPayments.Discount
    ),
    Operation.new(:discounts_create, :post, "/discounts",
      required: [:type, :amount],
      response_schema: DodoPayments.Discount
    ),
    Operation.new(:discounts_retrieve, :get, "/discounts/{discount_id}",
      path_params: [:discount_id],
      response_schema: DodoPayments.Discount
    ),
    Operation.new(:discounts_delete, :delete, "/discounts/{discount_id}",
      path_params: [:discount_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:discounts_update, :patch, "/discounts/{discount_id}",
      path_params: [:discount_id],
      response_schema: DodoPayments.Discount
    ),
    Operation.new(:discounts_retrieve_by_code, :get, "/discounts/code/{code}",
      path_params: [:code],
      response_schema: DodoPayments.Discount
    ),
    Operation.new(:discount_customers_list, :get, "/discounts/{discount_id}/customers",
      path_params: [:discount_id],
      pagination: @page,
      item_schema: DodoPayments.DiscountCustomer
    ),
    Operation.new(:discount_customers_attach, :post, "/discounts/{discount_id}/customers",
      path_params: [:discount_id],
      required: [:customer_ids],
      validator: :customer_id_list,
      replay: :safe,
      response_schema: DodoPayments.DiscountCustomersResponse,
      reconciliation:
        "Attaching an already-attached customer is operation-idempotent; retry the identical customer_ids set."
    ),
    Operation.new(
      :discount_customers_detach,
      :delete,
      "/discounts/{discount_id}/customers/{customer_id}",
      path_params: [:discount_id, :customer_id],
      input: :none,
      response_mode: :empty,
      reconciliation:
        "List customers attached to the discount before repeating; an already-detached customer returns 404."
    ),

    # Customers, wallets and balances
    Operation.new(:customers_list, :get, "/customers",
      pagination: @page,
      item_schema: DodoPayments.Customer
    ),
    Operation.new(:customers_create, :post, "/customers",
      required: [:email, :name],
      response_schema: DodoPayments.Customer
    ),
    Operation.new(:customers_retrieve, :get, "/customers/{customer_id}",
      path_params: [:customer_id],
      response_schema: DodoPayments.Customer
    ),
    Operation.new(:customers_update, :patch, "/customers/{customer_id}",
      path_params: [:customer_id],
      response_schema: DodoPayments.Customer
    ),
    Operation.new(
      :customer_payment_methods_list,
      :get,
      "/customers/{customer_id}/payment-methods",
      path_params: [:customer_id],
      response_schema: DodoPayments.CustomerPaymentMethodsResponse
    ),
    Operation.new(
      :customer_payment_methods_delete,
      :delete,
      "/customers/{customer_id}/payment-methods/{payment_method_id}",
      path_params: [:customer_id, :payment_method_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(
      :customer_credit_entitlements_list,
      :get,
      "/customers/{customer_id}/credit-entitlements",
      path_params: [:customer_id],
      response_schema: DodoPayments.CustomerCreditEntitlementsResponse
    ),
    Operation.new(:customer_entitlements_list, :get, "/customers/{customer_id}/entitlements",
      path_params: [:customer_id],
      response_schema: DodoPayments.CustomerEntitlementsResponse
    ),
    Operation.new(
      :customer_entitlement_grants_list,
      :get,
      "/customers/{customer_id}/entitlement-grants",
      path_params: [:customer_id],
      pagination: @page,
      item_schema: DodoPayments.EntitlementGrant
    ),
    Operation.new(
      :customer_portal_sessions_create,
      :post,
      "/customers/{customer_id}/customer-portal/session",
      path_params: [:customer_id],
      input: :query,
      response_schema: DodoPayments.CustomerPortalSession
    ),
    Operation.new(:customer_wallets_list, :get, "/customers/{customer_id}/wallets",
      path_params: [:customer_id],
      response_schema: DodoPayments.CustomerWalletListResponse
    ),
    Operation.new(
      :customer_wallet_ledger_entries_list,
      :get,
      "/customers/{customer_id}/wallets/ledger-entries",
      path_params: [:customer_id],
      pagination: @page,
      item_schema: DodoPayments.CustomerWalletTransaction
    ),
    Operation.new(
      :customer_wallet_ledger_entries_create,
      :post,
      "/customers/{customer_id}/wallets/ledger-entries",
      path_params: [:customer_id],
      required: [:amount, :currency, :entry_type],
      replay: {:idempotent_by, [:idempotency_key]},
      response_schema: DodoPayments.CustomerWallet
    ),
    Operation.new(:balance_ledger_list, :get, "/balances/ledger",
      pagination: @page,
      item_schema: DodoPayments.BalanceLedgerEntry
    ),

    # Payments, subscriptions, refunds and disputes
    Operation.new(:payments_list, :get, "/payments",
      pagination: @page,
      item_schema: DodoPayments.Payment
    ),
    Operation.new(:payments_create, :post, "/payments",
      required: [:billing, :customer, :product_cart],
      response_schema: DodoPayments.PaymentCreateResponse,
      reconciliation:
        "Reconcile by payment, customer or webhook before repeating a payment creation whose delivery is unknown."
    ),
    Operation.new(:payments_retrieve, :get, "/payments/{payment_id}",
      path_params: [:payment_id],
      response_schema: DodoPayments.Payment
    ),
    Operation.new(:payment_line_items_list, :get, "/payments/{payment_id}/line-items",
      path_params: [:payment_id],
      response_schema: DodoPayments.PaymentLineItemsResponse
    ),
    Operation.new(:subscriptions_list, :get, "/subscriptions",
      pagination: @page,
      item_schema: DodoPayments.Subscription
    ),
    Operation.new(:subscriptions_create, :post, "/subscriptions",
      required: [:billing, :customer, :product_id, :quantity],
      response_schema: DodoPayments.SubscriptionCreateResponse
    ),
    Operation.new(:subscriptions_retrieve, :get, "/subscriptions/{subscription_id}",
      path_params: [:subscription_id],
      response_schema: DodoPayments.Subscription
    ),
    Operation.new(:subscriptions_update, :patch, "/subscriptions/{subscription_id}",
      path_params: [:subscription_id],
      response_schema: DodoPayments.Subscription
    ),
    Operation.new(:subscriptions_charge, :post, "/subscriptions/{subscription_id}/charge",
      path_params: [:subscription_id],
      required: [:product_price],
      response_schema: DodoPayments.SubscriptionChargeResponse,
      reconciliation:
        "Inspect the subscription and its payments or wait for webhooks before repeating an ambiguous charge."
    ),
    Operation.new(
      :subscriptions_change_plan,
      :post,
      "/subscriptions/{subscription_id}/change-plan",
      path_params: [:subscription_id],
      required: [:product_id, :proration_billing_mode, :quantity],
      response_mode: :empty
    ),
    Operation.new(
      :subscriptions_usage_history,
      :get,
      "/subscriptions/{subscription_id}/usage-history",
      path_params: [:subscription_id],
      pagination: @page,
      item_schema: DodoPayments.SubscriptionUsageHistory
    ),
    Operation.new(
      :subscriptions_update_payment_method,
      :post,
      "/subscriptions/{subscription_id}/update-payment-method",
      path_params: [:subscription_id],
      required: [:payment_method],
      body_field: :payment_method,
      response_schema: DodoPayments.SubscriptionUpdatePaymentMethodResponse
    ),
    Operation.new(
      :subscriptions_preview_change_plan,
      :post,
      "/subscriptions/{subscription_id}/change-plan/preview",
      path_params: [:subscription_id],
      required: [:product_id, :proration_billing_mode, :quantity],
      replay: :safe,
      consequential: false,
      response_schema: DodoPayments.SubscriptionPreviewChangePlanResponse
    ),
    Operation.new(
      :subscriptions_credit_usage,
      :get,
      "/subscriptions/{subscription_id}/credit-usage",
      path_params: [:subscription_id],
      response_schema: DodoPayments.SubscriptionCreditUsageResponse
    ),
    Operation.new(
      :subscriptions_cancel_change_plan,
      :delete,
      "/subscriptions/{subscription_id}/change-plan/scheduled",
      path_params: [:subscription_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:refunds_list, :get, "/refunds",
      pagination: @page,
      item_schema: DodoPayments.Refund
    ),
    Operation.new(:refunds_create, :post, "/refunds",
      required: [:payment_id],
      response_schema: DodoPayments.Refund
    ),
    Operation.new(:refunds_retrieve, :get, "/refunds/{refund_id}",
      path_params: [:refund_id],
      response_schema: DodoPayments.Refund
    ),
    Operation.new(:disputes_list, :get, "/disputes",
      pagination: @page,
      item_schema: DodoPayments.DisputeListItem
    ),
    Operation.new(:disputes_retrieve, :get, "/disputes/{dispute_id}",
      path_params: [:dispute_id],
      response_schema: DodoPayments.Dispute
    ),

    # Metering and credits
    Operation.new(:meters_list, :get, "/meters",
      pagination: @page,
      item_schema: DodoPayments.Meter
    ),
    Operation.new(:meters_create, :post, "/meters",
      required: [:aggregation, :event_name, :measurement_unit, :name],
      response_schema: DodoPayments.Meter
    ),
    Operation.new(:meters_retrieve, :get, "/meters/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Meter
    ),
    Operation.new(:meters_archive, :delete, "/meters/{id}",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:meters_unarchive, :post, "/meters/{id}/unarchive",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:usage_events_ingest, :post, "/events/ingest",
      required: [:events],
      validator: :usage_event_batch,
      replay: {:idempotent_by, [[:events, :event_id]]},
      response_schema: DodoPayments.UsageEventIngestResponse
    ),
    Operation.new(:usage_events_list, :get, "/events",
      pagination: @page,
      item_schema: DodoPayments.UsageEvent
    ),
    Operation.new(:usage_events_retrieve, :get, "/events/{event_id}",
      path_params: [:event_id],
      response_schema: DodoPayments.UsageEvent
    ),
    Operation.new(:credit_entitlements_list, :get, "/credit-entitlements",
      pagination: @page,
      item_schema: DodoPayments.CreditEntitlement
    ),
    Operation.new(:credit_entitlements_create, :post, "/credit-entitlements",
      required: [:name, :overage_enabled, :precision, :rollover_enabled, :unit],
      response_schema: DodoPayments.CreditEntitlement
    ),
    Operation.new(:credit_entitlements_retrieve, :get, "/credit-entitlements/{id}",
      path_params: [:id],
      response_schema: DodoPayments.CreditEntitlement
    ),
    Operation.new(:credit_entitlements_delete, :delete, "/credit-entitlements/{id}",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:credit_entitlements_update, :patch, "/credit-entitlements/{id}",
      path_params: [:id],
      response_mode: :empty
    ),
    Operation.new(:credit_entitlements_undelete, :post, "/credit-entitlements/{id}/undelete",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(
      :credit_balances_list,
      :get,
      "/credit-entitlements/{credit_entitlement_id}/balances",
      path_params: [:credit_entitlement_id],
      pagination: @page,
      item_schema: DodoPayments.CustomerCreditBalance
    ),
    Operation.new(
      :credit_balances_retrieve,
      :get,
      "/credit-entitlements/{credit_entitlement_id}/balances/{customer_id}",
      path_params: [:credit_entitlement_id, :customer_id],
      response_schema: DodoPayments.CustomerCreditBalance
    ),
    Operation.new(
      :credit_balance_grants_list,
      :get,
      "/credit-entitlements/{credit_entitlement_id}/balances/{customer_id}/grants",
      path_params: [:credit_entitlement_id, :customer_id],
      pagination: @page,
      item_schema: DodoPayments.CreditGrant
    ),
    Operation.new(
      :credit_balance_ledger_list,
      :get,
      "/credit-entitlements/{credit_entitlement_id}/balances/{customer_id}/ledger",
      path_params: [:credit_entitlement_id, :customer_id],
      pagination: @page,
      item_schema: DodoPayments.CreditLedgerEntry
    ),
    Operation.new(
      :credit_balance_ledger_entries_create,
      :post,
      "/credit-entitlements/{credit_entitlement_id}/balances/{customer_id}/ledger-entries",
      path_params: [:credit_entitlement_id, :customer_id],
      required: [:amount, :entry_type],
      replay: {:idempotent_by, [:idempotency_key]},
      response_schema: DodoPayments.CreditLedgerEntryCreateResponse
    ),

    # Fulfilment and public license runtime
    Operation.new(:entitlements_list, :get, "/entitlements",
      pagination: @page,
      item_schema: DodoPayments.Entitlement
    ),
    Operation.new(:entitlements_create, :post, "/entitlements",
      required: [:integration_config, :integration_type, :name],
      response_schema: DodoPayments.Entitlement
    ),
    Operation.new(:entitlements_retrieve, :get, "/entitlements/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Entitlement
    ),
    Operation.new(:entitlements_delete, :delete, "/entitlements/{id}",
      path_params: [:id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:entitlements_update, :patch, "/entitlements/{id}",
      path_params: [:id],
      response_schema: DodoPayments.Entitlement
    ),
    Operation.new(:entitlement_files_upload, :post, "/entitlements/{id}/files",
      path_params: [:id],
      input: :none,
      response_schema: DodoPayments.EntitlementFileUploadResponse
    ),
    Operation.new(:entitlement_files_delete, :delete, "/entitlements/{id}/files/{file_id}",
      path_params: [:id, :file_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:entitlement_grants_list, :get, "/entitlements/{id}/grants",
      path_params: [:id],
      pagination: @page,
      item_schema: DodoPayments.EntitlementGrant
    ),
    Operation.new(:entitlement_grants_revoke, :delete, "/entitlements/{id}/grants/{grant_id}",
      path_params: [:id, :grant_id],
      input: :none,
      replay: :safe,
      response_schema: DodoPayments.EntitlementGrant
    ),
    Operation.new(
      :entitlement_grants_fulfill_license_key,
      :post,
      "/grants/{grant_id}/license-key",
      path_params: [:grant_id],
      required: [:key],
      response_schema: DodoPayments.EntitlementGrant
    ),
    Operation.new(:license_keys_list, :get, "/license_keys",
      pagination: @page,
      item_schema: DodoPayments.LicenseKey
    ),
    Operation.new(:license_keys_create, :post, "/license_keys",
      required: [:customer_id, :key, :product_id],
      response_schema: DodoPayments.LicenseKey
    ),
    Operation.new(:license_keys_retrieve, :get, "/license_keys/{id}",
      path_params: [:id],
      response_schema: DodoPayments.LicenseKey
    ),
    Operation.new(:license_keys_update, :patch, "/license_keys/{id}",
      path_params: [:id],
      response_schema: DodoPayments.LicenseKey
    ),
    Operation.new(:license_key_instances_list, :get, "/license_key_instances",
      pagination: @page,
      item_schema: DodoPayments.LicenseKeyInstance
    ),
    Operation.new(:license_key_instances_retrieve, :get, "/license_key_instances/{id}",
      path_params: [:id],
      response_schema: DodoPayments.LicenseKeyInstance
    ),
    Operation.new(:license_key_instances_update, :patch, "/license_key_instances/{id}",
      path_params: [:id],
      required: [:name],
      response_schema: DodoPayments.LicenseKeyInstance
    ),
    Operation.new(:licenses_activate, :post, "/licenses/activate",
      auth: :public,
      required: [:license_key, :name],
      response_schema: DodoPayments.License
    ),
    Operation.new(:licenses_deactivate, :post, "/licenses/deactivate",
      auth: :public,
      required: [:license_key, :license_key_instance_id],
      response_mode: :empty
    ),
    Operation.new(:licenses_validate, :post, "/licenses/validate",
      auth: :public,
      required: [:license_key],
      replay: :safe,
      consequential: false,
      response_schema: DodoPayments.License
    ),

    # Finance and documents
    Operation.new(:payouts_list, :get, "/payouts",
      pagination: @page,
      item_schema: DodoPayments.Payout
    ),
    Operation.new(:payout_breakup_retrieve, :get, "/payouts/{payout_id}/breakup",
      path_params: [:payout_id],
      item_schema: DodoPayments.PayoutBreakupItem
    ),
    Operation.new(:payout_breakup_details_list, :get, "/payouts/{payout_id}/breakup/details",
      path_params: [:payout_id],
      pagination: @page,
      item_schema: DodoPayments.PayoutBreakupDetail
    ),
    Operation.new(:payout_breakup_csv_download, :get, "/payouts/{payout_id}/breakup/details/csv",
      path_params: [:payout_id],
      response_mode: :csv
    ),
    Operation.new(:invoices_payment_download, :get, "/invoices/payments/{payment_id}",
      path_params: [:payment_id],
      auth: :public,
      response_mode: :pdf
    ),
    Operation.new(:invoices_refund_download, :get, "/invoices/refunds/{refund_id}",
      path_params: [:refund_id],
      auth: :public,
      response_mode: :pdf
    ),
    Operation.new(:invoices_payout_download, :get, "/invoices/payouts/{payout_id}",
      path_params: [:payout_id],
      auth: :public,
      response_mode: :pdf
    ),

    # Endpoint management. Event verification lives in DodoPayments.Webhooks.
    Operation.new(:webhook_endpoints_list, :get, "/webhooks",
      pagination: @cursor,
      item_schema: DodoPayments.WebhookEndpoint
    ),
    Operation.new(:webhook_endpoints_create, :post, "/webhooks",
      required: [:url],
      replay: {:idempotent_by, [:idempotency_key]},
      response_schema: DodoPayments.WebhookEndpoint
    ),
    Operation.new(:webhook_endpoints_retrieve, :get, "/webhooks/{webhook_id}",
      path_params: [:webhook_id],
      response_schema: DodoPayments.WebhookEndpoint
    ),
    Operation.new(:webhook_endpoints_delete, :delete, "/webhooks/{webhook_id}",
      path_params: [:webhook_id],
      input: :none,
      response_mode: :empty
    ),
    Operation.new(:webhook_endpoints_update, :patch, "/webhooks/{webhook_id}",
      path_params: [:webhook_id],
      response_schema: DodoPayments.WebhookEndpoint
    ),
    Operation.new(:webhook_endpoints_retrieve_secret, :get, "/webhooks/{webhook_id}/secret",
      path_params: [:webhook_id],
      response_schema: DodoPayments.WebhookSecret
    ),
    Operation.new(:webhook_headers_retrieve, :get, "/webhooks/{webhook_id}/headers",
      path_params: [:webhook_id],
      response_schema: DodoPayments.WebhookHeaders
    ),
    Operation.new(:webhook_headers_update, :patch, "/webhooks/{webhook_id}/headers",
      path_params: [:webhook_id],
      required: [:headers],
      response_mode: :empty
    )
  ]

  @expected_operation_count DodoPayments.SourceMetadata.operation_count()
  if length(@operations) != @expected_operation_count do
    raise "Dodo operation catalogue drifted: expected #{@expected_operation_count}, got #{length(@operations)}"
  end

  if Enum.uniq_by(@operations, & &1.id) != @operations do
    raise "Dodo operation catalogue contains duplicate identifiers"
  end

  path_mismatch? =
    Enum.any?(@operations, fn operation ->
      placeholders =
        Regex.scan(~r/\{([^}]+)\}/, operation.path, capture: :all_but_first)
        |> List.flatten()

      placeholders != Enum.map(operation.path_params, &Atom.to_string/1)
    end)

  if path_mismatch? do
    raise "Dodo operation catalogue path placeholders do not match path_params"
  end

  unless Enum.all?(@operations, fn operation ->
           operation.auth in [:merchant, :public] and
             not is_nil(operation.replay) and
             is_boolean(operation.consequential) and
             operation.response_mode in [:json, :empty, :binary, :pdf, :csv] and
             is_list(operation.success_statuses) and operation.success_statuses != [] and
             is_binary(operation.reconciliation)
         end) do
    raise "every Dodo operation must classify auth, replay, response and reconciliation policy"
  end

  @by_id Map.new(@operations, &{&1.id, &1})

  def all, do: @operations

  def fetch!(id) do
    case Map.fetch(@by_id, id) do
      {:ok, operation} -> operation
      :error -> raise ArgumentError, "unknown Dodo Payments operation: #{inspect(id)}"
    end
  end
end
