defmodule DodoPayments.ResponseTypes do
  @moduledoc """
  Wire-shape aliases shared by typed response structs.

  Nested JSON objects deliberately remain string-keyed maps for compatibility.
  Elixir typespecs cannot enumerate individual binary keys, so these aliases
  describe the authoritative upstream value domains without claiming atom keys
  or converting child objects into structs.
  """

  @type json ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json()]
          | %{optional(String.t()) => json()}

  @type object :: %{optional(String.t()) => json()}
  @type metadata :: %{optional(String.t()) => String.t() | number() | boolean()}
  @type billing_address :: %{optional(String.t()) => String.t() | nil}
  @type customer_limited_details ::
          %{optional(String.t()) => String.t() | metadata() | nil}
  @type product_cart_item ::
          %{optional(String.t()) => String.t() | number() | nil}
  @type payment_line_item ::
          %{optional(String.t()) => String.t() | number() | nil}
  @type refund_list_item ::
          %{optional(String.t()) => String.t() | number() | boolean() | nil}
  @type dispute :: %{optional(String.t()) => String.t() | boolean() | nil}
  @type custom_field_response :: %{optional(String.t()) => String.t()}
  @type brand :: %{optional(String.t()) => String.t() | boolean() | nil}
  @type discount_currency_option ::
          %{optional(String.t()) => String.t() | number() | boolean() | nil}
  @type localized_price ::
          %{optional(String.t()) => String.t() | number() | nil}
  @type product_collection_group ::
          %{optional(String.t()) => String.t() | boolean() | [product_collection_product()] | nil}
  @type product_collection_product ::
          %{
            optional(String.t()) => String.t() | number() | boolean() | object() | nil
          }
  @type customer_payment_method ::
          %{optional(String.t()) => String.t() | boolean() | object() | nil}
  @type customer_credit_entitlement ::
          %{optional(String.t()) => String.t() | number() | nil}
  @type customer_entitlement ::
          %{optional(String.t()) => String.t() | nil}
  @type customer_wallet ::
          %{optional(String.t()) => String.t() | number()}
  @type subscription_usage_meter ::
          %{optional(String.t()) => String.t() | number()}
  @type subscription_immediate_charge ::
          %{optional(String.t()) => String.t() | object() | [object()]}
  @type subscription_credit_usage ::
          %{optional(String.t()) => String.t() | number() | boolean() | nil}
  @type discount_customer :: %{optional(String.t()) => String.t()}
end

defmodule DodoPayments.Addon do
  @moduledoc "An add-on product response."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      name: String.t(),
      price: number(),
      tax_category: DodoPayments.Enums.decoded_tax_category(),
      updated_at: String.t(),
      description: String.t(),
      image: String.t()
    ]
end

defmodule DodoPayments.Brand do
  @moduledoc "A brand response, including verification and archival state."
  use DodoPayments.Schema,
    fields: [
      brand_id: String.t(),
      business_id: String.t(),
      enabled: boolean(),
      statement_descriptor: String.t(),
      verification_enabled: boolean(),
      verification_status: DodoPayments.Enums.decoded_brand_verification_status(),
      archived_at: String.t(),
      description: String.t(),
      image: String.t(),
      name: String.t(),
      reason_for_hold: String.t(),
      support_email: String.t(),
      url: String.t()
    ]
end

defmodule DodoPayments.BrandListResponse do
  @moduledoc "The non-paginated brand list envelope."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.brand()]]
end

