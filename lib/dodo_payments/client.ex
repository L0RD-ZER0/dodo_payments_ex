defmodule DodoPayments.Client do
  @moduledoc """
  Explicit, immutable configuration for Dodo Payments calls.

  Clients are ordinary values: there is no global API key, tenant registry, or
  client-specific process. The SDK application owns a small root supervisor for
  deadline isolation. The default transport is `DodoPayments.ReqClient`; pass `client:
  {module, state}` to use any conforming `DodoPayments.ClientModule`.

  The default environment is `:test`, making accidental live charges less likely.

      client =
        DodoPayments.Client.new!(
          api_key: System.fetch_env!("DODO_PAYMENTS_API_KEY")
        )

  API keys can also be supplied by a zero-arity function for runtime secret
  rotation. The function is resolved once per logical SDK call.
  """

  alias DodoPayments.Deadline
  alias DodoPayments.Error.ConfigurationError

  @type credential :: String.t() | (-> String.t() | nil)

  @test_url "https://test.dodopayments.com"
  @live_url "https://live.dodopayments.com"
  @default_environment :test
  @default_timeout 30_000
  @default_max_response_bytes 10 * 1024 * 1024
  @default_max_attempts 3
  @default_retry_base_delay 200
  @default_retry_max_delay 2_000
  @options [
    :api_key,
    :environment,
    :base_url,
    :allow_insecure_http,
    :client,
    :req,
    :timeout,
    :max_response_bytes,
    :max_attempts,
    :retry_base_delay,
    :retry_max_delay
  ]

  @enforce_keys [:base_url, :client_module, :client_state]
  defstruct [
    :api_key,
    :base_url,
    :client_module,
    :client_state,
    environment: @default_environment,
    timeout: @default_timeout,
    max_response_bytes: @default_max_response_bytes,
    max_attempts: @default_max_attempts,
    retry_base_delay: @default_retry_base_delay,
    retry_max_delay: @default_retry_max_delay
  ]

  @type environment :: :test | :live | :custom
  @type environment_input ::
          environment()
          | :test_mode
          | :live_mode
          | String.t()
  @type t :: %__MODULE__{
          api_key: DodoPayments.Secret.t() | nil,
          client_module: module(),
          client_state: term(),
          base_url: String.t(),
          environment: environment(),
          timeout: pos_integer(),
          max_response_bytes: pos_integer() | :infinity,
          max_attempts: pos_integer(),
          retry_base_delay: non_neg_integer(),
          retry_max_delay: non_neg_integer()
        }

  @doc "Creates a client, returning configuration errors as data."
  @spec new(keyword()) :: {:ok, t()} | {:error, ConfigurationError.t()}
  def new(opts \\ []) do
    with :ok <- validate_options(opts),
         :ok <- validate_insecure_http_option(opts),
         {:ok, api_key} <- api_key(opts),
         {:ok, environment, base_url} <- environment_and_url(opts),
         {:ok, module, state} <- client_module(opts),
         {:ok, timeout} <- timeout(opts, @default_timeout),
         {:ok, max_response_bytes} <-
           byte_limit(opts, :max_response_bytes, @default_max_response_bytes),
         {:ok, max_attempts} <- positive_integer(opts, :max_attempts, @default_max_attempts),
         {:ok, retry_base_delay} <-
           non_negative_integer(opts, :retry_base_delay, @default_retry_base_delay),
         {:ok, retry_max_delay} <-
           non_negative_integer(opts, :retry_max_delay, @default_retry_max_delay),
         :ok <- ensure_retry_range(retry_base_delay, retry_max_delay) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         client_module: module,
         client_state: state,
         base_url: base_url,
         environment: environment,
         timeout: timeout,
         max_response_bytes: max_response_bytes,
         max_attempts: max_attempts,
         retry_base_delay: retry_base_delay,
         retry_max_delay: retry_max_delay
       }}
    end
  end

  @doc "Creates a client or raises `DodoPayments.Error.ConfigurationError`."
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    case new(opts) do
      {:ok, client} -> client
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns a new client using a different key or zero-arity key provider.

  Direct keys are validated immediately and invalid values raise
  `DodoPayments.Error.ConfigurationError`. A provider's returned value is
  necessarily validated when the provider is resolved for a request.
  """
  @spec with_api_key(t(), credential() | nil) :: t()
  def with_api_key(%__MODULE__{} = client, api_key)
      when is_function(api_key, 0) or is_nil(api_key) do
    %{client | api_key: DodoPayments.Secret.new(api_key)}
  end

  def with_api_key(%__MODULE__{} = client, api_key) when is_binary(api_key) do
    if DodoPayments.Secret.valid_value?(api_key) do
      %{client | api_key: DodoPayments.Secret.new(api_key)}
    else
      invalid_api_key!()
    end
  end

  def with_api_key(%__MODULE__{}, _api_key) do
    invalid_api_key!()
  end

  defp environment_and_url(opts) do
    environment_option = Keyword.fetch(opts, :environment)
    base_url = Keyword.get(opts, :base_url)
    allow_insecure_http? = Keyword.get(opts, :allow_insecure_http, false)

    case {environment_option, base_url} do
      {:error, nil} ->
        {:ok, @default_environment, @test_url}

      {:error, url} when is_binary(url) ->
        validate_url(:custom, url, allow_insecure_http?)

      {{:ok, value}, nil} ->
        with {:ok, environment} <- normalize_environment(value) do
          environment_url(environment)
        end

      {{:ok, value}, url} when is_binary(url) ->
        with {:ok, environment} <- normalize_environment(value) do
          if environment == :custom,
            do: validate_url(:custom, url, allow_insecure_http?),
            else: error("base_url can only be combined with environment: :custom")
        end

      {_environment, _url} ->
        error("base_url must be an absolute HTTPS URL")
    end
  end

  defp environment_url(:test), do: {:ok, :test, @test_url}
  defp environment_url(:live), do: {:ok, :live, @live_url}
  defp environment_url(:custom), do: error("environment :custom requires base_url")

  defp normalize_environment(value) when value in [:test, :test_mode, "test", "test_mode"],
    do: {:ok, :test}

  defp normalize_environment(value) when value in [:live, :live_mode, "live", "live_mode"],
    do: {:ok, :live}

  defp normalize_environment(:custom), do: {:ok, :custom}

  defp normalize_environment(_value) do
    error("environment must be test, live, or :custom with base_url")
  end

  defp api_key(opts) do
    case Keyword.get(opts, :api_key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if DodoPayments.Secret.valid_value?(value),
          do: {:ok, DodoPayments.Secret.new(value)},
          else: invalid_api_key()

      value when is_function(value, 0) ->
        {:ok, DodoPayments.Secret.new(value)}

      _ ->
        invalid_api_key()
    end
  end

  defp invalid_api_key do
    error(
      "api_key must be a non-empty ASCII string without HTTP control bytes, a zero-arity function, or nil"
    )
  end

  defp invalid_api_key! do
    raise ConfigurationError,
      message:
        "api_key must be a non-empty ASCII string without HTTP control bytes, a zero-arity function, or nil"
  end

  defp validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        error("client options must be a keyword list")

      unknown = Keyword.keys(opts) -- @options ->
        if unknown == [],
          do: :ok,
          else: error("unknown client option(s): #{Enum.map_join(unknown, ", ", &inspect/1)}")
    end
  end

  defp validate_insecure_http_option(opts) do
    if is_boolean(Keyword.get(opts, :allow_insecure_http, false)),
      do: :ok,
      else: error("allow_insecure_http must be a boolean")
  end

  defp validate_url(environment, url, allow_insecure_http?) do
    with {:ok, uri} <- URI.new(url),
         true <- valid_percent_encoding?(url),
         true <- valid_base_uri?(uri, allow_insecure_http?) do
      {:ok, environment, String.trim_trailing(url, "/")}
    else
      _ ->
        error(
          "base_url must be an absolute HTTPS URL without credentials, query, or fragment; " <>
            "set allow_insecure_http: true only for trusted local HTTP origins"
        )
    end
  end

  defp valid_base_uri?(uri, allow_insecure_http?) do
    (uri.scheme == "https" or (allow_insecure_http? and uri.scheme == "http")) and
      is_binary(uri.host) and uri.host != "" and
      uri.port in 1..65_535 and is_nil(uri.userinfo) and is_nil(uri.query) and
      is_nil(uri.fragment)
  end

  defp valid_percent_encoding?(<<>>), do: true

  defp valid_percent_encoding?(<<"%", high, low, rest::binary>>)
       when high in ?0..?9 or high in ?A..?F or high in ?a..?f do
    if low in ?0..?9 or low in ?A..?F or low in ?a..?f,
      do: valid_percent_encoding?(rest),
      else: false
  end

  defp valid_percent_encoding?(<<"%", _rest::binary>>), do: false
  defp valid_percent_encoding?(<<_byte, rest::binary>>), do: valid_percent_encoding?(rest)

  defp client_module(opts) do
    case {Keyword.get(opts, :client), Keyword.get(opts, :req)} do
      {client, req} when not is_nil(client) and not is_nil(req) ->
        error("client and req are mutually exclusive")

      {{module, state}, nil} when is_atom(module) ->
        validate_client_module(module, state)

      {nil, _} ->
        req_client(opts)

      _ ->
        error("client must be a {module, state} tuple")
    end
  end

  defp validate_client_module(module, state) do
    if Code.ensure_loaded?(module) and function_exported?(module, :request, 2) do
      {:ok, module, state}
    else
      error("client module #{inspect(module)} must export request/2")
    end
  end

  defp req_client(opts) do
    case Keyword.get(opts, :req) do
      nil ->
        case DodoPayments.ReqClient.new() do
          {:ok, state} -> {:ok, DodoPayments.ReqClient, state}
          {:error, error} -> {:error, error}
        end

      %Req.Request{} = request ->
        case DodoPayments.ReqClient.from_req(request) do
          {:ok, state} -> {:ok, DodoPayments.ReqClient, state}
          {:error, error} -> {:error, error}
        end

      _ ->
        error("req must be a %Req.Request{}")
    end
  end

  defp positive_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> error("#{key} must be a positive integer")
    end
  end

  defp timeout(opts, default) do
    value = Keyword.get(opts, :timeout, default)

    if Deadline.valid_timeout?(value),
      do: {:ok, value},
      else: error("timeout must be between 1 and #{Deadline.max_timeout()} milliseconds")
  end

  defp non_negative_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> error("#{key} must be a non-negative integer")
    end
  end

  defp byte_limit(opts, key, default) do
    case Keyword.get(opts, key, default) do
      :infinity -> {:ok, :infinity}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> error("#{key} must be a positive integer or :infinity")
    end
  end

  defp ensure_retry_range(base, max) when base <= max, do: :ok
  defp ensure_retry_range(_, _), do: error("retry_base_delay cannot exceed retry_max_delay")

  defp error(message), do: {:error, ConfigurationError.exception(message: message)}
end

defimpl Inspect, for: DodoPayments.Client do
  import Inspect.Algebra

  def inspect(client, opts) do
    values = [
      environment: client.environment,
      base_url: client.base_url,
      api_key: if(client.api_key, do: :redacted, else: nil),
      client_module: client.client_module,
      timeout: client.timeout,
      max_response_bytes: client.max_response_bytes,
      max_attempts: client.max_attempts
    ]

    concat(["#DodoPayments.Client<", to_doc(values, opts), ">"])
  end
end
