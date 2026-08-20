defmodule DodoPayments.Telemetry do
  @moduledoc false

  @default_mode :request_bounded
  @default_max_concurrency 64
  @default_timeout 1_000
  @options [:mode, :max_concurrency, :timeout]

  @type mode :: :request_bounded | :async
  @type config :: %{mode: mode(), max_concurrency: pos_integer(), timeout: pos_integer()}

  @spec validate_config!() :: config()
  def validate_config! do
    Application.get_env(:dodo_payments, __MODULE__, [])
    |> normalize_config()
    |> validate_config!()
  end

  @spec validate_config!(term()) :: config()
  def validate_config!(config) do
    config = normalize_config(config)

    unless config.mode in [:request_bounded, :async] do
      raise ArgumentError,
            "invalid config :telemetry mode; expected :request_bounded or :async"
    end

    validate_positive!(:max_concurrency, config.max_concurrency)
    validate_positive!(:timeout, config.timeout)
    config
  end

  defp normalize_config(config) when is_list(config) do
    if Keyword.keyword?(config) and Keyword.keys(config) -- @options == [] do
      %{
        mode: Keyword.get(config, :mode, @default_mode),
        max_concurrency: Keyword.get(config, :max_concurrency, @default_max_concurrency),
        timeout: Keyword.get(config, :timeout, @default_timeout)
      }
    else
      invalid_config!()
    end
  end

  defp normalize_config(config) when is_map(config) do
    if Map.keys(config) -- @options == [] do
      %{
        mode: Map.get(config, :mode, @default_mode),
        max_concurrency: Map.get(config, :max_concurrency, @default_max_concurrency),
        timeout: Map.get(config, :timeout, @default_timeout)
      }
    else
      invalid_config!()
    end
  end

  defp normalize_config(_config), do: invalid_config!()

  defp invalid_config! do
    raise ArgumentError,
          "invalid config :telemetry; expected only :mode, :max_concurrency, and :timeout"
  end

  defp validate_positive!(key, value) do
    unless is_integer(value) and value > 0 do
      raise ArgumentError,
            "invalid config :telemetry #{key}; expected a positive integer"
    end
  end
end