defmodule DodoPayments.Customer do
  @moduledoc "A customer response."
  use DodoPayments.Schema,
    fields: [
      business_id: String.t(),
      created_at: String.t(),
      customer_id: String.t(),
      email: String.t(),
      name: String.t(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      phone_number: String.t()
    ]
end

defmodule DodoPayments.Discount do
  @moduledoc "A discount-code response."
  use DodoPayments.Schema,
    fields: [
      amount: number(),
      business_id: String.t(),
      code: String.t(),
      created_at: String.t(),
      customer_eligibility: DodoPayments.Enums.decoded_customer_eligibility(),
      discount_id: String.t(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      preserve_on_plan_change: boolean(),
      restricted_to: [String.t()],
      times_used: number(),
      type: DodoPayments.Enums.decoded_discount_type(),
      currency_options: [DodoPayments.ResponseTypes.discount_currency_option()],
      expires_at: String.t(),
      name: String.t(),
      per_customer_usage_limit: number(),
      starts_at: String.t(),
      subscription_cycles: number(),
      usage_limit: number()
    ]
end

defmodule DodoPayments.Meter do
  @moduledoc "A usage meter response."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      aggregation: DodoPayments.ResponseTypes.object(),
      business_id: String.t(),
      created_at: String.t(),
      event_name: String.t(),
      measurement_unit: String.t(),
      name: String.t(),
      updated_at: String.t(),
      description: String.t(),
      filter: DodoPayments.ResponseTypes.object()
    ]
end

defmodule DodoPayments.Refund do
  @moduledoc "A refund response."
  use DodoPayments.Schema,
    fields: [
      brand_id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      is_partial: boolean(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      payment_id: String.t(),
      refund_id: String.t(),
      status: DodoPayments.Enums.decoded_refund_status(),
      amount: number(),
      currency: DodoPayments.Enums.decoded_currency(),
      reason: String.t()
    ]
end

defmodule DodoPayments.Entitlement do
  @moduledoc "An entitlement definition and its integration configuration."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      integration_config: DodoPayments.ResponseTypes.object(),
      integration_type: DodoPayments.Enums.decoded_entitlement_integration_type(),
      is_active: boolean(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      name: String.t(),
      updated_at: String.t(),
      description: String.t()
    ]
end

defmodule DodoPayments.WebhookEndpoint do
  @moduledoc "A configured webhook endpoint."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      created_at: String.t(),
      description: String.t(),
      metadata: %{optional(String.t()) => String.t()},
      updated_at: String.t(),
      url: String.t(),
      disabled: boolean(),
      filter_types: [String.t()],
      rate_limit: number()
    ]
end

defmodule DodoPayments.Product do
  @moduledoc "A product response. Unrecognized Dodo fields are kept in `extra`."
  use DodoPayments.Schema,
    fields: [
      product_id: String.t(),
      brand_id: String.t(),
      business_id: String.t(),
      name: String.t(),
      description: String.t(),
      image: String.t(),
      price: number() | DodoPayments.ResponseTypes.object(),
      price_detail: DodoPayments.ResponseTypes.object(),
      currency: DodoPayments.Enums.decoded_currency(),
      tax_category: DodoPayments.Enums.decoded_tax_category(),
      tax_inclusive: boolean(),
      is_recurring: boolean(),
      credit_entitlements: [DodoPayments.ResponseTypes.object()],
      entitlements: [DodoPayments.ResponseTypes.object()],
      license_key_enabled: boolean(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      addons: [String.t()],
      digital_product_delivery: DodoPayments.ResponseTypes.object(),
      license_key_activation_message: String.t(),
      license_key_activations_limit: number(),
      license_key_duration: DodoPayments.ResponseTypes.object(),
      pricing_mode: DodoPayments.Enums.decoded_pricing_mode(),
      product_collection_id: String.t(),
      created_at: String.t(),
      updated_at: String.t()
    ]
end

defmodule DodoPayments.CheckoutSession do
  @moduledoc "A hosted checkout session or checkout status response."
  use DodoPayments.Schema,
    fields: [
      session_id: String.t(),
      payment_id: String.t(),
      checkout_url: String.t(),
      client_secret: String.t(),
      publishable_key: String.t()
    ]
end

defmodule DodoPayments.CheckoutSessionStatus do
  @moduledoc "The current status of a hosted checkout session."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      created_at: String.t(),
      customer_email: String.t(),
      customer_name: String.t(),
      payment_id: String.t(),
      payment_status: DodoPayments.Enums.decoded_intent_status()
    ]
end

defmodule DodoPayments.CheckoutSessionPreview do
  @moduledoc "A Dodo checkout price and tax preview."
  use DodoPayments.Schema,
    fields: [
      billing_country: DodoPayments.Enums.decoded_country_code(),
      currency: DodoPayments.Enums.decoded_currency(),
      current_breakup: DodoPayments.ResponseTypes.object(),
      is_byop: boolean(),
      product_cart: [DodoPayments.ResponseTypes.object()],
      total_price: number(),
      next_billing_date: String.t(),
      recurring_breakup: DodoPayments.ResponseTypes.object(),
      tax_id_business_name: String.t(),
      tax_id_err_msg: String.t(),
      tax_id_format_name: String.t(),
      total_tax: number(),
      trial_amount: number(),
      trial_period_days: number()
    ]
end

defmodule DodoPayments.PaymentCreateResponse do
  @moduledoc "A response from Dodo's deprecated direct payment creation endpoint."
  use DodoPayments.Schema,
    fields: [
      client_secret: String.t(),
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      payment_id: String.t(),
      total_amount: number(),
      discount_id: String.t(),
      discount_ids: [String.t()],
      expires_on: String.t(),
      payment_link: String.t(),
      product_cart: [DodoPayments.ResponseTypes.product_cart_item()]
    ]
end

defmodule DodoPayments.Payment do
  @moduledoc "A payment response."
  use DodoPayments.Schema,
    fields: [
      payment_id: String.t(),
      brand_id: String.t(),
      business_id: String.t(),
      billing: DodoPayments.ResponseTypes.billing_address(),
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      total_amount: number(),
      currency: DodoPayments.Enums.decoded_currency(),
      status: DodoPayments.Enums.decoded_intent_status(),
      payment_method: String.t(),
      payment_method_id: String.t(),
      payment_method_type: String.t(),
      payment_provider: DodoPayments.Enums.decoded_payment_provider(),
      subscription_id: String.t(),
      refunds: [DodoPayments.ResponseTypes.refund_list_item()],
      refund_status: DodoPayments.Enums.decoded_payment_refund_status(),
      disputes: [DodoPayments.ResponseTypes.dispute()],
      metadata: DodoPayments.ResponseTypes.metadata(),
      digital_products_delivered: boolean(),
      has_license_key: boolean(),
      dispute_status: DodoPayments.Enums.decoded_dispute_status(),
      is_update_payment_method: boolean(),
      retry_attempt: number(),
      settlement_amount: number(),
      settlement_currency: DodoPayments.Enums.decoded_currency(),
      settlement_tax: number(),
      tax: number(),
      card_holder_name: String.t(),
      card_issuing_country: DodoPayments.Enums.decoded_country_code(),
      card_last_four: String.t(),
      card_network: String.t(),
      card_type: String.t(),
      checkout_session_id: String.t(),
      custom_field_responses: [DodoPayments.ResponseTypes.custom_field_response()],
      discount_id: String.t(),
      discounts: [DodoPayments.ResponseTypes.object()],
      error_code: String.t(),
      error_message: String.t(),
      invoice_id: String.t(),
      invoice_url: String.t(),
      payment_link: String.t(),
      product_cart: [DodoPayments.ResponseTypes.product_cart_item()],
      created_at: String.t(),
      updated_at: String.t()
    ]
end

defmodule DodoPayments.PaymentLineItemsResponse do
  @moduledoc "Line items and currency for a payment."
  use DodoPayments.Schema,
    fields: [
      currency: DodoPayments.Enums.decoded_currency(),
      items: [DodoPayments.ResponseTypes.payment_line_item()]
    ]
end

defmodule DodoPayments.SubscriptionCreateResponse do
  @moduledoc "A response from Dodo's deprecated direct subscription creation endpoint."
  use DodoPayments.Schema,
    fields: [
      addons: [DodoPayments.ResponseTypes.object()],
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      payment_id: String.t(),
      recurring_pre_tax_amount: number(),
      subscription_id: String.t(),
      client_secret: String.t(),
      discount_id: String.t(),
      discount_ids: [String.t()],
      expires_on: String.t(),
      one_time_product_cart: [DodoPayments.ResponseTypes.product_cart_item()],
      payment_link: String.t(),
      trial_amount: number()
    ]
end

defmodule DodoPayments.SubscriptionUpdatePaymentMethodResponse do
  @moduledoc "Checkout credentials returned while updating a subscription payment method."
  use DodoPayments.Schema,
    fields: [
      client_secret: String.t(),
      expires_on: String.t(),
      payment_id: String.t(),
      payment_link: String.t()
    ],
    sensitive_fields: [:client_secret, :payment_link]
end

defmodule DodoPayments.PresignedImageUpload do
  @moduledoc "A presigned image-upload target. Inspection always redacts the capability URL."
  use DodoPayments.Schema,
    fields: [image_id: String.t(), url: String.t()],
    sensitive_fields: [:url]
end

defmodule DodoPayments.PresignedFileUpload do
  @moduledoc "A presigned file-upload target. Inspection always redacts the capability URL."
  use DodoPayments.Schema,
    fields: [file_id: String.t(), url: String.t()],
    sensitive_fields: [:url]
end

defmodule DodoPayments.CustomerPortalSession do
  @moduledoc "A customer portal session. Inspection always redacts its privileged link."
  use DodoPayments.Schema,
    fields: [link: String.t()],
    sensitive_fields: [:link]
end

defmodule DodoPayments.Subscription do
  @moduledoc "A subscription response."
  use DodoPayments.Schema,
    fields: [
      subscription_id: String.t(),
      addons: [DodoPayments.ResponseTypes.object()],
      billing: DodoPayments.ResponseTypes.billing_address(),
      brand_id: String.t(),
      business_id: term(),
      cancel_at_next_billing_date: boolean(),
      credit_entitlement_cart: [DodoPayments.ResponseTypes.object()],
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      product_id: String.t(),
      status: DodoPayments.Enums.decoded_subscription_status(),
      currency: DodoPayments.Enums.decoded_currency(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      meter_credit_entitlement_cart: [DodoPayments.ResponseTypes.object()],
      meters: [DodoPayments.ResponseTypes.object()],
      on_demand: boolean(),
      payment_frequency_count: number(),
      payment_frequency_interval: DodoPayments.Enums.decoded_time_interval(),
      quantity: number(),
      recurring_pre_tax_amount: number(),
      subscription_period_count: number(),
      subscription_period_interval: DodoPayments.Enums.decoded_time_interval(),
      tax_inclusive: boolean(),
      trial_period_days: number(),
      next_billing_date: String.t(),
      previous_billing_date: String.t(),
      cancellation_comment: String.t(),
      cancellation_feedback: DodoPayments.Enums.decoded_cancellation_feedback(),
      cancelled_at: String.t(),
      custom_field_responses: [DodoPayments.ResponseTypes.custom_field_response()],
      customer_business_name: String.t(),
      discount_cycles_remaining: number(),
      discount_id: String.t(),
      discounts: [DodoPayments.ResponseTypes.object()],
      expires_at: String.t(),
      paused_at: String.t(),
      payment_method_id: String.t(),
      product_name: String.t(),
      scheduled_change: DodoPayments.ResponseTypes.object(),
      tax_id: String.t(),
      trial_amount: number(),
      created_at: String.t()
    ]
end

defmodule DodoPayments.BrandArchiveResponse do
  @moduledoc "The permanent brand-archive result and counts of records moved."
  use DodoPayments.Schema,
    fields: [
      archived_at: String.t(),
      brand_id: String.t(),
      collections_moved: number(),
      products_moved: number(),
      subscriptions_moved: number(),
      moved_to_brand_id: String.t()
    ]
end

defmodule DodoPayments.UsageEvent do
  @moduledoc "An ingested usage event."
  use DodoPayments.Schema,
    fields: [
      business_id: String.t(),
      customer_id: String.t(),
      event_id: String.t(),
      event_name: String.t(),
      timestamp: String.t(),
      metadata: DodoPayments.ResponseTypes.metadata()
    ]
end

defmodule DodoPayments.License do
  @moduledoc "A public license activation or validation response."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      valid: boolean(),
      business_id: String.t(),
      created_at: String.t(),
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      license_key_id: String.t(),
      name: String.t(),
      product: DodoPayments.ResponseTypes.object()
    ]
end

defmodule DodoPayments.WebhookSecret do
  @moduledoc "A webhook signing secret returned by Dodo. Inspection always redacts the secret."
  use DodoPayments.Schema,
    fields: [secret: String.t()],
    sensitive_fields: [:secret]
end

defmodule DodoPayments.WebhookHeaders do
  @moduledoc "Configured webhook headers. Inspection redacts every returned header value."
  use DodoPayments.Schema,
    fields: [headers: %{optional(String.t()) => String.t()}, sensitive: [String.t()]],
    sensitive_fields: [:headers]
end

defmodule DodoPayments.LicenseKey do
  @moduledoc "A merchant license-key record. Inspection always redacts the issued key."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      brand_id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      customer_id: String.t(),
      instances_count: number(),
      key: String.t(),
      product_id: String.t(),
      source: DodoPayments.Enums.decoded_license_key_source(),
      status: DodoPayments.Enums.decoded_license_key_status(),
      activations_limit: number(),
      expires_at: String.t(),
      payment_id: String.t(),
      subscription_id: String.t()
    ],
    sensitive_fields: [:key]
