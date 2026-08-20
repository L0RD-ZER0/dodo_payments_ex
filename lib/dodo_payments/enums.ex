defmodule DodoPayments.UnknownEnum do
  @moduledoc """
  A lossless value returned when Dodo introduces an enum member that this SDK
  does not know yet.

  Known values decode to atoms. Unknown values are never converted to atoms;
  their exact wire value is retained here until the SDK is updated.
  """

  @enforce_keys [:enum, :value]
  defstruct [:enum, :value]

  @type t :: %__MODULE__{enum: atom(), value: String.t()}
end

defimpl String.Chars, for: DodoPayments.UnknownEnum do
  def to_string(%{value: value}), do: value
end

defmodule DodoPayments.EnumRuntime do
  @moduledoc false

  def values(atom_to_wire, enum), do: atom_to_wire |> Map.fetch!(enum) |> Map.keys()

  def dump(_atom_to_wire, wire_to_atom, enum, value) when is_binary(value) do
    if Map.has_key?(wire_to_atom, enum), do: {:ok, value}, else: {:error, :unknown_enum}
  end

  def dump(atom_to_wire, _wire_to_atom, enum, value) when is_atom(value) do
    with {:ok, values} <- Map.fetch(atom_to_wire, enum),
         {:ok, wire} <- Map.fetch(values, value) do
      {:ok, wire}
    else
      :error -> {:error, :unknown_value}
    end
  end

  def dump(_atom_to_wire, _wire_to_atom, _enum, _value), do: {:error, :unknown_value}

  def dump!(atom_to_wire, wire_to_atom, enum, value) do
    case dump(atom_to_wire, wire_to_atom, enum, value) do
      {:ok, wire} ->
        wire

      {:error, reason} ->
        raise ArgumentError,
              "invalid #{inspect(enum)} enum value #{inspect(value)}: #{inspect(reason)}"
    end
  end

  def load(_wire_to_atom, _enum, nil), do: nil

  def load(wire_to_atom, enum, value) when is_binary(value) do
    case Map.fetch(wire_to_atom, enum) do
      {:ok, values} -> load_known(values, enum, value)
      :error -> value
    end
  end

  def load(_wire_to_atom, _enum, value), do: value

  defp load_known(values, enum, value) do
    case Map.fetch(values, value) do
      {:ok, atom} -> atom
      :error -> %DodoPayments.UnknownEnum{enum: enum, value: value}
    end
  end
end

