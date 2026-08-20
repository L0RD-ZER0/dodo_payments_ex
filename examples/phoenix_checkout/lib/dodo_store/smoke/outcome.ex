defmodule DodoStore.Smoke.Outcome do
  @moduledoc """
  One secret-safe result from the local smoke scenario engine.

  `outcome` describes whether the harness proved its expectation. The separate
  `lifecycle_outcome` says what the synthetic checkout did; a correctly handled
  declined payment is therefore a passing smoke result whose lifecycle outcome
  is `:rejected`.
  """

  @enforce_keys [
    :scenario_id,
    :lifecycle_outcome,
    :outcome,
    :verification_level,
    :support_expectation
  ]
  defstruct [
    :scenario_id,
    :target,
    :lifecycle_outcome,
    :outcome,
    :verification_level,
    :support_expectation,
    :duration_ms,
    signature_provenance: :synthetic_valid_signature,
    processor_mode: :explicit,
    observations: %{},
    errors: []
  ]

  @type result_outcome :: :pass | :fail | :skip | :inconclusive
  @type t :: %__MODULE__{
          scenario_id: String.t(),
          target: map() | nil,
          lifecycle_outcome: atom(),
          outcome: result_outcome(),
          verification_level: atom(),
          support_expectation: atom(),
          duration_ms: non_neg_integer() | nil,
          signature_provenance: :synthetic_valid_signature,
          processor_mode: :explicit | :supervised,
          observations: map(),
          errors: [map()]
        }
end

defimpl Inspect, for: DodoStore.Smoke.Outcome do
  import Inspect.Algebra

  def inspect(result, opts) do
    safe =
      Map.take(result, [
        :scenario_id,
        :target,
        :lifecycle_outcome,
        :outcome,
        :verification_level,
        :support_expectation,
        :duration_ms,
        :signature_provenance,
        :processor_mode,
        :observations,
        :errors
      ])

    concat(["#DodoStore.Smoke.Outcome<", to_doc(safe, opts), ">"])
  end
end
