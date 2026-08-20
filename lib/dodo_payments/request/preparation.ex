defmodule DodoPayments.Request.Preparation do
  @moduledoc false

  alias DodoPayments.{Client, Deadline, Operation}
  alias DodoPayments.Error.ConfigurationError
  alias DodoPayments.Request.RetryPolicy

  @request_options [:headers, :timeout, :max_response_bytes, :max_attempts, :return]
  @transport_owned_headers ~w(
    accept-encoding
    connection
    content-encoding
    content-length
    expect
    host
    te
    trailer
    transfer-encoding
    upgrade
  )

  @doc false
  @spec transport_owned_headers() :: [String.t()]
  def transport_owned_headers, do: @transport_owned_headers

  @spec prepare(Client.t(), Operation.t(), map() | nil, keyword(), pos_integer(), integer()) ::
          {:ok, map()} | {:error, Exception.t()}
  def prepare(client, operation, params, opts, timeout, deadline) do
    with {:ok, prepared} <- Operation.prepare(operation, params),
         {:ok, body} <- encode_body(prepared.body, operation.id),
         {:ok, url} <- build_url(client.base_url, prepared.path, prepared.query),
         {:ok, headers} <- build_headers(client, operation, body, opts),
         {:ok, max_response_bytes} <-
           byte_limit_option(opts, :max_response_bytes, client.max_response_bytes),
         {:ok, max_attempts} <- positive_option(opts, :max_attempts, client.max_attempts),
         {:ok, return} <- return_option(opts) do
      {:ok,
       %{
         client: client,
         operation: operation,
         body: body,
         url: url,
         headers: headers,
         timeout: timeout,
         max_response_bytes: max_response_bytes,
         deadline: deadline,
         max_attempts: max_attempts,
         replayable?: RetryPolicy.replayable?(operation.replay, params),
         params: params || %{},
         opts: opts,
         return: return,
         uncertainty: nil
       }}
    end
  end

  @spec validate_options(term()) :: :ok | {:error, ConfigurationError.t()}
  def validate_options(opts) do
    if Keyword.keyword?(opts) do
      validate_known_options(opts)
    else
      configuration_error("request options must be a keyword list")
    end
  end

  @spec positive_option(keyword(), atom(), pos_integer()) ::
          {:ok, pos_integer()} | {:error, ConfigurationError.t()}
  def positive_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> configuration_error("#{key} must be a positive integer")
    end
  end

  @spec timeout_option(term(), pos_integer()) ::
          {:ok, pos_integer()} | {:error, ConfigurationError.t()}
  def timeout_option(opts, default) do
    if Keyword.keyword?(opts) do
      value = Keyword.get(opts, :timeout, default)

      if Deadline.valid_timeout?(value),
        do: {:ok, value},
        else:
          configuration_error(
            "timeout must be between 1 and #{Deadline.max_timeout()} milliseconds"
          )
    else
      configuration_error("request options must be a keyword list")
    end
  end

  defp validate_known_options(opts) do
    case Keyword.keys(opts) -- @request_options do
      [] ->
        validate_headers(Keyword.get(opts, :headers, []))

      unknown ->
        configuration_error(
          "unknown request option(s): #{Enum.map_join(unknown, ", ", &inspect/1)}"
        )
    end
  end

  defp encode_body(nil, _operation), do: {:ok, nil}

  defp encode_body(body, operation) do
    case Jason.encode(body) do
      {:ok, encoded} ->
        {:ok, encoded}

      {:error, reason} ->
        {:error,
         DodoPayments.ValidationError.exception(
           operation: operation,
           reason: {:json_encoding_failed, reason}
         )}
    end
  end

  defp build_url(base_url, path, query) do
    url = base_url <> "/" <> String.trim_leading(path, "/")

    query_string =
      query
      |> Enum.flat_map(fn {key, value} -> query_pairs(to_string(key), value) end)
      |> URI.encode_query()

    {:ok, if(query_string == "", do: url, else: url <> "?" <> query_string)}
  rescue
    exception ->
      {:error,
       DodoPayments.ValidationError.exception(
         operation: :request,
         reason: {:invalid_query, exception}
       )}
  end

  defp query_pairs(_key, nil), do: []

  defp query_pairs(key, values) when is_list(values),
    do: Enum.map(values, &{key, query_value(&1)})

  defp query_pairs(key, value), do: [{key, query_value(value)}]

  defp query_value(value) when is_binary(value), do: value
  defp query_value(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp query_value(value) when is_map(value), do: Jason.encode!(value)
  defp query_value(value), do: to_string(value)

  defp build_headers(client, operation, body, opts) do
    supplied = opts |> Keyword.get(:headers, []) |> normalize_headers()
    supplied = delete_headers(supplied, protected_header_names())

    base =
      supplied
      |> put_header("accept", accept(operation.response_mode))
      |> put_new_header("user-agent", DodoPayments.user_agent())
      |> maybe_put_content_type(body)

    case operation.auth do
      :public ->
        {:ok, base}

      :merchant ->
        with {:ok, api_key} <- DodoPayments.Secret.resolve(client.api_key) do
          {:ok, put_header(base, "authorization", "Bearer " <> api_key)}
        end
    end
  end

  defp normalize_headers(headers) do
    Enum.flat_map(headers, fn
      {name, values} when is_list(values) ->
        Enum.map(values, &{wire_header_name(name), to_string(&1)})

      {name, value} ->
        [{wire_header_name(name), to_string(value)}]
    end)
  end

  defp protected_header_names,
    do: @transport_owned_headers ++ DodoPayments.Redaction.credential_headers()

  defp delete_headers(headers, names) do
    names = MapSet.new(names)

    Enum.reject(headers, fn {key, _value} ->
      DodoPayments.Redaction.header_name(key) in names or
        DodoPayments.Redaction.credential_header?(key)
    end)
  end

  defp delete_header(headers, name) do
    Enum.reject(headers, fn {key, _value} -> String.downcase(key) == name end)
  end

  defp put_header(headers, name, value), do: [{name, value} | delete_header(headers, name)]

  defp put_new_header(headers, name, value) do
    if Enum.any?(headers, fn {key, _value} -> String.downcase(key) == name end),
      do: headers,
      else: [{name, value} | headers]
  end

  defp maybe_put_content_type(headers, nil), do: headers

  defp maybe_put_content_type(headers, _body),
    do: put_header(headers, "content-type", "application/json")

  defp accept(:json), do: "application/json"
  defp accept(:pdf), do: "application/pdf"
  defp accept(:csv), do: "text/csv"
  defp accept(_response_mode), do: "*/*"

  defp validate_headers(headers) when is_map(headers) do
    headers |> Map.to_list() |> validate_headers()
  end

  defp validate_headers(headers) when is_list(headers) do
    if not List.improper?(headers) and Enum.all?(headers, &valid_header?/1),
      do: :ok,
      else: configuration_error("headers must contain string or atom names and scalar values")
  end

  defp validate_headers(_headers) do
    configuration_error("headers must be a map or list of {name, value} pairs")
  end

  defp valid_header?({name, values}) when is_list(values) do
    valid_header_name?(name) and values != [] and not List.improper?(values) and
      Enum.all?(values, &valid_header_value?/1)
  end

  defp valid_header?({name, value}),
    do: valid_header_name?(name) and valid_header_value?(value)

  defp valid_header?(_header), do: false

  defp valid_header_name?(name) when is_atom(name),
    do: name |> wire_header_name() |> valid_header_name?()

  defp valid_header_name?(name) when is_binary(name),
    do: Regex.match?(~r/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/, name)

  defp valid_header_name?(_name), do: false

  defp wire_header_name(name) when is_atom(name),
    do: name |> Atom.to_string() |> String.replace("_", "-")

  defp wire_header_name(name), do: name

  defp valid_header_value?(value) when is_binary(value) or is_atom(value) or is_number(value) do
    value
    |> to_string()
    |> :binary.bin_to_list()
    |> Enum.all?(fn
      9 -> true
      byte when byte in 32..126 -> true
      _byte -> false
    end)
  end

  defp valid_header_value?(_value), do: false

  defp byte_limit_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      :infinity -> {:ok, :infinity}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> configuration_error("#{key} must be a positive integer or :infinity")
    end
  end

  defp return_option(opts) do
    case Keyword.get(opts, :return, :data) do
      value when value in [:data, :response] -> {:ok, value}
      _other -> configuration_error("return must be :data or :response")
    end
  end

  defp configuration_error(message), do: {:error, ConfigurationError.exception(message: message)}
end