defmodule DodoPayments.EnumBuilder do
  @moduledoc false

  defmacro defenum(name, wire_values) do
    name = Macro.expand(name, __CALLER__)
    wire_values = Macro.expand(wire_values, __CALLER__)

    pairs =
      Enum.map(wire_values, fn
        {wire, atom} when is_binary(wire) and is_atom(atom) -> {wire, atom}
        wire when is_binary(wire) -> {wire, enum_atom(wire)}
      end)

    atoms = Enum.map(pairs, &elem(&1, 1))

    if length(atoms) != length(Enum.uniq(atoms)) do
      raise ArgumentError, "enum #{name} contains colliding Elixir atom names"
    end

    type_ast = Enum.reduce(atoms, fn atom, union -> {:|, [], [atom, union]} end)
    decoded_name = :"decoded_#{name}"

    quote do
      @type unquote(name)() :: unquote(type_ast)
      @type unquote(decoded_name)() ::
              unquote(name)() | DodoPayments.UnknownEnum.t()

      @dodo_enum_definitions {unquote(name), unquote(Macro.escape(pairs))}
    end
  end

  defmacro __before_compile__(env) do
    definitions = definitions(env.module)
    atom_to_wire = atom_to_wire(definitions)
    wire_to_atom = wire_to_atom(definitions)
    unambiguous_atom_to_wire = unambiguous_atom_to_wire(definitions)

    quote do
      @enum_atom_to_wire unquote(Macro.escape(atom_to_wire))
      @enum_wire_to_atom unquote(Macro.escape(wire_to_atom))
      @unambiguous_atom_to_wire unquote(Macro.escape(unambiguous_atom_to_wire))

      @doc "Returns every enum domain known to the source-locked SDK schema."
      @spec names() :: [atom()]
      def names, do: Map.keys(@enum_wire_to_atom)

      @doc "Returns the canonical Elixir atoms for an enum domain."
      @spec values(atom()) :: [atom()]
      def values(enum), do: DodoPayments.EnumRuntime.values(@enum_atom_to_wire, enum)

      @doc false
      @spec dump_unambiguous_atom(atom()) :: {:ok, String.t()} | :error
      def dump_unambiguous_atom(value) when is_atom(value) do
        Map.fetch(@unambiguous_atom_to_wire, value)
      end

      @doc "Converts a known atom, compatible string, or unknown wrapper to its wire string."
      @spec dump(atom(), atom() | String.t() | DodoPayments.UnknownEnum.t()) ::
              {:ok, String.t()} | {:error, :unknown_enum | :unknown_value}
      def dump(enum, %DodoPayments.UnknownEnum{enum: enum, value: value}), do: {:ok, value}

      def dump(enum, value),
        do: DodoPayments.EnumRuntime.dump(@enum_atom_to_wire, @enum_wire_to_atom, enum, value)

      @doc "Converts an enum value to its wire string or raises for a mismatched atom/domain."
      @spec dump!(atom(), atom() | String.t() | DodoPayments.UnknownEnum.t()) :: String.t()
      def dump!(enum, value),
        do:
          DodoPayments.EnumRuntime.dump!(
            @enum_atom_to_wire,
            @enum_wire_to_atom,
            enum,
            value
          )

      @doc "Decodes a wire string without ever creating an atom dynamically."
      @spec load(atom(), term()) :: term()
      def load(enum, value), do: DodoPayments.EnumRuntime.load(@enum_wire_to_atom, enum, value)
    end
  end

  defp enum_atom(wire) do
    wire
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.trim("_")
    |> String.downcase()
    |> String.to_atom()
  end

  defp definitions(module) do
    module
    |> Module.get_attribute(:dodo_enum_definitions)
    |> Enum.reverse()
    |> Map.new()
  end

  defp atom_to_wire(definitions) do
    Map.new(definitions, fn {enum, pairs} ->
      {enum, Map.new(pairs, fn {wire, atom} -> {atom, wire} end)}
    end)
  end

  defp wire_to_atom(definitions) do
    Map.new(definitions, fn {enum, pairs} -> {enum, Map.new(pairs)} end)
  end

  defp unambiguous_atom_to_wire(definitions) do
    definitions
    |> Enum.flat_map(fn {_enum, pairs} -> pairs end)
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.reduce(%{}, &put_unambiguous/2)
  end

  defp put_unambiguous({atom, wires}, encoded) do
    case Enum.uniq(wires) do
      [wire] -> Map.put(encoded, atom, wire)
      _ambiguous -> encoded
    end
  end
end