end

defmodule DodoPayments.EntitlementGrant do
  @moduledoc "An entitlement grant. Inspection redacts credential-bearing delivery payloads."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      brand_id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      customer_id: String.t(),
      entitlement_id: String.t(),
      integration_type: DodoPayments.Enums.decoded_entitlement_integration_type(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      status: DodoPayments.Enums.decoded_entitlement_grant_status(),
      updated_at: String.t(),
      delivered_at: String.t(),
      digital_product_delivery: DodoPayments.ResponseTypes.object(),
      error_code: String.t(),
      error_message: String.t(),
      feature: DodoPayments.ResponseTypes.object(),
      license_key: DodoPayments.ResponseTypes.object(),
      oauth_expires_at: String.t(),
      oauth_url: String.t(),
      payment_id: String.t(),
      revocation_reason: String.t(),
      revoked_at: String.t(),
      subscription_id: String.t()
    ],
    sensitive_fields: [:license_key, :oauth_url]
end

defmodule DodoPayments.ShortLink do
  @moduledoc "A product short-link list item."
  use DodoPayments.Schema,
    fields: [
      created_at: String.t(),
      full_url: String.t(),
      product_id: String.t(),
      short_url: String.t()
    ]
end

defmodule DodoPayments.ShortLinkCreateResponse do
  @moduledoc "The URLs returned after creating a product short link."
  use DodoPayments.Schema, fields: [full_url: String.t(), short_url: String.t()]
