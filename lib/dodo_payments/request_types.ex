defmodule DodoPayments.RequestTypes do
  @source_sdk_version DodoPayments.SourceMetadata.source_sdk_version()

  @moduledoc """
  Compile-time request type metadata for the public resource API.

  The field catalogue is extracted from the declarations in the source-locked
  `dodopayments` #{@source_sdk_version} npm package. It describes the parameter map
  accepted by each operation; path parameters are removed when a public
  endpoint type is emitted.

  Elixir typespecs cannot express a required literal string key. Generated
  endpoint types therefore expose the exact atom-keyed fields for editor and
  Dialyzer help and include a compatibility branch for the string and mixed
  atom/string maps accepted by the runtime.
  """

  @typedoc "A nested request object key accepted by the request codec."
  @type input_key :: atom() | String.t() | integer() | float()

  @typedoc """
  A value accepted by the request codec.

  `Date`, `DateTime`, `NaiveDateTime`, and `Decimal` values are encoded to
  their wire representations before sending. Endpoint fields retain the
  semantic primitive declared upstream; this broader type documents the
  transport-compatible string-key and nested-map fallback.
  """
  @type input_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | atom()
          | Date.t()
          | DateTime.t()
          | NaiveDateTime.t()
          | Decimal.t()
          | [input_value()]
          | input_object()

  @typedoc "A recursively encodable request object."
  @type input_object :: %{optional(input_key()) => input_value()}

  @typedoc "Compatibility shape for string-keyed and mixed-key parameter maps."
  @type compatibility_params :: %{optional(atom() | String.t()) => input_value()}

  @typedoc "Flat metadata object declared by the upstream request schemas."
  @type flat_metadata ::
          %{optional(atom() | String.t()) => String.t() | number() | boolean()}

  @typedoc "String-valued object used for webhook data and static checkout parameters."
  @type string_map :: %{optional(atom() | String.t()) => String.t()}

  @typedoc "Billing address used by payment and subscription creation."
  @type billing_address ::
          %{
            required(:country) => DodoPayments.Enums.country_code(),
            optional(:city) => String.t(),
            optional(:state) => String.t(),
            optional(:street) => String.t(),
            optional(:zipcode) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Existing- or new-customer request used by checkout flows."
  @type customer_request ::
          %{
            required(:customer_id) => String.t(),
            optional(String.t()) => input_value()
          }
          | %{
              required(:email) => String.t(),
              optional(:name) => String.t(),
              optional(:phone_number) => String.t(),
              optional(String.t()) => input_value()
            }
          | compatibility_params()

  @typedoc "Feature switches accepted by checkout session creation and preview."
  @type checkout_session_flags ::
          %{
            optional(:allow_currency_selection) => boolean(),
            optional(:allow_customer_editing_business_name) => boolean(),
            optional(:allow_customer_editing_city) => boolean(),
            optional(:allow_customer_editing_country) => boolean(),
            optional(:allow_customer_editing_email) => boolean(),
            optional(:allow_customer_editing_name) => boolean(),
            optional(:allow_customer_editing_state) => boolean(),
            optional(:allow_customer_editing_street) => boolean(),
            optional(:allow_customer_editing_tax_id) => boolean(),
            optional(:allow_customer_editing_zipcode) => boolean(),
            optional(:allow_discount_code) => boolean(),
            optional(:allow_editing_addons) => boolean(),
            optional(:allow_phone_number_collection) => boolean(),
            optional(:allow_tax_id) => boolean(),
            optional(:always_create_new_customer) => boolean(),
            optional(:redirect_immediately) => boolean(),
            optional(:require_phone_number) => boolean(),
            optional(:single_page) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Subscription add-on request."
  @type attach_addon ::
          %{
            required(:addon_id) => String.t(),
            required(:quantity) => number(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "One-time product cart item used by payment and subscription creation."
  @type one_time_product_cart_item ::
          %{
            required(:product_id) => String.t(),
            required(:quantity) => number(),
            optional(:amount) => number(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Credit entitlement override on a checkout product item."
  @type checkout_credit_entitlement ::
          %{
            required(:credit_entitlement_id) => String.t(),
            required(:credits_amount) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Product cart item used by checkout session creation and preview."
  @type checkout_product_item ::
          %{
            required(:product_id) => String.t(),
            required(:quantity) => number(),
            optional(:addons) => [attach_addon()],
            optional(:amount) => number(),
            optional(:credit_entitlements) => [checkout_credit_entitlement()],
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "One usage event accepted by the bulk ingest endpoint."
  @type usage_event_input ::
          %{
            required(:customer_id) => String.t(),
            required(:event_id) => String.t(),
            required(:event_name) => String.t(),
            optional(:metadata) => flat_metadata(),
            optional(:timestamp) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "New or existing payment method selection for a subscription."
  @type subscription_payment_method ::
          %{
            required(:type) => DodoPayments.Enums.subscription_payment_method_selection(),
            optional(:allowed_payment_method_types) => [DodoPayments.Enums.payment_method_type()],
            optional(:return_url) => String.t(),
            optional(String.t()) => input_value()
          }
          | %{
              required(:payment_method_id) => String.t(),
              required(:type) => DodoPayments.Enums.subscription_payment_method_selection(),
              optional(String.t()) => input_value()
            }
          | compatibility_params()

  @typedoc "One line item in a partial-refund request."
  @type refund_item ::
          %{
            required(:item_id) => String.t(),
            optional(:amount) => number(),
            optional(:tax_inclusive) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Meter aggregation configuration."
  @type meter_aggregation ::
          %{
            required(:type) => DodoPayments.Enums.meter_aggregation(),
            optional(:key) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "One leaf condition in a meter filter."
  @type meter_filter_condition ::
          %{
            required(:key) => String.t(),
            required(:operator) => DodoPayments.Enums.meter_filter_operator(),
            required(:value) => String.t() | number() | boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Recursive meter filter; Dodo accepts at most three nesting levels."
  @type meter_filter ::
          %{
            required(:clauses) => [meter_filter_condition()] | [meter_filter()],
            required(:conjunction) => DodoPayments.Enums.meter_conjunction(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "A product membership entry inside a product-collection group."
  @type collection_group_product ::
          %{
            required(:product_id) => String.t(),
            optional(:status) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "A product group supplied while creating a product collection."
  @type collection_group ::
          %{
            required(:products) => [collection_group_product()],
            optional(:group_name) => String.t(),
            optional(:status) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Credit-entitlement settings attached to a product."
  @type product_credit_entitlement ::
          %{
            required(:credit_entitlement_id) => String.t(),
            required(:credits_amount) => String.t(),
            optional(:currency) => DodoPayments.Enums.currency(),
            optional(:expires_after_days) => number(),
            optional(:low_balance_threshold_percent) => number(),
            optional(:max_rollover_count) => number(),
            optional(:overage_behavior) => DodoPayments.Enums.cbb_overage_behavior(),
            optional(:overage_enabled) => boolean(),
            optional(:overage_limit) => String.t(),
            optional(:price_per_unit) => String.t(),
            optional(:proration_behavior) => DodoPayments.Enums.cbb_proration_behavior(),
            optional(:rollover_enabled) => boolean(),
            optional(:rollover_percentage) => number(),
            optional(:rollover_timeframe_count) => number(),
            optional(:rollover_timeframe_interval) => DodoPayments.Enums.time_interval(),
            optional(:trial_credits) => String.t(),
            optional(:trial_credits_expire_after_trial) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "An entitlement attached to a product."
  @type product_entitlement ::
          %{
            required(:entitlement_id) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Deprecated digital-delivery settings accepted on product creation."
  @type product_digital_delivery_create ::
          %{
            optional(:external_url) => String.t(),
            optional(:instructions) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Deprecated digital-delivery settings accepted on product update."
  @type product_digital_delivery_update ::
          %{
            optional(:external_url) => String.t(),
            optional(:files) => [String.t()],
            optional(:instructions) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Fixed validity period for deprecated product-level license keys."
  @type license_key_duration ::
          %{
            required(:count) => number(),
            required(:interval) => DodoPayments.Enums.time_interval(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "One usage meter attached to a usage-based product price."
  @type product_meter ::
          %{
            required(:meter_id) => String.t(),
            optional(:credit_entitlement_id) => String.t(),
            optional(:description) => String.t(),
            optional(:free_threshold) => number(),
            optional(:measurement_unit) => String.t(),
            optional(:meter_units_per_credit) => String.t(),
            optional(:name) => String.t(),
            optional(:price_per_unit) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "One-time product price configuration."
  @type one_time_product_price ::
          %{
            required(:currency) => DodoPayments.Enums.currency(),
            required(:discount) => number(),
            required(:price) => number(),
            required(:purchasing_power_parity) => boolean(),
            required(:type) => :one_time_price,
            optional(:pay_what_you_want) => boolean(),
            optional(:suggested_price) => number(),
            optional(:tax_inclusive) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Recurring product price configuration."
  @type recurring_product_price ::
          %{
            required(:currency) => DodoPayments.Enums.currency(),
            required(:discount) => number(),
            required(:payment_frequency_count) => number(),
            required(:payment_frequency_interval) => DodoPayments.Enums.time_interval(),
            required(:price) => number(),
            required(:purchasing_power_parity) => boolean(),
            required(:subscription_period_count) => number(),
            required(:subscription_period_interval) => DodoPayments.Enums.time_interval(),
            required(:type) => :recurring_price,
            optional(:tax_inclusive) => boolean(),
            optional(:trial_amount) => number(),
            optional(:trial_apply_discounts) => boolean(),
            optional(:trial_period_days) => number(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Usage-based product price configuration."
  @type usage_based_product_price ::
          %{
            required(:currency) => DodoPayments.Enums.currency(),
            required(:discount) => number(),
            required(:fixed_price) => number(),
            required(:payment_frequency_count) => number(),
            required(:payment_frequency_interval) => DodoPayments.Enums.time_interval(),
            required(:purchasing_power_parity) => boolean(),
            required(:subscription_period_count) => number(),
            required(:subscription_period_interval) => DodoPayments.Enums.time_interval(),
            required(:type) => :usage_based_price,
            optional(:meters) => [product_meter()],
            optional(:tax_inclusive) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Product price union accepted by product create and update."
  @type product_price ::
          one_time_product_price()
          | recurring_product_price()
          | usage_based_product_price()

  @typedoc "A custom field collected during checkout."
  @type checkout_custom_field ::
          %{
            required(:field_type) => DodoPayments.Enums.custom_field_type(),
            required(:key) => String.t(),
            required(:label) => String.t(),
            optional(:options) => [String.t()],
            optional(:placeholder) => String.t(),
            optional(:required) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Color values for one checkout theme mode."
  @type checkout_theme_mode ::
          %{
            optional(:bg_primary) => String.t(),
            optional(:bg_secondary) => String.t(),
            optional(:border_primary) => String.t(),
            optional(:border_secondary) => String.t(),
            optional(:button_primary) => String.t(),
            optional(:button_primary_hover) => String.t(),
            optional(:button_secondary) => String.t(),
            optional(:button_secondary_hover) => String.t(),
            optional(:button_text_primary) => String.t(),
            optional(:button_text_secondary) => String.t(),
            optional(:input_focus_border) => String.t(),
            optional(:text_error) => String.t(),
            optional(:text_placeholder) => String.t(),
            optional(:text_primary) => String.t(),
            optional(:text_secondary) => String.t(),
            optional(:text_success) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Custom light/dark theme configuration for checkout."
  @type checkout_theme_config ::
          %{
            optional(:dark) => checkout_theme_mode(),
            optional(:font_primary_url) => String.t(),
            optional(:font_secondary_url) => String.t(),
            optional(:font_size) => DodoPayments.Enums.font_size(),
            optional(:font_weight) => DodoPayments.Enums.font_weight(),
            optional(:light) => checkout_theme_mode(),
            optional(:pay_button_text) => String.t(),
            optional(:radius) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Checkout page customization."
  @type checkout_customization ::
          %{
            optional(:force_language) => String.t(),
            optional(:show_on_demand_tag) => boolean(),
            optional(:show_order_details) => boolean(),
            optional(:theme) => DodoPayments.Enums.checkout_theme(),
            optional(:theme_config) => checkout_theme_config(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "On-demand subscription authorization and initial-charge settings."
  @type on_demand_subscription ::
          %{
            required(:mandate_only) => boolean(),
            optional(:adaptive_currency_fees_inclusive) => boolean(),
            optional(:product_currency) => DodoPayments.Enums.currency(),
            optional(:product_description) => String.t(),
            optional(:product_price) => number(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Subscription overrides supplied to a checkout session."
  @type checkout_subscription_data ::
          %{
            optional(:on_demand) => on_demand_subscription(),
            optional(:trial_period_days) => number(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Integration-specific entitlement configuration."
  @type entitlement_integration_config ::
          %{
            required(:feature_id) => String.t(),
            required(:feature_type) => DodoPayments.Enums.feature_type(),
            optional(String.t()) => input_value()
          }
          | %{
              required(:permission) => DodoPayments.Enums.github_permission(),
              required(:target_id) => String.t(),
              optional(String.t()) => input_value()
            }
          | %{
              required(:guild_id) => String.t(),
              optional(:role_id) => String.t(),
              optional(String.t()) => input_value()
            }
          | %{
              required(:chat_id) => String.t(),
              optional(String.t()) => input_value()
            }
          | %{
              required(:figma_file_id) => String.t(),
              optional(String.t()) => input_value()
            }
          | %{
              required(:framer_template_id) => String.t(),
              optional(String.t()) => input_value()
            }
          | %{
              required(:notion_template_id) => String.t(),
              optional(String.t()) => input_value()
            }
          | %{
              required(:digital_file_ids) => [String.t()],
              optional(:external_url) => String.t(),
              optional(:instructions) => String.t(),
              optional(:legacy_file_ids) => [String.t()],
              optional(String.t()) => input_value()
            }
          | %{
              optional(:activation_message) => String.t(),
              optional(:activations_limit) => number(),
              optional(:duration_count) => number(),
              optional(:duration_interval) => DodoPayments.Enums.time_interval(),
              optional(:fulfillment_mode) => DodoPayments.Enums.license_fulfillment_mode(),
              optional(String.t()) => input_value()
            }
          | compatibility_params()

  @typedoc "Per-currency option for a discount."
  @type discount_currency_option ::
          %{
            required(:currency) => DodoPayments.Enums.currency(),
            optional(:is_default) => boolean(),
            optional(:max_amount_possible) => number(),
            optional(:minimum_subtotal) => number(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Credit-entitlement settings updated on a subscription."
  @type subscription_credit_entitlement ::
          %{
            required(:credit_entitlement_id) => String.t(),
            optional(:credits_amount) => String.t(),
            optional(:expires_after_days) => number(),
            optional(:low_balance_threshold_percent) => number(),
            optional(:max_rollover_count) => number(),
            optional(:overage_enabled) => boolean(),
            optional(:overage_limit) => String.t(),
            optional(:rollover_enabled) => boolean(),
            optional(:rollover_percentage) => number(),
            optional(:rollover_timeframe_count) => number(),
            optional(:rollover_timeframe_interval) => DodoPayments.Enums.time_interval(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Request to disable on-demand charging at a future billing date."
  @type disable_on_demand ::
          %{
            required(:next_billing_date) => String.t(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @typedoc "Controls whether customer credit may be used or purchased for a charge."
  @type customer_balance_config ::
          %{
            optional(:allow_customer_credits_purchase) => boolean(),
            optional(:allow_customer_credits_usage) => boolean(),
            optional(String.t()) => input_value()
          }
          | compatibility_params()

  @schemas %{
    addons_create:
      {:upstream, "resources/addons.ts", "AddonCreateParams",
       [
         {:currency, true, {:enum, :currency}},
         {:name, true, :string},
         {:price, true, :number},
         {:tax_category, true, {:enum, :tax_category}},
         {:description, false, :string}
       ]},
    addons_list:
      {:upstream, "resources/addons.ts", "AddonListParams",
       [{:page_number, false, :number}, {:page_size, false, :number}]},
    addons_update:
      {:upstream, "resources/addons.ts", "AddonUpdateParams",
       [
         {:currency, false, {:enum, :currency}},
         {:description, false, :string},
         {:image_id, false, :string},
         {:name, false, :string},
         {:price, false, :number},
         {:tax_category, false, {:enum, :tax_category}}
       ]},
    balance_ledger_list:
      {:upstream, "resources/balances.ts", "BalanceRetrieveLedgerParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:currency, false, {:enum, :currency}},
         {:event_type, false, {:enum, :balance_event_type}},
         {:limit, false, :number},
         {:reference_object_id, false, :string}
       ]},
    brands_archive:
      {:upstream, "resources/brands.ts", "BrandArchiveParams",
       [{:move_products_to, false, :string}]},
    brands_create:
      {:upstream, "resources/brands.ts", "BrandCreateParams",
       [
         {:description, false, :string},
         {:name, false, :string},
         {:statement_descriptor, false, :string},
         {:support_email, false, :string},
         {:url, false, :string}
       ]},
    brands_list:
      {:upstream, "resources/brands.ts", "BrandListParams",
       [{:include_archived, false, :boolean}]},
    brands_update:
      {:upstream, "resources/brands.ts", "BrandUpdateParams",
       [
         {:description, false, :string},
         {:image_id, false, :string},
         {:name, false, :string},
         {:statement_descriptor, false, :string},
         {:support_email, false, :string},
         {:url, false, :string}
       ]},
    checkout_sessions_create:
      {:upstream, "resources/checkout-sessions.ts", "CheckoutSessionCreateParams",
       [
         {:product_cart, true, {:list, {:named, :checkout_product_item}}},
         {:allowed_payment_method_types, false, {:list, {:enum, :payment_method_type}}},
         {:billing_address, false, {:named, :billing_address}},
         {:billing_currency, false, {:enum, :currency}},
         {:cancel_url, false, :string},
         {:confirm, false, :boolean},
         {:custom_fields, false, {:list, {:named, :checkout_custom_field}}},
         {:customer, false, {:named, :customer_request}},
         {:customer_business_name, false, :string},
         {:customization, false, {:named, :checkout_customization}},
         {:discount_code, false, :string},
         {:discount_codes, false, {:list, :string}},
         {:feature_flags, false, {:named, :checkout_session_flags}},
         {:force_3ds, false, :boolean},
         {:mandate_min_amount_inr_paise, false, :number},
         {:metadata, false, {:named, :flat_metadata}},
         {:minimal_address, false, :boolean},
         {:payment_method_id, false, :string},
         {:product_collection_id, false, :string},
         {:return_url, false, :string},
         {:short_link, false, :boolean},
         {:show_saved_payment_methods, false, :boolean},
         {:subscription_data, false, {:named, :checkout_subscription_data}},
         {:tax_id, false, :string}
       ]},
    checkout_sessions_preview:
      {:upstream, "resources/checkout-sessions.ts", "CheckoutSessionPreviewParams",
       [
         {:product_cart, true, {:list, {:named, :checkout_product_item}}},
         {:allowed_payment_method_types, false, {:list, {:enum, :payment_method_type}}},
         {:billing_address, false, {:named, :billing_address}},
         {:billing_currency, false, {:enum, :currency}},
         {:cancel_url, false, :string},
         {:confirm, false, :boolean},
         {:custom_fields, false, {:list, {:named, :checkout_custom_field}}},
         {:customer, false, {:named, :customer_request}},
         {:customer_business_name, false, :string},
         {:customization, false, {:named, :checkout_customization}},
         {:discount_code, false, :string},
         {:discount_codes, false, {:list, :string}},
         {:feature_flags, false, {:named, :checkout_session_flags}},
         {:force_3ds, false, :boolean},
         {:mandate_min_amount_inr_paise, false, :number},
         {:metadata, false, {:named, :flat_metadata}},
         {:minimal_address, false, :boolean},
         {:payment_method_id, false, :string},
         {:product_collection_id, false, :string},
         {:return_url, false, :string},
         {:short_link, false, :boolean},
         {:show_saved_payment_methods, false, :boolean},
         {:subscription_data, false, {:named, :checkout_subscription_data}},
         {:tax_id, false, :string}
       ]},
    collection_group_items_create:
      {:upstream, "resources/product-collections/groups/items.ts", "ItemCreateParams",
       [{:id, true, :string}, {:products, true, {:list, {:named, :collection_group_product}}}]},
    collection_group_items_update:
      {:upstream, "resources/product-collections/groups/items.ts", "ItemUpdateParams",
       [{:id, true, :string}, {:group_id, true, :string}, {:status, true, :boolean}]},
    collection_groups_create:
      {:upstream, "resources/product-collections/groups/groups.ts", "GroupCreateParams",
       [
         {:products, true, {:list, {:named, :collection_group_product}}},
         {:group_name, false, :string},
         {:status, false, :boolean}
       ]},
    collection_groups_update:
      {:upstream, "resources/product-collections/groups/groups.ts", "GroupUpdateParams",
       [
         {:id, true, :string},
         {:group_name, false, :string},
         {:product_order, false, {:list, :string}},
         {:status, false, :boolean}
       ]},
    credit_balance_grants_list:
      {:upstream, "resources/credit-entitlements/balances.ts", "BalanceListGrantsParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:credit_entitlement_id, true, :string},
         {:status, false, {:enum, :credit_grant_status}}
       ]},
    credit_balance_ledger_entries_create:
      {:upstream, "resources/credit-entitlements/balances.ts", "BalanceCreateLedgerEntryParams",
       [
         {:credit_entitlement_id, true, :string},
         {:amount, true, :string},
         {:entry_type, true, {:enum, :ledger_entry_type}},
         {:expires_at, false, :string},
         {:idempotency_key, false, :string},
         {:metadata, false, {:named, :flat_metadata}},
         {:reason, false, :string}
       ]},
    credit_balance_ledger_list:
      {:upstream, "resources/credit-entitlements/balances.ts", "BalanceListLedgerParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:credit_entitlement_id, true, :string},
         {:end_date, false, :string},
         {:start_date, false, :string},
         {:transaction_type, false, :string}
       ]},
    credit_balances_list:
      {:upstream, "resources/credit-entitlements/balances.ts", "BalanceListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:customer_id, false, :string}
       ]},
    credit_entitlements_create:
      {:upstream, "resources/credit-entitlements/credit-entitlements.ts",
       "CreditEntitlementCreateParams",
       [
         {:name, true, :string},
         {:overage_enabled, true, :boolean},
         {:precision, true, :number},
         {:rollover_enabled, true, :boolean},
         {:unit, true, :string},
         {:currency, false, {:enum, :currency}},
         {:description, false, :string},
         {:expires_after_days, false, :number},
         {:max_rollover_count, false, :number},
         {:overage_behavior, false, {:enum, :cbb_overage_behavior}},
         {:overage_limit, false, :number},
         {:price_per_unit, false, :string},
         {:rollover_percentage, false, :number},
         {:rollover_timeframe_count, false, :number},
         {:rollover_timeframe_interval, false, {:enum, :time_interval}}
       ]},
    credit_entitlements_list:
      {:upstream, "resources/credit-entitlements/credit-entitlements.ts",
       "CreditEntitlementListParams",
       [{:page_number, false, :number}, {:page_size, false, :number}, {:deleted, false, :boolean}]},
    credit_entitlements_update:
      {:upstream, "resources/credit-entitlements/credit-entitlements.ts",
       "CreditEntitlementUpdateParams",
       [
         {:currency, false, {:enum, :currency}},
         {:description, false, :string},
         {:expires_after_days, false, :number},
         {:max_rollover_count, false, :number},
         {:name, false, :string},
         {:overage_behavior, false, {:enum, :cbb_overage_behavior}},
         {:overage_enabled, false, :boolean},
         {:overage_limit, false, :number},
         {:price_per_unit, false, :string},
         {:rollover_enabled, false, :boolean},
         {:rollover_percentage, false, :number},
         {:rollover_timeframe_count, false, :number},
         {:rollover_timeframe_interval, false, {:enum, :time_interval}},
         {:unit, false, :string}
       ]},
    customer_entitlement_grants_list:
      {:upstream, "resources/customers/customers.ts", "CustomerListEntitlementGrantsParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:integration_type, false, {:enum, :entitlement_integration_type}},
         {:status, false, {:enum, :entitlement_grant_status}}
       ]},
    customer_portal_sessions_create:
      {:upstream, "resources/customers/customer-portal.ts", "CustomerPortalCreateParams",
       [{:return_url, false, :string}, {:send_email, false, :boolean}]},
    customer_wallet_ledger_entries_create:
      {:upstream, "resources/customers/wallets/ledger-entries.ts", "LedgerEntryCreateParams",
       [
         {:amount, true, :number},
         {:currency, true, {:enum, :currency}},
         {:entry_type, true, {:enum, :ledger_entry_type}},
         {:idempotency_key, false, :string},
         {:reason, false, :string}
       ]},
    customer_wallet_ledger_entries_list:
      {:upstream, "resources/customers/wallets/ledger-entries.ts", "LedgerEntryListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:currency, false, {:enum, :currency}}
       ]},
    customers_create:
      {:upstream, "resources/customers/customers.ts", "CustomerCreateParams",
       [
         {:email, true, :string},
         {:name, true, :string},
         {:metadata, false, {:named, :flat_metadata}},
         {:phone_number, false, :string}
       ]},
    customers_list:
      {:upstream, "resources/customers/customers.ts", "CustomerListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:email, false, :string},
         {:name, false, :string}
       ]},
    customers_update:
      {:upstream, "resources/customers/customers.ts", "CustomerUpdateParams",
       [
         {:email, false, :string},
         {:metadata, false, {:named, :flat_metadata}},
         {:name, false, :string},
         {:phone_number, false, :string}
       ]},
    discounts_create:
      {:upstream, "resources/discounts.ts", "DiscountCreateParams",
       [
         {:amount, true, :number},
         {:type, true, {:enum, :discount_type}},
         {:code, false, :string},
         {:currency_options, false, {:list, {:named, :discount_currency_option}}},
         {:customer_eligibility, false, {:enum, :customer_eligibility}},
         {:expires_at, false, :string},
         {:metadata, false, {:named, :flat_metadata}},
         {:name, false, :string},
         {:per_customer_usage_limit, false, :number},
         {:preserve_on_plan_change, false, :boolean},
         {:restricted_to, false, {:list, :string}},
         {:starts_at, false, :string},
         {:subscription_cycles, false, :number},
         {:usage_limit, false, :number}
       ]},
    discounts_list:
      {:upstream, "resources/discounts.ts", "DiscountListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:active, false, :boolean},
         {:code, false, :string},
         {:discount_type, false, {:enum, :discount_type}},
         {:product_id, false, :string}
       ]},
    discounts_update:
      {:upstream, "resources/discounts.ts", "DiscountUpdateParams",
       [
         {:amount, false, :number},
         {:code, false, :string},
         {:currency_options, false, {:list, {:named, :discount_currency_option}}},
         {:customer_eligibility, false, {:enum, :customer_eligibility}},
         {:expires_at, false, :string},
         {:metadata, false, {:named, :flat_metadata}},
         {:name, false, :string},
         {:per_customer_usage_limit, false, :number},
         {:preserve_on_plan_change, false, :boolean},
         {:restricted_to, false, {:list, :string}},
         {:starts_at, false, :string},
         {:subscription_cycles, false, :number},
         {:type, false, {:enum, :discount_type}},
         {:usage_limit, false, :number}
       ]},
    disputes_list:
      {:upstream, "resources/disputes.ts", "DisputeListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:customer_id, false, :string},
         {:dispute_stage, false, {:enum, :dispute_stage}},
         {:dispute_status, false, {:enum, :dispute_status}}
       ]},
    entitlement_grants_fulfill_license_key:
      {:upstream, "resources/entitlements/grants.ts", "GrantFulfillLicenseKeyParams",
       [
         {:key, true, :string},
         {:activations_limit, false, :number},
         {:expires_at, false, :string}
       ]},
    entitlement_grants_list:
      {:upstream, "resources/entitlements/grants.ts", "GrantListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:customer_id, false, :string},
         {:status, false, {:enum, :entitlement_grant_status}}
       ]},
    entitlements_create:
      {:upstream, "resources/entitlements/entitlements.ts", "EntitlementCreateParams",
       [
         {:integration_config, true, {:named, :entitlement_integration_config}},
         {:integration_type, true, {:enum, :entitlement_integration_type}},
         {:name, true, :string},
         {:description, false, :string},
         {:metadata, false, {:named, :flat_metadata}}
       ]},
    entitlements_list:
      {:upstream, "resources/entitlements/entitlements.ts", "EntitlementListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:integration_type, false, {:enum, :entitlement_integration_type}}
       ]},
    entitlements_update:
      {:upstream, "resources/entitlements/entitlements.ts", "EntitlementUpdateParams",
       [
         {:description, false, :string},
         {:integration_config, false, {:named, :entitlement_integration_config}},
         {:metadata, false, {:named, :flat_metadata}},
         {:name, false, :string}
       ]},
    license_key_instances_list:
      {:upstream, "resources/license-key-instances.ts", "LicenseKeyInstanceListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:grant_id, false, :string},
         {:license_key_id, false, :string}
       ]},
    license_key_instances_update:
      {:upstream, "resources/license-key-instances.ts", "LicenseKeyInstanceUpdateParams",
       [{:name, true, :string}]},
    license_keys_create:
      {:upstream, "resources/license-keys.ts", "LicenseKeyCreateParams",
       [
         {:customer_id, true, :string},
         {:key, true, :string},
         {:product_id, true, :string},
         {:activations_limit, false, :number},
         {:expires_at, false, :string}
       ]},
    license_keys_list:
      {:upstream, "resources/license-keys.ts", "LicenseKeyListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:customer_id, false, :string},
         {:product_id, false, :string},
         {:source, false, {:enum, :license_key_source}},
         {:status, false, {:enum, :license_key_status}}
       ]},
    license_keys_update:
      {:upstream, "resources/license-keys.ts", "LicenseKeyUpdateParams",
       [
         {:activations_limit, false, :number},
         {:disabled, false, :boolean},
         {:expires_at, false, :string}
       ]},
    licenses_activate:
      {:upstream, "resources/licenses.ts", "LicenseActivateParams",
       [{:license_key, true, :string}, {:name, true, :string}]},
    licenses_deactivate:
      {:upstream, "resources/licenses.ts", "LicenseDeactivateParams",
       [{:license_key, true, :string}, {:license_key_instance_id, true, :string}]},
    licenses_validate:
      {:upstream, "resources/licenses.ts", "LicenseValidateParams",
       [{:license_key, true, :string}, {:license_key_instance_id, false, :string}]},
    localized_prices_create:
      {:upstream, "resources/products/localized-prices.ts", "LocalizedPriceCreateParams",
       [
         {:amount, true, :number},
         {:currency, true, {:enum, :currency}},
         {:country_code, false, {:enum, :country_code}}
       ]},
    localized_prices_update:
      {:upstream, "resources/products/localized-prices.ts", "LocalizedPriceUpdateParams",
       [{:product_id, true, :string}, {:amount, false, :number}]},
    meters_create:
      {:upstream, "resources/meters.ts", "MeterCreateParams",
       [
         {:aggregation, true, {:named, :meter_aggregation}},
         {:event_name, true, :string},
         {:measurement_unit, true, :string},
         {:name, true, :string},
         {:description, false, :string},
         {:filter, false, {:named, :meter_filter}}
       ]},
    meters_list:
      {:upstream, "resources/meters.ts", "MeterListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:archived, false, :boolean}
       ]},
    payments_create:
      {:upstream, "resources/payments.ts", "PaymentCreateParams",
       [
         {:billing, true, {:named, :billing_address}},
         {:customer, true, {:named, :customer_request}},
         {:product_cart, true, {:list, {:named, :one_time_product_cart_item}}},
         {:adaptive_currency_fees_inclusive, false, :boolean},
         {:allowed_payment_method_types, false, {:list, {:enum, :payment_method_type}}},
         {:billing_currency, false, {:enum, :currency}},
         {:customer_business_name, false, :string},
         {:discount_code, false, :string},
         {:discount_codes, false, {:list, :string}},
         {:force_3ds, false, :boolean},
         {:metadata, false, {:named, :flat_metadata}},
         {:payment_link, false, :boolean},
         {:payment_method_id, false, :string},
         {:redirect_immediately, false, :boolean},
         {:require_phone_number, false, :boolean},
         {:return_url, false, :string},
         {:short_link, false, :boolean},
         {:show_saved_payment_methods, false, :boolean},
         {:tax_id, false, :string}
       ]},
    payments_list:
      {:upstream, "resources/payments.ts", "PaymentListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:brand_id, false, :string},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:currency, false, {:enum, :currency}},
         {:customer_id, false, :string},
         {:product_id, false, :string},
         {:status, false, {:enum, :intent_status}},
         {:subscription_id, false, :string}
       ]},
    payout_breakup_details_list:
      {:upstream, "resources/payouts/breakup/details.ts", "DetailListParams",
       [{:page_number, false, :number}, {:page_size, false, :number}]},
    payouts_list:
      {:upstream, "resources/payouts/payouts.ts", "PayoutListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string}
       ]},
    product_collections_create:
      {:upstream, "resources/product-collections/product-collections.ts",
       "ProductCollectionCreateParams",
       [
         {:groups, true, {:list, {:named, :collection_group}}},
         {:name, true, :string},
         {:brand_id, false, :string},
         {:description, false, :string},
         {:effective_at_on_downgrade, false, {:enum, :effective_at}},
         {:effective_at_on_upgrade, false, {:enum, :effective_at}},
         {:on_payment_failure, false, {:enum, :payment_failure_behavior}},
         {:proration_billing_mode_on_downgrade, false, {:enum, :proration_billing_mode}},
         {:proration_billing_mode_on_upgrade, false, {:enum, :proration_billing_mode}}
       ]},
    product_collections_list:
      {:upstream, "resources/product-collections/product-collections.ts",
       "ProductCollectionListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:archived, false, :boolean},
         {:brand_id, false, :string}
       ]},
    product_collections_update:
      {:upstream, "resources/product-collections/product-collections.ts",
       "ProductCollectionUpdateParams",
       [
         {:brand_id, false, :string},
         {:description, false, :string},
         {:effective_at_on_downgrade, false, {:enum, :effective_at}},
         {:effective_at_on_upgrade, false, {:enum, :effective_at}},
         {:group_order, false, {:list, :string}},
         {:image_id, false, :string},
         {:name, false, :string},
         {:on_payment_failure, false, {:enum, :payment_failure_behavior}},
         {:proration_billing_mode_on_downgrade, false, {:enum, :proration_billing_mode}},
         {:proration_billing_mode_on_upgrade, false, {:enum, :proration_billing_mode}}
       ]},
    product_collections_update_images:
      {:upstream, "resources/product-collections/product-collections.ts",
       "ProductCollectionUpdateImagesParams", [{:force_update, false, :boolean}]},
    product_images_update:
      {:upstream, "resources/products/images.ts", "ImageUpdateParams",
       [{:force_update, false, :boolean}]},
    product_short_links_create:
      {:upstream, "resources/products/short-links.ts", "ShortLinkCreateParams",
       [{:slug, true, :string}, {:static_checkout_params, false, {:named, :string_map}}]},
    product_short_links_list:
      {:upstream, "resources/products/short-links.ts", "ShortLinkListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:product_id, false, :string}
       ]},
    products_create:
      {:upstream, "resources/products/products.ts", "ProductCreateParams",
       [
         {:name, true, :string},
         {:price, true, {:named, :product_price}},
         {:tax_category, true, {:enum, :tax_category}},
         {:addons, false, {:list, :string}},
         {:brand_id, false, :string},
         {:credit_entitlements, false, {:list, {:named, :product_credit_entitlement}}},
         {:description, false, :string},
         {:digital_product_delivery, false, {:named, :product_digital_delivery_create}},
         {:entitlements, false, {:list, {:named, :product_entitlement}}},
         {:license_key_activation_message, false, :string},
         {:license_key_activations_limit, false, :number},
         {:license_key_duration, false, {:named, :license_key_duration}},
         {:license_key_enabled, false, :boolean},
         {:metadata, false, {:named, :flat_metadata}},
         {:pricing_mode, false, {:enum, :pricing_mode}}
       ]},
    products_list:
      {:upstream, "resources/products/products.ts", "ProductListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:archived, false, :boolean},
         {:brand_id, false, :string},
         {:recurring, false, :boolean}
       ]},
    products_update:
      {:upstream, "resources/products/products.ts", "ProductUpdateParams",
       [
         {:addons, false, {:list, :string}},
         {:brand_id, false, :string},
         {:credit_entitlements, false, {:list, {:named, :product_credit_entitlement}}},
         {:description, false, :string},
         {:digital_product_delivery, false, {:named, :product_digital_delivery_update}},
         {:entitlements, false, {:list, {:named, :product_entitlement}}},
         {:image_id, false, :string},
         {:license_key_activation_message, false, :string},
         {:license_key_activations_limit, false, :number},
         {:license_key_duration, false, {:named, :license_key_duration}},
         {:license_key_enabled, false, :boolean},
         {:metadata, false, {:named, :flat_metadata}},
         {:name, false, :string},
         {:price, false, {:named, :product_price}},
         {:pricing_mode, false, {:enum, :pricing_mode}},
         {:tax_category, false, {:enum, :tax_category}}
       ]},
    products_update_files:
      {:upstream, "resources/products/products.ts", "ProductUpdateFilesParams",
       [{:file_name, true, :string}]},
    refunds_create:
      {:upstream, "resources/refunds.ts", "RefundCreateParams",
       [
         {:payment_id, true, :string},
         {:items, false, {:list, {:named, :refund_item}}},
         {:metadata, false, {:named, :flat_metadata}},
         {:reason, false, :string}
       ]},
    refunds_list:
      {:upstream, "resources/refunds.ts", "RefundListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:customer_id, false, :string},
         {:status, false, {:enum, :refund_status}},
         {:subscription_id, false, :string}
       ]},
    subscriptions_change_plan:
      {:upstream, "resources/subscriptions.ts", "SubscriptionChangePlanParams",
       [
         {:product_id, true, :string},
         {:proration_billing_mode, true, {:enum, :proration_billing_mode}},
         {:quantity, true, :number},
         {:adaptive_currency_fees_inclusive, false, :boolean},
         {:addons, false, {:list, {:named, :attach_addon}}},
         {:discount_code, false, :string},
         {:discount_codes, false, {:list, :string}},
         {:effective_at, false, {:enum, :effective_at}},
         {:metadata, false, {:named, :flat_metadata}},
         {:on_payment_failure, false, {:enum, :payment_failure_behavior}}
       ]},
    subscriptions_charge:
      {:upstream, "resources/subscriptions.ts", "SubscriptionChargeParams",
       [
         {:product_price, true, :number},
         {:adaptive_currency_fees_inclusive, false, :boolean},
         {:customer_balance_config, false, {:named, :customer_balance_config}},
         {:metadata, false, {:named, :flat_metadata}},
         {:product_currency, false, {:enum, :currency}},
         {:product_description, false, :string}
       ]},
    subscriptions_create:
      {:upstream, "resources/subscriptions.ts", "SubscriptionCreateParams",
       [
         {:billing, true, {:named, :billing_address}},
         {:customer, true, {:named, :customer_request}},
         {:product_id, true, :string},
         {:quantity, true, :number},
         {:addons, false, {:list, {:named, :attach_addon}}},
         {:allowed_payment_method_types, false, {:list, {:enum, :payment_method_type}}},
         {:billing_currency, false, {:enum, :currency}},
         {:customer_business_name, false, :string},
         {:discount_code, false, :string},
         {:discount_codes, false, {:list, :string}},
         {:force_3ds, false, :boolean},
         {:mandate_min_amount_inr_paise, false, :number},
         {:metadata, false, {:named, :flat_metadata}},
         {:on_demand, false, {:named, :on_demand_subscription}},
         {:one_time_product_cart, false, {:list, {:named, :one_time_product_cart_item}}},
         {:payment_link, false, :boolean},
         {:payment_method_id, false, :string},
         {:redirect_immediately, false, :boolean},
         {:require_phone_number, false, :boolean},
         {:return_url, false, :string},
         {:short_link, false, :boolean},
         {:show_saved_payment_methods, false, :boolean},
         {:tax_id, false, :string},
         {:trial_period_days, false, :number}
       ]},
    subscriptions_list:
      {:upstream, "resources/subscriptions.ts", "SubscriptionListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:brand_id, false, :string},
         {:cancel_at_next_billing_date, false, :boolean},
         {:created_at_gte, false, :string},
         {:created_at_lte, false, :string},
         {:customer_id, false, :string},
         {:product_id, false, :string},
         {:status, false, {:enum, :subscription_status}}
       ]},
    subscriptions_preview_change_plan:
      {:upstream, "resources/subscriptions.ts", "SubscriptionPreviewChangePlanParams",
       [
         {:product_id, true, :string},
         {:proration_billing_mode, true, {:enum, :proration_billing_mode}},
         {:quantity, true, :number},
         {:adaptive_currency_fees_inclusive, false, :boolean},
         {:addons, false, {:list, {:named, :attach_addon}}},
         {:discount_code, false, :string},
         {:discount_codes, false, {:list, :string}},
         {:effective_at, false, {:enum, :effective_at}},
         {:metadata, false, {:named, :flat_metadata}},
         {:on_payment_failure, false, {:enum, :payment_failure_behavior}}
       ]},
    subscriptions_update:
      {:upstream, "resources/subscriptions.ts", "SubscriptionUpdateParams",
       [
         {:billing, false, {:named, :billing_address}},
         {:cancel_at_next_billing_date, false, :boolean},
         {:cancel_reason, false, :string},
         {:cancellation_comment, false, :string},
         {:cancellation_feedback, false, {:enum, :cancellation_feedback}},
         {:credit_entitlement_cart, false, {:list, {:named, :subscription_credit_entitlement}}},
         {:customer_business_name, false, :string},
         {:customer_name, false, :string},
         {:disable_on_demand, false, {:named, :disable_on_demand}},
         {:metadata, false, {:named, :flat_metadata}},
         {:next_billing_date, false, :string},
         {:pause, false, :boolean},
         {:status, false, {:enum, :subscription_status}},
         {:subscription_period_count, false, :number},
         {:subscription_period_interval, false, {:enum, :time_interval}},
         {:tax_id, false, :string}
       ]},
    subscriptions_update_payment_method:
      {:upstream, "resources/subscriptions.ts", "SubscriptionUpdatePaymentMethodParams",
       [{:payment_method, true, {:named, :subscription_payment_method}}]},
    subscriptions_usage_history:
      {:upstream, "resources/subscriptions.ts", "SubscriptionRetrieveUsageHistoryParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:end_date, false, :string},
         {:meter_id, false, :string},
         {:start_date, false, :string}
       ]},
    usage_events_ingest:
      {:upstream, "resources/usage-events.ts", "UsageEventIngestParams",
       [{:events, true, {:list, {:named, :usage_event_input}}}]},
    usage_events_list:
      {:upstream, "resources/usage-events.ts", "UsageEventListParams",
       [
         {:page_number, false, :number},
         {:page_size, false, :number},
         {:customer_id, false, :string},
         {:end, false, :string},
         {:event_name, false, :string},
         {:meter_id, false, :string},
         {:start, false, :string}
       ]},
    webhook_endpoints_create:
      {:upstream, "resources/webhooks/webhooks.ts", "WebhookCreateParams",
       [
         {:url, true, :string},
         {:description, false, :string},
         {:disabled, false, :boolean},
         {:filter_types, false, {:list, {:enum, :webhook_event_type}}},
         {:headers, false, {:named, :string_map}},
         {:idempotency_key, false, :string},
         {:metadata, false, {:named, :string_map}},
         {:rate_limit, false, :number}
       ]},
    webhook_endpoints_list:
      {:upstream, "resources/webhooks/webhooks.ts", "WebhookListParams",
       [{:iterator, false, :string}, {:limit, false, :number}]},
    webhook_endpoints_update:
      {:upstream, "resources/webhooks/webhooks.ts", "WebhookUpdateParams",
       [
         {:description, false, :string},
         {:disabled, false, :boolean},
         {:filter_types, false, {:list, {:enum, :webhook_event_type}}},
         {:metadata, false, {:named, :string_map}},
         {:rate_limit, false, :number},
         {:url, false, :string}
       ]},
    webhook_headers_update:
      {:upstream, "resources/webhooks/headers.ts", "HeaderUpdateParams",
       [{:headers, true, {:named, :string_map}}]},
    discount_customers_list:
      {:schema_first, [{:page_number, false, :number}, {:page_size, false, :number}]},
    discount_customers_attach: {:schema_first, [{:customer_ids, true, {:list, :string}}]}
  }

  @doc false
  @spec schema_ids() :: [atom()]
  def schema_ids, do: Map.keys(@schemas)

  @doc false
  @spec source(atom()) ::
          {:upstream, String.t(), String.t()} | :schema_first | nil
  def source(id) do
    case Map.get(@schemas, id) do
      {:upstream, path, interface, _fields} -> {:upstream, path, interface}
      {:schema_first, _fields} -> :schema_first
      nil -> nil
    end
  end

  @doc false
  def params_ast(%DodoPayments.Operation{} = operation) do
    fields = parameter_fields(operation)

    exact =
      fields
      |> Enum.map_join(", ", fn {name, required?, descriptor} ->
        qualifier = if required?, do: "required", else: "optional"
        "#{qualifier}(:#{name}) => #{descriptor_source(descriptor)}"
      end)
      |> then(fn entries ->
        string_keys =
          "optional(String.t()) => DodoPayments.RequestTypes.input_value()"

        "%{" <> Enum.join(Enum.reject([entries, string_keys], &(&1 == "")), ", ") <> "}"
      end)

    Code.string_to_quoted!(exact <> " | DodoPayments.RequestTypes.compatibility_params()")
  end

  @doc false
  @spec encode(DodoPayments.Operation.t(), map()) ::
          {:ok, map()} | {:error, DodoPayments.ValidationError.t()}
  def encode(%DodoPayments.Operation{} = operation, params) when is_map(params) do
    case Map.fetch(@schemas, operation.id) do
      {:ok, _schema} -> encode_map(params, parameter_fields(operation), operation.id, [])
      :error -> {:ok, params}
    end
  end

  @doc false
  @spec parameter_fields(DodoPayments.Operation.t()) ::
          [{atom(), boolean(), term()}]
  def parameter_fields(%DodoPayments.Operation{} = operation) do
    operation.id
    |> schema_fields!()
    |> Enum.reject(fn {name, _required?, _descriptor} ->
      name in operation.path_params
    end)
  end

  @doc false
  @spec generic_nested_residuals() :: [{atom(), atom(), :object | {:list, :object}}]
  def generic_nested_residuals do
    for id <- schema_ids(),
        {field, _required?, descriptor} <- parameter_fields(DodoPayments.Operation.fetch!(id)),
        descriptor in [:object, {:list, :object}] do
      {id, field, descriptor}
    end
  end

  @doc false
  def type_doc(%DodoPayments.Operation{} = operation) do
    source =
      case source(operation.id) do
        {:upstream, path, interface} ->
          "Source: locked upstream `#{path}` declaration `#{interface}`."

        :schema_first ->
          "Source: Dodo OpenAPI schema (the upstream TypeScript endpoint is schema-first)."
      end

    "Parameters for `#{operation.id}`. Exact fields use atom keys; string-keyed " <>
      "and mixed-key maps remain supported. " <> source
  end

  defp schema_fields!(id) do
    case Map.fetch!(@schemas, id) do
      {:upstream, _path, _interface, fields} -> fields
      {:schema_first, fields} -> fields
    end
  end

  defp descriptor_source(:string), do: "String.t()"
  defp descriptor_source(:number), do: "number()"
  defp descriptor_source(:boolean), do: "boolean()"
  defp descriptor_source(:object), do: "DodoPayments.RequestTypes.input_object()"

  defp descriptor_source({:enum, name}) do
    "DodoPayments.Enums.#{name}()"
  end

  defp descriptor_source({:named, name}) do
    "DodoPayments.RequestTypes.#{name}()"
  end

  defp descriptor_source({:list, descriptor}) do
    "[#{descriptor_source(descriptor)}]"
  end

  defp encode_map(map, fields, operation, path) do
    descriptors = Map.new(fields, fn {name, _required?, descriptor} -> {name, descriptor} end)

    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, encoded} ->
      descriptor = Map.get(descriptors, field_atom(key, descriptors))

      case encode_value(value, descriptor, operation, path ++ [key]) do
        {:ok, encoded_value} -> {:cont, {:ok, Map.put(encoded, key, encoded_value)}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp encode_value(value, {:enum, enum}, operation, path) when is_atom(value) do
    case DodoPayments.Enums.dump(enum, value) do
      {:ok, wire} ->
        {:ok, wire}

      {:error, _reason} ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           field: List.first(path),
           reason: {:unknown_enum_atom, enum, value, path}
         )}
    end
  end

  defp encode_value(%DodoPayments.UnknownEnum{} = value, {:enum, enum}, operation, path) do
    case DodoPayments.Enums.dump(enum, value) do
      {:ok, wire} ->
        {:ok, wire}

      {:error, _reason} ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           field: List.first(path),
           reason: {:wrong_unknown_enum_domain, enum, value.enum, path}
         )}
    end
  end

  defp encode_value(values, {:list, descriptor}, operation, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, encoded} ->
      case encode_value(value, descriptor, operation, path ++ [index]) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | encoded]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      {:error, _error} = error -> error
    end
  end

  defp encode_value(map, {:named, name}, operation, path) when is_map(map) do
    encode_map(map, named_fields(name), operation, path)
  end

  defp encode_value(value, _descriptor, _operation, _path), do: {:ok, value}

  defp field_atom(key, descriptors) when is_atom(key),
    do: if(Map.has_key?(descriptors, key), do: key)

  defp field_atom(key, descriptors) when is_binary(key) do
    Enum.find(Map.keys(descriptors), &(Atom.to_string(&1) == key))
  end

  defp field_atom(_key, _descriptors), do: nil

  defp named_fields(:billing_address),
    do: [{:country, true, {:enum, :country_code}}]

  defp named_fields(:checkout_product_item),
    do: [{:addons, false, {:list, {:named, :attach_addon}}}]

  defp named_fields(:checkout_session_flags),
    do: [
      {:allow_currency_selection, false, :boolean},
      {:allow_customer_editing_business_name, false, :boolean},
      {:allow_customer_editing_city, false, :boolean},
      {:allow_customer_editing_country, false, :boolean},
      {:allow_customer_editing_email, false, :boolean},
      {:allow_customer_editing_name, false, :boolean},
      {:allow_customer_editing_state, false, :boolean},
      {:allow_customer_editing_street, false, :boolean},
      {:allow_customer_editing_tax_id, false, :boolean},
      {:allow_customer_editing_zipcode, false, :boolean},
      {:allow_discount_code, false, :boolean},
      {:allow_editing_addons, false, :boolean},
      {:allow_phone_number_collection, false, :boolean},
      {:allow_tax_id, false, :boolean},
      {:always_create_new_customer, false, :boolean},
      {:redirect_immediately, false, :boolean},
      {:require_phone_number, false, :boolean},
      {:single_page, false, :boolean}
    ]

  defp named_fields(:checkout_custom_field),
    do: [{:field_type, true, {:enum, :custom_field_type}}]

  defp named_fields(:checkout_customization),
    do: [
      {:theme, false, {:enum, :checkout_theme}},
      {:theme_config, false, {:named, :checkout_theme_config}}
    ]

  defp named_fields(:checkout_theme_config),
    do: [
      {:dark, false, {:named, :checkout_theme_mode}},
      {:font_size, false, {:enum, :font_size}},
      {:font_weight, false, {:enum, :font_weight}},
      {:light, false, {:named, :checkout_theme_mode}}
    ]

  defp named_fields(:checkout_subscription_data),
    do: [{:on_demand, false, {:named, :on_demand_subscription}}]

  defp named_fields(:discount_currency_option),
    do: [{:currency, true, {:enum, :currency}}]

  defp named_fields(:entitlement_integration_config),
    do: [
      {:feature_type, false, {:enum, :feature_type}},
      {:permission, false, {:enum, :github_permission}},
      {:duration_interval, false, {:enum, :time_interval}},
      {:fulfillment_mode, false, {:enum, :license_fulfillment_mode}}
    ]

  defp named_fields(:license_key_duration),
    do: [{:interval, true, {:enum, :time_interval}}]

  defp named_fields(:meter_aggregation),
    do: [{:type, true, {:enum, :meter_aggregation}}]

  defp named_fields(:meter_filter),
    do: [
      {:clauses, true, {:list, {:named, :meter_filter_clause}}},
      {:conjunction, true, {:enum, :meter_conjunction}}
    ]

  defp named_fields(:meter_filter_clause),
    do: [
      {:clauses, false, {:list, {:named, :meter_filter_clause}}},
      {:conjunction, false, {:enum, :meter_conjunction}},
      {:operator, false, {:enum, :meter_filter_operator}}
    ]

  defp named_fields(:on_demand_subscription),
    do: [{:product_currency, false, {:enum, :currency}}]

  defp named_fields(:product_credit_entitlement),
    do: [
      {:currency, false, {:enum, :currency}},
      {:overage_behavior, false, {:enum, :cbb_overage_behavior}},
      {:proration_behavior, false, {:enum, :cbb_proration_behavior}},
      {:rollover_timeframe_interval, false, {:enum, :time_interval}}
    ]

  defp named_fields(:product_price),
    do: [
      {:currency, true, {:enum, :currency}},
      {:payment_frequency_interval, false, {:enum, :time_interval}},
      {:subscription_period_interval, false, {:enum, :time_interval}},
      {:type, true, {:enum, :price_type}}
    ]

  defp named_fields(:subscription_credit_entitlement),
    do: [{:rollover_timeframe_interval, false, {:enum, :time_interval}}]

  defp named_fields(:subscription_payment_method),
    do: [
      {:type, true, {:enum, :subscription_payment_method_selection}},
      {:allowed_payment_method_types, false, {:list, {:enum, :payment_method_type}}}
    ]

  defp named_fields(_name), do: []
end
