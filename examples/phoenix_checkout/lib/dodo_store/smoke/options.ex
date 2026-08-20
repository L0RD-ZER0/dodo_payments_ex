defmodule DodoStore.Smoke.Options do
  @moduledoc """
  Strict command-line contract for the production-shaped smoke harness.

  User-provided enum strings are resolved through fixed lookup tables. The
  parser never creates atoms from command-line input.
  """

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end

  @profiles %{
    "local" => :local,
    "sandbox-api" => :sandbox_api,
    "sandbox-checkout" => :sandbox_checkout
  }

  @features %{
    "core" => :core,
    "payment-method-types" => :payment_method_types,
    "payment-method-families" => :payment_method_families,
    "refunds" => :refunds,
    "disputes" => :disputes,
    "resilience" => :resilience,
    "all" => :all
  }

  @interactions %{"automated" => :automated, "manual" => :manual}
  @executions %{"sequential" => :sequential, "parallel" => :parallel}
  @coverage_modes %{"strict" => :strict, "informational" => :informational}

  @outcomes %{
    "accepted" => :accepted,
    "rejected" => :rejected,
    "cancelled" => :cancelled,
    "refunded" => :refunded,
    "disputed" => :disputed,
    "processing-accepted" => :processing_accepted,
    "processing-rejected" => :processing_rejected,
    "random" => :random,
    "all" => :all
  }

  @switches [
    profile: [:string, :keep],
    features: [:string, :keep],
    methods: [:string, :keep],
    families: [:string, :keep],
    interaction: [:string, :keep],
    execution: [:string, :keep],
    coverage: [:string, :keep],
    max_concurrency: [:integer, :keep],
    timeout: [:integer, :keep],
    resume: [:string, :keep],
    report: [:string, :keep],
    dry_run: [:boolean, :keep],
    seed: [:integer, :keep],
    outcome: [:string, :keep],
    help: [:boolean, :keep]
  ]

  @enforce_keys [
    :profile,
    :features,
    :methods,
    :families,
    :interaction,
    :execution,
    :coverage,
    :max_concurrency,
    :timeout,
    :dry_run,
    :seed,
    :outcomes,
    :help
  ]
  defstruct @enforce_keys ++ [resume: nil, report: nil]

  @type profile :: :local | :sandbox_api | :sandbox_checkout
  @type feature ::
          :core
          | :payment_method_types
          | :payment_method_families
          | :refunds
          | :disputes
          | :resilience
          | :all
  @type interaction :: :automated | :manual
  @type execution :: :sequential | :parallel
  @type coverage_mode :: :strict | :informational
  @type outcome ::
          :accepted
          | :rejected
          | :cancelled
          | :refunded
          | :disputed
          | :processing_accepted
          | :processing_rejected
          | :random
          | :all

  @type t :: %__MODULE__{
          profile: profile(),
          features: [feature()],
          methods: :all | [DodoPayments.Enums.payment_method_type()],
          families: :all | [DodoPayments.Enums.payment_method_family()],
          interaction: interaction(),
          execution: execution(),
          coverage: coverage_mode(),
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          resume: String.t() | nil,
          report: String.t() | nil,
          dry_run: boolean(),
          seed: non_neg_integer(),
          outcomes: [outcome()],
          help: boolean()
        }

  @spec parse([String.t()]) :: {:ok, t()} | {:error, Error.t()}
  def parse(argv) when is_list(argv) do
    {:ok, parse!(argv)}
  rescue
    error in Error -> {:error, error}
  end

  @spec parse!([String.t()]) :: t()
  def parse!(argv) when is_list(argv) do
    {parsed, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    reject_invalid!(invalid)
    reject_positional!(positional)
    reject_duplicate_singulars!(parsed)

    profile = parse_one!(parsed, :profile, @profiles, :local)
    features = parse_many!(parsed, :features, @features, [:core])
    methods = parse_methods!(parsed)
    families = parse_families!(parsed)
    interaction = parse_one!(parsed, :interaction, @interactions, :automated)
    execution = parse_one!(parsed, :execution, @executions, :sequential)
    coverage = parse_one!(parsed, :coverage, @coverage_modes, :strict)

    seed =
      parsed
      |> Keyword.get(:seed, System.unique_integer([:positive, :monotonic]))
      |> positive_or_zero!("--seed")

    outcomes = parse_outcomes!(parsed, profile)

    options = %__MODULE__{
      profile: profile,
      features: features,
      methods: methods,
      families: families,
      interaction: interaction,
      execution: execution,
      coverage: coverage,
      max_concurrency: positive!(Keyword.get(parsed, :max_concurrency, 4), "--max-concurrency"),
      timeout: positive!(Keyword.get(parsed, :timeout, 60_000), "--timeout"),
      resume: optional_nonempty!(Keyword.get(parsed, :resume), "--resume"),
      report: optional_nonempty!(Keyword.get(parsed, :report), "--report"),
      dry_run: Keyword.get(parsed, :dry_run, false),
      seed: seed,
      outcomes: outcomes,
      help: Keyword.get(parsed, :help, false)
    }

    validate!(options, parsed)
  end

  @doc "Returns the stable lifecycle outcomes represented by `--outcome all`."
  @spec lifecycle_outcomes() :: [outcome()]
  def lifecycle_outcomes do
    [
      :accepted,
      :rejected,
      :cancelled,
      :refunded,
      :disputed,
      :processing_accepted,
      :processing_rejected
    ]
  end

  @doc "Human-readable task usage."
  @spec help() :: String.t()
  def help do
    """
    Usage: mix dodo.smoke [options]

      --profile local|sandbox-api|sandbox-checkout
      --features core,payment-method-types,payment-method-families,
                 refunds,disputes,resilience|all
      --methods all|TYPE[,TYPE...]
      --families all|FAMILY[,FAMILY...]
      --interaction automated|manual
      --execution sequential|parallel
      --coverage strict|informational
      --outcome accepted|rejected|cancelled|refunded|disputed|
                processing-accepted|processing-rejected|random|all
      --seed NON_NEGATIVE_INTEGER
      --max-concurrency POSITIVE_INTEGER
      --timeout POSITIVE_MILLISECONDS
      --resume RUN_ID  (reserved; fails closed until checkpoint-aware continuation exists)
      --report PATH
      --dry-run
    """
  end

  defp parse_one!(parsed, key, choices, default) do
    case Keyword.get(parsed, key) do
      nil -> default
      value -> lookup!(choices, value, "--#{cli_name(key)}")
    end
  end

  defp parse_many!(parsed, key, choices, default) do
    case values!(parsed, key) do
      [] ->
        default

      raw_values ->
        selected = Enum.map(raw_values, &lookup!(choices, &1, "--#{cli_name(key)}"))
        reject_reserved_mix!(selected, :all, "--#{cli_name(key)}")
        Enum.uniq(selected)
    end
  end

  defp parse_methods!(parsed) do
    case values!(parsed, :methods) do
      [] ->
        :all

      ["all"] ->
        :all

      raw_values ->
        if "all" in raw_values do
          fail!("--methods all cannot be combined with method names")
        else
          parse_dodo_enum!(raw_values, :payment_method_type, "--methods")
        end
    end
  end

  defp parse_families!(parsed) do
    case values!(parsed, :families) do
      [] ->
        :all

      ["all"] ->
        :all

      raw_values ->
        if "all" in raw_values do
          fail!("--families all cannot be combined with family names")
        else
          parse_dodo_enum!(raw_values, :payment_method_family, "--families")
        end
    end
  end

  defp parse_outcomes!(parsed, profile) do
    case values!(parsed, :outcome) do
      [] when profile == :local ->
        [:random]

      [] ->
        [:accepted]

      raw_values ->
        selected = Enum.map(raw_values, &lookup!(@outcomes, &1, "--outcome"))
        reject_reserved_mix!(selected, :all, "--outcome")
        reject_reserved_mix!(selected, :random, "--outcome")
        Enum.uniq(selected)
    end
  end

  defp values!(parsed, key) do
    raw_values = Keyword.get_values(parsed, key)

    values =
      raw_values
      |> Enum.flat_map(&String.split(&1, ",", trim: false))
      |> Enum.map(&String.trim/1)

    if raw_values != [] and Enum.any?(values, &(&1 == "")) do
      fail!("--#{cli_name(key)} contains an empty value")
    end

    values
  end

  defp parse_dodo_enum!(wire_values, enum, flag) do
    choices =
      Map.new(DodoPayments.Enums.values(enum), fn value ->
        {DodoPayments.Enums.dump!(enum, value), value}
      end)

    wire_values
    |> Enum.map(&lookup!(choices, &1, flag))
    |> Enum.uniq()
  end

  defp lookup!(choices, value, flag) do
    case Map.fetch(choices, value) do
      {:ok, choice} -> choice
      :error -> fail!("unknown value #{inspect(value)} for #{flag}")
    end
  end

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    rendered = Enum.map_join(invalid, ", ", fn {flag, value} -> "#{flag}=#{inspect(value)}" end)
    fail!("unknown or malformed options: #{rendered}")
  end

  defp reject_positional!([]), do: :ok

  defp reject_positional!(args),
    do: fail!("unexpected positional arguments: #{Enum.join(args, " ")}")

  defp reject_duplicate_singulars!(parsed) do
    repeatable = [:features, :methods, :families, :outcome]

    parsed
    |> Keyword.keys()
    |> Enum.reject(&(&1 in repeatable))
    |> Enum.find(fn key -> length(Keyword.get_values(parsed, key)) > 1 end)
    |> case do
      nil -> :ok
      key -> fail!("--#{cli_name(key)} may be specified only once")
    end
  end

  defp reject_reserved_mix!(values, reserved, flag) do
    if reserved in values and length(values) > 1 do
      fail!("#{flag} #{cli_value(reserved)} cannot be combined with other values")
    end
  end

  defp validate!(%__MODULE__{} = options, parsed) do
    if options.interaction == :manual and options.execution == :parallel do
      fail!("--interaction manual cannot be combined with --execution parallel")
    end

    if Keyword.has_key?(parsed, :methods) and
         not feature_enabled?(options.features, :payment_method_types) do
      fail!("--methods requires --features payment-method-types or all")
    end

    if Keyword.has_key?(parsed, :families) and
         not feature_enabled?(options.features, :payment_method_families) do
      fail!("--families requires --features payment-method-families or all")
    end

    if options.profile != :local and :random in options.outcomes do
      fail!("--outcome random is supported only by the local profile")
    end

    if options.resume && options.dry_run do
      fail!("--resume cannot be combined with --dry-run")
    end

    validate_feature_outcomes!(options)

    options
  end

  defp validate_feature_outcomes!(options) do
    outcomes = options.outcomes

    if :refunds in options.features and not (:refunded in outcomes or outcomes == [:all]) do
      fail!("--features refunds requires --outcome refunded or all")
    end

    if :disputes in options.features and not (:disputed in outcomes or outcomes == [:all]) do
      fail!("--features disputes requires --outcome disputed or all")
    end
  end

  defp feature_enabled?(features, feature), do: :all in features or feature in features

  defp positive!(value, _flag) when is_integer(value) and value > 0, do: value
  defp positive!(_value, flag), do: fail!("#{flag} must be a positive integer")

  defp positive_or_zero!(value, _flag) when is_integer(value) and value >= 0, do: value
  defp positive_or_zero!(_value, flag), do: fail!("#{flag} must be a non-negative integer")

  defp optional_nonempty!(nil, _flag), do: nil
  defp optional_nonempty!(value, _flag) when is_binary(value) and byte_size(value) > 0, do: value
  defp optional_nonempty!(_value, flag), do: fail!("#{flag} must not be empty")

  defp cli_name(value), do: value |> Atom.to_string() |> String.replace("_", "-")
  defp cli_value(value), do: value |> Atom.to_string() |> String.replace("_", "-")

  defp fail!(message), do: raise(Error, message: message)
end