end

defmodule DodoPayments.LocalizedPrice do
  @moduledoc "A localized product-price rule."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      amount: number(),
      created_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      mode: DodoPayments.Enums.decoded_pricing_mode(),
      product_id: String.t(),
      updated_at: String.t(),
      country_code: DodoPayments.Enums.decoded_country_code()
    ]
end

defmodule DodoPayments.LocalizedPriceListResponse do
  @moduledoc "The non-paginated localized-price list envelope."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.localized_price()]]
end

defmodule DodoPayments.ProductCollectionListItem do
  @moduledoc "A product-collection list item."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      created_at: String.t(),
      name: String.t(),
      products_count: number(),
      updated_at: String.t(),
      description: String.t(),
      image: String.t()
    ]
end

defmodule DodoPayments.ProductCollection do
  @moduledoc "A product collection and its groups."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      brand_id: String.t(),
      created_at: String.t(),
      groups: [DodoPayments.ResponseTypes.product_collection_group()],
      name: String.t(),
      updated_at: String.t(),
      description: String.t(),
      effective_at_on_downgrade: DodoPayments.Enums.decoded_effective_at(),
      effective_at_on_upgrade: DodoPayments.Enums.decoded_effective_at(),
      image: String.t(),
      on_payment_failure: DodoPayments.Enums.decoded_payment_failure_behavior(),
      proration_billing_mode_on_downgrade: DodoPayments.Enums.decoded_proration_billing_mode(),
      proration_billing_mode_on_upgrade: DodoPayments.Enums.decoded_proration_billing_mode()
    ]