defmodule DodoPayments.Enums do
  @moduledoc """
  Source-locked Dodo enum types and their safe JSON-boundary conversions.

  Request APIs use the atom types. Decoded responses use the corresponding
  `decoded_*` type, which adds `%DodoPayments.UnknownEnum{}` for forward
  compatibility. No atom is ever created from server or caller input.
  """

  import DodoPayments.EnumBuilder

  Module.register_attribute(__MODULE__, :dodo_enum_definitions, accumulate: true)
  @before_compile DodoPayments.EnumBuilder

  defenum(:country_code, ~w(
    AF AX AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BY BE BZ BJ BM BT BO BQ BA BW BV BR IO BN BG BF BI KH CM CA CV KY CF TD CL CN CX CC CO KM CG CD CK CR CI HR CU CW CY CZ DK DJ DM DO EC EG SV GQ ER EE ET FK FO FJ FI FR GF PF TF GA GM GE DE GH GI GR GL GD GP GU GT GG GN GW GY HT HM VA HN HK HU IS IN ID IR IQ IE IM IL IT JM JP JE JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU MO MK MG MW MY MV ML MT MH MQ MR MU YT MX FM MD MC MN ME MS MA MZ MM NA NR NP NL NC NZ NI NE NG NU NF MP NO OM PK PW PS PA PG PY PE PH PN PL PT PR QA RE RO RU RW BL SH KN LC MF PM VC WS SM ST SA SN RS SC SL SG SX SK SI SB SO ZA GS SS ES LK SD SR SJ SZ SE CH SY TW TJ TZ TH TL TG TK TO TT TN TR TM TC TV UG UA AE GB UM US UY UZ VU VE VN VG VI WF EH YE ZM ZW
  ))

  defenum(:currency, ~w(
    AED ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BWP BYN BZD CAD CHF CLP CNY COP CRC CUP CVE CZK DJF DKK DOP DZD EGP ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HRK HTG HUF IDR ILS INR IQD JMD JOD JPY KES KGS KHR KMF KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SEK SGD SHP SLE SLL SOS SRD SSP STN SVC SZL THB TND TOP TRY TTD TWD TZS UAH UGX USD UYU UZS VES VND VUV WST XAF XCD XOF XPF YER ZAR ZMW
  ))

  defenum(:tax_category, ~w(digital_products saas e_book edtech live_tutoring))
  defenum(:pricing_mode, ~w(by_currency by_country))

  defenum(:intent_status, ~w(
    succeeded failed cancelled processing requires_customer_action requires_merchant_action
    requires_payment_method requires_confirmation requires_capture partially_captured
    partially_captured_and_capturable
  ))

  defenum(:payment_method_type, ~w(
    ach affirm afterpay_clearpay alfamart ali_pay ali_pay_hk alma amazon_pay apple_pay atome
    bacs bancontact_card becs benefit bizum blik boleto bca_bank_transfer bni_va bri_va
    card_redirect cimb_va classic credit crypto_currency cashapp dana danamon_va debit
    duit_now efecty eft eps fps evoucher giropay givex google_pay go_pay gcash ideal interac
    indomaret klarna kakao_pay local_bank_redirect mandiri_va knet mb_way mobile_pay momo
    momo_atm multibanco online_banking_thailand online_banking_czech_republic
    online_banking_finland online_banking_fpx online_banking_poland online_banking_slovakia
    oxxo pago_efectivo permata_bank_transfer open_banking_uk pay_bright paypal paze pix
    pay_safe_card przelewy24 prompt_pay pse red_compra red_pagos samsung_pay sepa
    sepa_bank_transfer sofort swish touch_n_go trustly twint upi_collect upi_intent vipps
    viet_qr venmo walley we_chat_pay seven_eleven lawson mini_stop family_mart seicomart
    pay_easy local_bank_transfer mifinity open_banking_pis direct_carrier_billing
    instant_bank_transfer billie zip revolut_pay naver_pay payco satispay
  ))

  defenum(:payment_method_family, ~w(
    card card_redirect pay_later wallet bank_redirect bank_transfer crypto bank_debit reward
    real_time_payment upi voucher gift_card open_banking mobile_payment
  ))

  defenum(:payment_refund_status, ~w(partial full))
  defenum(:refund_status, ~w(succeeded failed pending review))
  defenum(:payment_provider, ~w(stripe adyen dodo))
  defenum(:dispute_stage, ~w(pre_dispute dispute pre_arbitration))

  defenum(:dispute_status, ~w(
    dispute_opened dispute_expired dispute_accepted dispute_cancelled dispute_challenged
    dispute_won dispute_lost
  ))

  defenum(:subscription_status, ~w(pending active on_hold paused cancelled failed expired))
  defenum(:time_interval, ~w(Day Week Month Year))

  defenum(:cancellation_feedback, ~w(
    too_expensive missing_features switched_service unused customer_service low_quality
    too_complex other
  ))

  defenum(:license_key_source, ~w(auto import manual))
  defenum(:license_key_status, ~w(active expired disabled))

  defenum(:entitlement_integration_type, ~w(
    discord telegram github figma framer notion digital_files license_key feature_flag
  ))

  defenum(:entitlement_grant_status, ~w(Pending Delivered Failed Revoked))
  defenum(:customer_entitlement_grant_status, ~w(pending delivered failed revoked))
  defenum(:discount_type, ~w(flat percentage))
  defenum(:customer_eligibility, ~w(any first_time existing specific))
  defenum(:credit_grant_status, ~w(active expired depleted))
  defenum(:ledger_entry_type, ~w(credit debit))

  defenum(:cbb_overage_behavior, ~w(
    forgive_at_reset invoice_at_billing carry_deficit carry_deficit_auto_repay
  ))

  defenum(:cbb_proration_behavior, ~w(prorate no_prorate))
  defenum(:meter_conjunction, ~w(and or))

  defenum(:meter_filter_operator, ~w(
    equals not_equals greater_than greater_than_or_equals less_than less_than_or_equals
    contains does_not_contain
  ))

  defenum(:meter_aggregation, ~w(count sum max last))
  defenum(:checkout_theme, ~w(dark light system))
  defenum(:custom_field_type, ~w(text number email url date dropdown boolean))
  defenum(:font_size, ~w(xs sm md lg xl 2xl))
  defenum(:font_weight, ~w(normal medium bold extraBold))
  defenum(:price_type, ~w(one_time_price recurring_price usage_based_price))
  defenum(:feature_type, ~w(boolean))
  defenum(:github_permission, ~w(pull push admin maintain triage))
  defenum(:license_fulfillment_mode, ~w(auto manual))
  defenum(:credit_grant_source_type, ~w(subscription one_time addon api rollover))

  defenum(:credit_transaction_type, ~w(
    credit_added credit_deducted credit_expired credit_rolled_over rollover_forfeited
    overage_charged overage_reset auto_top_up manual_adjustment refund
  ))

  defenum(:brand_verification_status, ~w(Success Fail Review Hold))
  defenum(:abandonment_reason, ~w(payment_failed checkout_incomplete))
  defenum(:abandoned_checkout_status, ~w(abandoned recovering recovered exhausted opted_out))
  defenum(:dunning_status, ~w(recovering recovered exhausted))
  defenum(:dunning_trigger_state, ~w(on_hold cancelled))
  defenum(:payout_status, ~w(not_initiated in_progress on_hold failed success))

  defenum(:effective_at, ~w(immediately next_billing_date))
  defenum(:payment_failure_behavior, ~w(prevent_change apply_change))

  defenum(:proration_billing_mode, ~w(
    prorated_immediately full_immediately difference_immediately do_not_bill
  ))

  defenum(:subscription_payment_method_selection, ~w(new existing))

  defenum(:balance_event_type, ~w(
    payment refund refund_reversal dispute dispute_reversal tax tax_reversal payment_fees
    refund_fees refund_fees_reversal dispute_fees payout payout_fees payout_reversal
    payout_fees_reversal dodo_credits adjustment currency_conversion
    abandoned_cart_recovery_fee dunning_fees payment_retry_fee byop_fee
  ))

  defenum(:wallet_event_type, ~w(
    payment payment_reversal refund refund_reversal dispute dispute_reversal merchant_adjustment
  ))

  defenum(:webhook_event_type, ~w(
    payment.succeeded payment.failed payment.processing payment.cancelled refund.succeeded
    refund.failed dispute.opened dispute.expired dispute.accepted dispute.cancelled
    dispute.challenged dispute.won dispute.lost subscription.active subscription.renewed
    subscription.on_hold subscription.paused subscription.unpaused subscription.cancelled subscription.failed
    subscription.expired subscription.plan_changed subscription.updated
    subscription.update_payment_method license_key.created payout.created payout.on_hold
    payout.in_progress payout.failed payout.success credit.added credit.deducted credit.expired
    credit.rolled_over credit.rollover_forfeited credit.overage_charged credit.overage_reset
    credit.manual_adjustment credit.balance_low abandoned_checkout.detected
    abandoned_checkout.recovered dunning.started dunning.recovered entitlement_grant.created
    entitlement_grant.delivered entitlement_grant.failed entitlement_grant.revoked
  ))
end
