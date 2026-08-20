defmodule DodoStore.Smoke.Report do
  @moduledoc "A structured, secret-safe report for one smoke invocation."

  @enforce_keys [:run_id, :profile, :seed, :outcome, :results]
  defstruct [
    :run_id,
    :profile,
    :seed,
    :outcome,
    :started_at,
    :finished_at,
    :preflight_error,
    coverage: %{},
    results: [],
    claims: %{
      external_network: :blocked,
      webhook_delivery: :synthetic_valid_signature,
      proves_dodo_origin: false
    }
  ]

  @type t :: %__MODULE__{}
end

defimpl Inspect, for: DodoStore.Smoke.Report do
  import Inspect.Algebra

  def inspect(report, opts) do
    safe =
      Map.take(report, [
        :run_id,
        :profile,
        :seed,
        :outcome,
        :started_at,
        :finished_at,
        :preflight_error,
        :coverage,
        :results,
        :claims
      ])

    concat(["#DodoStore.Smoke.Report<", to_doc(safe, opts), ">"])
  end
end