end

defmodule DodoPayments.ProductCollectionUnarchiveResponse do
  @moduledoc "The result of unarchiving a product collection."
  use DodoPayments.Schema,
    fields: [
      collection_id: String.t(),
      excluded_product_ids: [String.t()],
      message: String.t()
    ]
end

defmodule DodoPayments.ProductCollectionGroup do
  @moduledoc "A created product-collection group."
  use DodoPayments.Schema,
    fields: [
      group_id: String.t(),
      products: [DodoPayments.ResponseTypes.product_collection_product()],
      status: boolean(),
      group_name: String.t()
    ]
end

defmodule DodoPayments.ProductCollectionProduct do
  @moduledoc "A product as represented inside a product collection."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      addons_count: number(),
      files_count: number(),
      has_credit_entitlements: boolean(),
      is_recurring: boolean(),
      license_key_enabled: boolean(),
      meters_count: number(),
      product_id: String.t(),
      status: boolean(),
      currency: DodoPayments.Enums.decoded_currency(),
      description: String.t(),
      name: String.t(),
      price: number(),
      price_detail: DodoPayments.ResponseTypes.object(),
      tax_category: DodoPayments.Enums.decoded_tax_category(),
      tax_inclusive: boolean()
    ]
end

defmodule DodoPayments.CustomerPaymentMethodsResponse do
  @moduledoc "A customer's saved payment methods."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.customer_payment_method()]]
