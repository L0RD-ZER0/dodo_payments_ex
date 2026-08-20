defmodule DodoStore.Smoke.PaymentMethodRegistry do
  @moduledoc """
  Source-locked payment-method inventory for smoke scenario planning.

  Dodo's enum inventory proves that a wire value exists; it does not prove
  that a merchant, country, currency, device, or test account can offer or
  complete that method. Entries therefore default to `:enum_only`, and family
  relationships are explicitly marked as inferred until an authoritative
  source confirms them.
  """

  alias DodoStore.Smoke.Options

  defmodule Entry do
    @moduledoc "A payment-method smoke-test registry entry."

    @enforce_keys [
      :type,
      :family,
      :family_source,
      :support_expectation,
      :interaction,
      :completion_driver,
      :settlement,
      :flows,
      :source_lock
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            type: DodoPayments.Enums.payment_method_type(),
            family: DodoPayments.Enums.payment_method_family(),
            family_source: :inferred,
            support_expectation:
              :documented_supported
              | :merchant_gated
              | :regional
              | :device_or_manual_required
              | :enum_only,
            interaction: :automated | :manual | :unknown,
            completion_driver: atom() | nil,
            settlement: :synchronous | :asynchronous | :unknown,
            flows: [atom()],
            source_lock: map()
          }
  end

  @source_lock %{
    source: "npm:dodopayments",
    version: "2.47.0",
    tarball_sha256: "030a4fc116f289199dd925572707d5d7407a21d666856d398aa8b1eb5a3c07e8",
    audited_on: ~D[2026-08-18]
  }

  # Dodo source-locks the two enum domains independently. Until the upstream
  # schema exposes their relationship, this table is an audited inference and
  # must not be treated as evidence that a method will be offered.
  @family_groups %{
    card: ~w(classic credit debit red_compra)a,
    card_redirect: ~w(bancontact_card card_redirect)a,
    pay_later: ~w(affirm afterpay_clearpay alma atome klarna pay_bright walley billie zip)a,
    wallet:
      ~w(ali_pay ali_pay_hk amazon_pay apple_pay cashapp dana google_pay go_pay gcash kakao_pay mobile_pay momo paypal paze samsung_pay touch_n_go venmo we_chat_pay mifinity revolut_pay naver_pay payco satispay)a,
    bank_redirect:
      ~w(benefit bizum blik duit_now eps giropay ideal interac local_bank_redirect knet mb_way multibanco online_banking_thailand online_banking_czech_republic online_banking_finland online_banking_fpx online_banking_poland online_banking_slovakia przelewy24 pse sofort trustly twint vipps)a,
    bank_transfer:
      ~w(bca_bank_transfer bni_va bri_va cimb_va danamon_va eft mandiri_va permata_bank_transfer sepa_bank_transfer local_bank_transfer instant_bank_transfer)a,
    crypto: ~w(crypto_currency)a,
    bank_debit: ~w(ach bacs becs sepa)a,
    reward: ~w(evoucher)a,
    real_time_payment: ~w(fps pix prompt_pay swish viet_qr)a,
    upi: ~w(upi_collect upi_intent)a,
    voucher:
      ~w(alfamart boleto efecty indomaret oxxo pago_efectivo red_pagos seven_eleven lawson mini_stop family_mart seicomart pay_easy)a,
    gift_card: ~w(givex pay_safe_card)a,
    open_banking: ~w(open_banking_uk open_banking_pis)a,
    mobile_payment: ~w(momo_atm direct_carrier_billing)a
  }

  @source_types DodoPayments.Enums.values(:payment_method_type) |> Enum.sort()
  @source_families DodoPayments.Enums.values(:payment_method_family) |> Enum.sort()
  @grouped_types @family_groups |> Map.values() |> List.flatten()

  if length(@grouped_types) != length(Enum.uniq(@grouped_types)) do
    raise "payment-method registry maps at least one type more than once"
  end

  if Enum.sort(@grouped_types) != @source_types do
    missing = @source_types -- @grouped_types
    unknown = @grouped_types -- @source_types

    raise "payment-method registry is not source-lock exhaustive; " <>
            "missing=#{inspect(missing)} unknown=#{inspect(unknown)}"
  end

  if @family_groups |> Map.keys() |> Enum.sort() != @source_families do
    raise "payment-method registry does not cover every source-locked family"
  end

  @type_to_family for {family, types} <- @family_groups,
                      type <- types,
                      into: %{},
                      do: {type, family}

  @concrete_features [
    :core,
    :payment_method_types,
    :payment_method_families,
    :refunds,
    :disputes,
    :resilience
  ]

  @doc "Returns the immutable upstream source-lock identity used by this registry."
  @spec source_lock() :: map()
  def source_lock, do: @source_lock

  @doc "Returns every registry entry in stable wire-name order."
  @spec all() :: [Entry.t()]
  def all, do: Enum.map(@source_types, &entry/1)

  @doc "Returns every source-locked payment-method type in stable order."
  @spec types() :: [DodoPayments.Enums.payment_method_type()]
  def types, do: @source_types

  @doc "Returns every source-locked payment-method family in stable order."
  @spec families() :: [DodoPayments.Enums.payment_method_family()]
  def families, do: @source_families

  @doc "Fetches one registry entry."
  @spec fetch(DodoPayments.Enums.payment_method_type()) :: {:ok, Entry.t()} | :error
  def fetch(type) when is_atom(type) do
    if Map.has_key?(@type_to_family, type), do: {:ok, entry(type)}, else: :error
  end

  @doc "Fetches one registry entry or raises for an unknown type."
  @spec fetch!(DodoPayments.Enums.payment_method_type()) :: Entry.t()
  def fetch!(type) do
    case fetch(type) do
      {:ok, entry} -> entry
      :error -> raise ArgumentError, "unknown payment-method type #{inspect(type)}"
    end
  end

  @doc "Expands parsed selectors into stable, explicit smoke scenario descriptors."
  @spec expand(Options.t()) :: [map()]
  def expand(%Options{} = options) do
    options.features
    |> concrete_features()
    |> Enum.flat_map(&feature_scenarios(&1, options))
    |> Enum.flat_map(&outcome_scenarios(&1, options))
  end

  defp entry(type) do
    metadata = method_metadata(type)

    struct!(Entry,
      type: type,
      family: Map.fetch!(@type_to_family, type),
      family_source: :inferred,
      support_expectation: metadata.support_expectation,
      interaction: metadata.interaction,
      completion_driver: metadata.completion_driver,
      settlement: metadata.settlement,
      flows: metadata.flows,
      source_lock: @source_lock
    )
  end

  defp method_metadata(:credit) do
    %{
      support_expectation: :documented_supported,
      interaction: :automated,
      completion_driver: :test_card,
      settlement: :synchronous,
      flows: [:one_time, :subscription, :renewal]
    }
  end

  defp method_metadata(type) when type in [:upi_collect, :upi_intent] do
    %{
      support_expectation: :documented_supported,
      interaction: :automated,
      completion_driver: :test_upi_vpa,
      settlement: :synchronous,
      flows: [:one_time]
    }
  end

  defp method_metadata(type)
       when type in [
              :affirm,
              :afterpay_clearpay,
              :alma,
              :atome,
              :billie,
              :klarna,
              :pay_bright,
              :walley,
              :zip
            ] do
    %{
      support_expectation: :merchant_gated,
      interaction: :manual,
      completion_driver: nil,
      settlement: :unknown,
      flows: []
    }
  end

  defp method_metadata(type)
       when type in [:apple_pay, :google_pay, :samsung_pay, :mobile_pay] do
    %{
      support_expectation: :device_or_manual_required,
      interaction: :manual,
      completion_driver: nil,
      settlement: :unknown,
      flows: []
    }
  end

  defp method_metadata(type) when type in [:bancontact_card, :giropay, :ideal] do
    %{
      support_expectation: :regional,
      interaction: :manual,
      completion_driver: nil,
      settlement: :unknown,
      flows: []
    }
  end

  defp method_metadata(_type) do
    %{
      support_expectation: :enum_only,
      interaction: :unknown,
      completion_driver: nil,
      settlement: :unknown,
      flows: []
    }
  end

  defp concrete_features([:all]), do: @concrete_features
  defp concrete_features(features), do: features

  defp feature_scenarios(:payment_method_types, options) do
    selected = if options.methods == :all, do: @source_types, else: options.methods

    Enum.map(selected, fn type ->
      entry = fetch!(type)

      %{
        base_id: "payment-method-type:#{wire(:payment_method_type, type)}",
        feature: :payment_method_types,
        method: type,
        family: entry.family,
        support_expectation: entry.support_expectation,
        declared_interaction: entry.interaction,
        selected_interaction: options.interaction,
        # Local scenarios prove wire serialization and application lifecycle
        # handling without driving a browser/device. Availability and actual
        # completion remain separate sandbox assertions.
        interaction_match?:
          options.profile == :local or entry.interaction in [options.interaction, :unknown],
        completion_driver: entry.completion_driver,
        verification_target: verification_target(options.profile)
      }
    end)
  end

  defp feature_scenarios(:payment_method_families, options) do
    selected = if options.families == :all, do: @source_families, else: options.families

    Enum.map(selected, fn family ->
      %{
        base_id: "payment-method-family:#{wire(:payment_method_family, family)}",
        feature: :payment_method_families,
        method: nil,
        family: family,
        methods: Map.fetch!(@family_groups, family),
        support_expectation: :enum_only,
        declared_interaction: :unknown,
        selected_interaction: options.interaction,
        interaction_match?: true,
        completion_driver: nil,
        verification_target: verification_target(options.profile)
      }
    end)
  end

  defp feature_scenarios(feature, options) when feature in @concrete_features do
    [
      %{
        base_id: Atom.to_string(feature),
        feature: feature,
        method: nil,
        family: nil,
        support_expectation: :documented_supported,
        declared_interaction: :automated,
        selected_interaction: options.interaction,
        interaction_match?: options.interaction == :automated,
        completion_driver: nil,
        combined_inventory?: options.features == [:all],
        verification_target: verification_target(options.profile)
      }
    ]
  end

  defp outcome_scenarios(scenario, options) do
    scenario
    |> feature_outcomes(options.outcomes)
    |> resolved_outcomes(options.seed, scenario.base_id)
    |> Enum.map(fn outcome ->
      scenario
      |> Map.put(:id, "#{scenario.base_id}:#{outcome}")
      |> Map.put(:outcome, outcome)
      |> Map.put(:seed, options.seed)
      |> Map.delete(:base_id)
    end)
  end

  defp feature_outcomes(%{feature: :refunds, combined_inventory?: true}, _outcomes),
    do: [:refunded]

  defp feature_outcomes(%{feature: :refunds}, [:all]), do: [:refunded]

  defp feature_outcomes(%{feature: :refunds}, outcomes),
    do: Enum.filter(outcomes, &(&1 == :refunded))

  defp feature_outcomes(%{feature: :disputes, combined_inventory?: true}, _outcomes),
    do: [:disputed]

  defp feature_outcomes(%{feature: :disputes}, [:all]), do: [:disputed]

  defp feature_outcomes(%{feature: :disputes}, outcomes),
    do: Enum.filter(outcomes, &(&1 == :disputed))

  defp feature_outcomes(_scenario, outcomes), do: outcomes

  defp resolved_outcomes([:all], _seed, _scenario_id), do: Options.lifecycle_outcomes()

  defp resolved_outcomes([:random], seed, scenario_id) do
    outcomes = Options.lifecycle_outcomes()
    [Enum.at(outcomes, rem(stable_hash("#{seed}:#{scenario_id}"), length(outcomes)))]
  end

  defp resolved_outcomes(outcomes, _seed, _scenario_id), do: outcomes

  # A small stable FNV-1a implementation avoids touching application or RNG
  # state during `--dry-run`, while making the printed seed fully replayable.
  defp stable_hash(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.reduce(2_166_136_261, fn byte, hash ->
      Bitwise.band(Bitwise.bxor(hash, byte) * 16_777_619, 0xFFFFFFFF)
    end)
  end

  defp verification_target(:local), do: :local_contract
  defp verification_target(:sandbox_api), do: :session_created
  defp verification_target(:sandbox_checkout), do: :webhook_processed

  defp wire(enum, value), do: DodoPayments.Enums.dump!(enum, value)
end