end

defmodule DodoPayments.DiscountCustomer do
  @moduledoc "A customer attached to a discount allow list."
  use DodoPayments.Schema, fields: [customer_id: String.t()]
end

defmodule DodoPayments.DiscountCustomersResponse do
  @moduledoc "Customers attached by one discount allow-list request."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.discount_customer()]]
end

defmodule DodoPayments.CustomerCreditEntitlementsResponse do
  @moduledoc "A customer's credit entitlements and current balances."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.customer_credit_entitlement()]]
end

defmodule DodoPayments.CustomerEntitlementsResponse do
  @moduledoc "A customer's entitlement delivery status rows."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.customer_entitlement()]]
end

defmodule DodoPayments.CustomerWallet do
  @moduledoc "A customer wallet in one currency."
  use DodoPayments.Schema,
    fields: [
      balance: number(),
      created_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      customer_id: String.t(),
      updated_at: String.t()
    ]
end

defmodule DodoPayments.CustomerWalletListResponse do
  @moduledoc "A customer's wallets and aggregate USD balance."
  use DodoPayments.Schema,
    fields: [items: [DodoPayments.ResponseTypes.customer_wallet()], total_balance_usd: number()]
end

defmodule DodoPayments.CustomerWalletTransaction do
  @moduledoc "A customer-wallet ledger transaction."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      after_balance: number(),
      amount: number(),
      before_balance: number(),
      business_id: String.t(),
      created_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      customer_id: String.t(),
      event_type: DodoPayments.Enums.decoded_wallet_event_type(),
      is_credit: boolean(),
      reason: String.t(),
      reference_object_id: String.t()
    ]
end

defmodule DodoPayments.BalanceLedgerEntry do
  @moduledoc "A merchant balance-ledger entry."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      amount: number(),
      business_id: String.t(),
      created_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      event_type: DodoPayments.Enums.decoded_balance_event_type(),
      is_credit: boolean(),
      usd_equivalent_amount: number(),
      after_balance: number(),
      before_balance: number(),
      description: String.t(),
      reference_object_id: String.t()
    ]
end

defmodule DodoPayments.SubscriptionChargeResponse do
  @moduledoc "The payment created by an on-demand subscription charge."
  use DodoPayments.Schema, fields: [payment_id: String.t()]
end

defmodule DodoPayments.SubscriptionUsageHistory do
  @moduledoc "A subscription's metered usage for one billing period."
  use DodoPayments.Schema,
    fields: [
      end_date: String.t(),
      meters: [DodoPayments.ResponseTypes.subscription_usage_meter()],
      start_date: String.t()
    ]
end

defmodule DodoPayments.SubscriptionPreviewChangePlanResponse do
  @moduledoc "A subscription plan-change preview."
  use DodoPayments.Schema,
    fields: [
      immediate_charge: DodoPayments.ResponseTypes.subscription_immediate_charge(),
      new_plan: DodoPayments.ResponseTypes.object()
    ]
end

defmodule DodoPayments.SubscriptionCreditUsageResponse do
  @moduledoc "Credit usage for entitlements attached to a subscription."
  use DodoPayments.Schema,
    fields: [
      items: [DodoPayments.ResponseTypes.subscription_credit_usage()],
      subscription_id: String.t()
    ]
end

defmodule DodoPayments.DisputeListItem do
  @moduledoc "A dispute list item."
  use DodoPayments.Schema,
    fields: [
      amount: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      currency: String.t(),
      dispute_id: String.t(),
      dispute_stage: DodoPayments.Enums.decoded_dispute_stage(),
      dispute_status: DodoPayments.Enums.decoded_dispute_status(),
      payment_id: String.t(),
      payment_provider: DodoPayments.Enums.decoded_payment_provider(),
      is_resolved_by_rdr: boolean()
    ]
end

defmodule DodoPayments.Dispute do
  @moduledoc "A retrieved dispute."
  use DodoPayments.Schema,
    fields: [
      amount: String.t(),
      brand_id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      currency: String.t(),
      customer: DodoPayments.ResponseTypes.customer_limited_details(),
      dispute_id: String.t(),
      dispute_stage: DodoPayments.Enums.decoded_dispute_stage(),
      dispute_status: DodoPayments.Enums.decoded_dispute_status(),
      payment_id: String.t(),
      payment_provider: DodoPayments.Enums.decoded_payment_provider(),
      is_resolved_by_rdr: boolean(),
      reason: String.t(),
      remarks: String.t()
    ]
end

defmodule DodoPayments.UsageEventIngestResponse do
  @moduledoc "The number of usage events accepted by an ingest request."
  use DodoPayments.Schema, fields: [ingested_count: number()]
end

defmodule DodoPayments.CreditEntitlement do
  @moduledoc "A credit entitlement definition."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      name: String.t(),
      overage_behavior: DodoPayments.Enums.decoded_cbb_overage_behavior(),
      overage_enabled: boolean(),
      precision: number(),
      rollover_enabled: boolean(),
      unit: String.t(),
      updated_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      description: String.t(),
      expires_after_days: number(),
      max_rollover_count: number(),
      overage_limit: number(),
      price_per_unit: String.t(),
      rollover_percentage: number(),
      rollover_timeframe_count: number(),
      rollover_timeframe_interval: DodoPayments.Enums.decoded_time_interval()
    ]
end

defmodule DodoPayments.CustomerCreditBalance do
  @moduledoc "A customer's balance for one credit entitlement."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      balance: String.t() | number(),
      created_at: String.t(),
      credit_entitlement_id: String.t(),
      customer_id: String.t(),
      overage: String.t() | number(),
      updated_at: String.t(),
      last_transaction_at: String.t()
    ]
end

defmodule DodoPayments.CreditGrant do
  @moduledoc "A grant contributing to a customer's credit balance."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      created_at: String.t(),
      credit_entitlement_id: String.t(),
      customer_id: String.t(),
      initial_amount: String.t() | number(),
      is_expired: boolean(),
      is_rolled_over: boolean(),
      remaining_amount: String.t() | number(),
      rollover_count: number(),
      source_type: DodoPayments.Enums.decoded_credit_grant_source_type(),
      updated_at: String.t(),
      expires_at: String.t(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      parent_grant_id: String.t(),
      source_id: String.t()
    ]
end

defmodule DodoPayments.CreditLedgerEntry do
  @moduledoc "A credit-balance ledger entry."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      amount: String.t(),
      balance_after: String.t(),
      balance_before: String.t(),
      brand_id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      credit_entitlement_id: String.t(),
      customer_id: String.t(),
      is_credit: boolean(),
      metadata: DodoPayments.ResponseTypes.metadata(),
      overage_after: String.t(),
      overage_before: String.t(),
      transaction_type: DodoPayments.Enums.decoded_credit_transaction_type(),
      description: String.t(),
      grant_id: String.t(),
      reference_id: String.t(),
      reference_type: String.t()
    ]
end

defmodule DodoPayments.CreditLedgerEntryCreateResponse do
  @moduledoc "The credit-balance state after creating a ledger entry."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      amount: String.t(),
      balance_after: String.t(),
      balance_before: String.t(),
      created_at: String.t(),
      credit_entitlement_id: String.t(),
      customer_id: String.t(),
      entry_type: DodoPayments.Enums.decoded_ledger_entry_type(),
      is_credit: boolean(),
      overage_after: String.t(),
      overage_before: String.t(),
      grant_id: String.t(),
      reason: String.t()
    ]
end

defmodule DodoPayments.EntitlementFileUploadResponse do
  @moduledoc "The identifier returned after attaching a file to an entitlement."
  use DodoPayments.Schema, fields: [file_id: String.t()]
end

defmodule DodoPayments.LicenseKeyInstance do
  @moduledoc "An activation instance for a license key."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      business_id: String.t(),
      created_at: String.t(),
      license_key_id: String.t(),
      name: String.t()
    ]
end

defmodule DodoPayments.Payout do
  @moduledoc "A payout list item."
  use DodoPayments.Schema,
    fields: [
      amount: number(),
      business_id: String.t(),
      chargebacks: number(),
      created_at: String.t(),
      currency: DodoPayments.Enums.decoded_currency(),
      fee: number(),
      payment_method: String.t(),
      payout_id: String.t(),
      refunds: number(),
      status: DodoPayments.Enums.decoded_payout_status(),
      tax: number(),
      updated_at: String.t(),
      name: String.t(),
      payout_document_url: String.t(),
      remarks: String.t()
    ]
end

defmodule DodoPayments.PayoutBreakupItem do
  @moduledoc "An event-type aggregate in a payout breakup."
  use DodoPayments.Schema, fields: [event_type: String.t(), total: number()]
end

defmodule DodoPayments.PayoutBreakupDetail do
  @moduledoc "An individual ledger entry in a payout breakup."
  use DodoPayments.Schema,
    fields: [
      id: String.t(),
      created_at: String.t(),
      event_type: String.t(),
      original_amount: number(),
      original_currency: String.t(),
      payout_currency_amount: number(),
      usd_equivalent_amount: number(),
      description: String.t(),
      reference_object_id: String.t()
    ]
end
