defmodule DodoPayments.Webhooks.Verifier do
  @moduledoc false

  import Bitwise

  alias DodoPayments.Webhooks.{Event, VerificationError}

  @default_tolerance 300
  @default_max_body_bytes 1_048_576
  @default_max_header_bytes 16_384
  @default_max_signatures 32
  @default_max_secrets 8
  @default_max_secret_bytes 4_096
  @options [
    :tolerance,
    :now,
    :max_body_bytes,
    :max_header_bytes,
    :max_signatures,
    :max_secrets,
    :max_secret_bytes
  ]
  @id_header "webhook-id"
  @timestamp_header "webhook-timestamp"
  @signature_header "webhook-signature"

  @spec verify(binary(), map() | [{term(), term()}], binary() | [binary()], keyword()) ::
          {:ok, Event.t()} | {:error, VerificationError.t()}
  def verify(raw_body, headers, secrets, opts) when is_binary(raw_body) do
    with :ok <- validate_limits(raw_body, headers, secrets, opts),
         {:ok, webhook_id} <- single_header(headers, @id_header),
         {:ok, timestamp_header} <- single_header(headers, @timestamp_header),
         {:ok, signature_header} <- joined_header(headers, @signature_header),
         {:ok, timestamp} <- parse_timestamp(timestamp_header),
         :ok <- timestamp_in_tolerance(timestamp, opts),
         {:ok, keys} <- decode_secrets(secrets),
         {:ok, signatures} <- decode_signatures(signature_header, opts),
         :ok <- authenticate(raw_body, webhook_id, timestamp_header, keys, signatures),
         {:ok, payload} <- decode_json(raw_body) do
      decode_event(webhook_id, raw_body, payload)
    end
  end

  def verify(_raw_body, _headers, _secrets, _opts),
    do: error(:invalid_body)

  @spec verify_signature(binary(), map() | [{term(), term()}], binary() | [binary()], keyword()) ::
          :ok | {:error, VerificationError.t()}
  def verify_signature(raw_body, headers, secrets, opts) when is_binary(raw_body) do
    with :ok <- validate_limits(raw_body, headers, secrets, opts),
         {:ok, webhook_id} <- single_header(headers, @id_header),
         {:ok, timestamp_header} <- single_header(headers, @timestamp_header),
         {:ok, signature_header} <- joined_header(headers, @signature_header),
         {:ok, timestamp} <- parse_timestamp(timestamp_header),
         :ok <- timestamp_in_tolerance(timestamp, opts),
         {:ok, keys} <- decode_secrets(secrets),
         {:ok, signatures} <- decode_signatures(signature_header, opts) do
      authenticate(raw_body, webhook_id, timestamp_header, keys, signatures)
    end
  end

  def verify_signature(_raw_body, _headers, _secrets, _opts),
    do: error(:invalid_body)

  defp single_header(headers, name) do
    case header_values(headers, name) do
      [] -> error(:missing_header, header: name)
      [value] when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      [_] -> error(:missing_header, header: name)
      _ -> error(:ambiguous_header, header: name)
    end
  end

  defp joined_header(headers, name) do
    values = Enum.reject(header_values(headers, name), &(String.trim(&1) == ""))

    case values do
      [] -> error(:missing_header, header: name)
      values -> {:ok, Enum.join(values, " ")}
    end
  end

  defp header_values(%_{} = _headers, _wanted), do: []

  defp header_values(headers, wanted) when is_map(headers) do
    headers
    |> Enum.flat_map(fn {key, value} ->
      if header_name(key) == wanted, do: List.wrap(value), else: []
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp header_values(headers, wanted) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> if header_name(key) == wanted, do: List.wrap(value), else: []
      _ -> []
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp header_values(_, _), do: []

  defp header_name(key) when is_binary(key), do: String.downcase(key)

  defp header_name(key) when is_atom(key),
    do: key |> Atom.to_string() |> String.replace("_", "-") |> String.downcase()

  defp header_name(_), do: ""

  defp parse_timestamp(value) do
    case Integer.parse(value) do
      {timestamp, ""} when timestamp >= 0 -> {:ok, timestamp}
      _ -> error(:invalid_timestamp)
    end
  end

  defp timestamp_in_tolerance(timestamp, opts) do
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance)

    with {:ok, now} <- now(opts) do
      if abs(now - timestamp) <= tolerance,
        do: :ok,
        else: error(:timestamp_outside_tolerance)
    end
  end

  defp now(opts) do
    case Keyword.get(opts, :now, fn -> System.system_time(:second) end) do
      fun when is_function(fun, 0) ->
        try do
          case fun.() do
            timestamp when is_integer(timestamp) -> {:ok, timestamp}
            _value -> error(:invalid_options)
          end
        rescue
          _exception -> error(:invalid_options)
        catch
          _kind, _reason -> error(:invalid_options)
        end

      timestamp when is_integer(timestamp) ->
        {:ok, timestamp}

      _value ->
        error(:invalid_options)
    end
  end

  defp decode_secrets(secret) when is_binary(secret), do: decode_secrets([secret])

  defp decode_secrets(secrets) when is_list(secrets) and secrets != [] do
    secrets
    |> Enum.reduce_while({:ok, []}, fn secret, {:ok, keys} ->
      case decode_secret(secret) do
        {:ok, key} -> {:cont, {:ok, [key | keys]}}
        :error -> {:halt, error(:invalid_secret)}
      end
    end)
  end

  defp decode_secrets(_), do: error(:invalid_secret)

  defp decode_secret("whsec_" <> encoded), do: decode_base64(encoded)
  defp decode_secret(_), do: :error

  defp decode_signatures(value, opts) do
    signatures =
      value
      |> String.split(~r/\s+/, trim: true)
      |> Enum.flat_map(&decode_signature_token/1)

    cond do
      signatures == [] ->
        error(:invalid_signature)

      length(signatures) > limit(opts, :max_signatures, @default_max_signatures) ->
        error(:resource_limit)

      true ->
        {:ok, signatures}
    end
  end

  defp decode_signature_token(token) do
    with ["v1", encoded] <- String.split(token, ",", parts: 2),
         {:ok, signature} <- decode_base64(encoded) do
      [signature]
    else
      _error -> []
    end
  end

  defp validate_limits(raw_body, headers, secrets, opts) do
    with :ok <- validate_options(opts),
         true <- byte_size(raw_body) <= limit(opts, :max_body_bytes, @default_max_body_bytes),
         max_header_bytes = limit(opts, :max_header_bytes, @default_max_header_bytes),
         true <- header_bytes(headers, max_header_bytes) <= max_header_bytes,
         :ok <- validate_secret_limits(secrets, opts) do
      :ok
    else
      {:error, _} = error -> error
      false -> error(:resource_limit)
    end
  end

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @options == [] and
         valid_option_values?(opts) do
      :ok
    else
      error(:invalid_options)
    end
  end

  defp valid_option_values?(opts) do
    valid_tolerance?(Keyword.get(opts, :tolerance, @default_tolerance)) and
      valid_now?(Keyword.get(opts, :now, fn -> System.system_time(:second) end)) and
      Enum.all?(
        [
          {:max_body_bytes, @default_max_body_bytes},
          {:max_header_bytes, @default_max_header_bytes},
          {:max_signatures, @default_max_signatures},
          {:max_secrets, @default_max_secrets},
          {:max_secret_bytes, @default_max_secret_bytes}
        ],
        fn {key, default} -> valid_positive_integer?(Keyword.get(opts, key, default)) end
      )
  end

  defp valid_tolerance?(value), do: is_integer(value) and value >= 0
  defp valid_now?(value), do: is_integer(value) or is_function(value, 0)
  defp valid_positive_integer?(value), do: is_integer(value) and value > 0

  defp limit(opts, key, default), do: Keyword.get(opts, key, default)

  defp header_bytes(%_{} = _headers, _limit), do: 0

  defp header_bytes(headers, limit) when is_map(headers),
    do: reduce_header_enumerable(headers, limit)

  defp header_bytes(headers, limit) when is_list(headers),
    do: reduce_header_list(headers, 0, limit)

  defp header_bytes(_, _limit), do: 0

  defp reduce_header_enumerable(headers, limit) do
    Enum.reduce_while(headers, 0, fn
      entry, total ->
        next = header_entry_bytes(entry, total, limit)
        if next > limit, do: {:halt, next}, else: {:cont, next}
    end)
  end

  defp reduce_header_list([], total, _limit), do: total

  defp reduce_header_list([entry | rest], total, limit) do
    next = header_entry_bytes(entry, total, limit)

    if next > limit,
      do: next,
      else: reduce_header_list(rest, next, limit)
  end

  defp reduce_header_list(_improper_tail, _total, limit), do: limit + 1

  defp header_entry_bytes({name, values}, total, limit) do
    case term_bytes(name) do
      {:ok, name_bytes} when is_list(values) ->
        header_value_list_bytes(values, name_bytes, total, limit)

      {:ok, name_bytes} ->
        header_value_list_bytes([values], name_bytes, total, limit)

      :error ->
        limit + 1
    end
  end

  defp header_entry_bytes(_invalid, total, _limit), do: total + 1

  defp header_value_list_bytes([], name_bytes, total, _limit),
    do: total + name_bytes + 1

  defp header_value_list_bytes([value | rest], name_bytes, total, limit) do
    case term_bytes(value) do
      {:ok, value_bytes} ->
        next = total + name_bytes + value_bytes + 1

        if next > limit,
          do: next,
          else: header_value_list_bytes(rest, name_bytes, next, limit)

      :error ->
        limit + 1
    end
  end

  defp header_value_list_bytes(_improper_tail, _name_bytes, _total, limit), do: limit + 1

  defp term_bytes(value) when is_binary(value), do: {:ok, byte_size(value)}
  defp term_bytes(value) when is_atom(value), do: {:ok, value |> Atom.to_string() |> byte_size()}
  defp term_bytes(_), do: :error

  defp validate_secret_limits(secret, opts) when is_binary(secret) do
    if byte_size(secret) <= limit(opts, :max_secret_bytes, @default_max_secret_bytes),
      do: :ok,
      else: error(:resource_limit)
  end

  defp validate_secret_limits(secrets, opts) when is_list(secrets) do
    max_count = limit(opts, :max_secrets, @default_max_secrets)
    max_bytes = limit(opts, :max_secret_bytes, @default_max_secret_bytes)
    validate_secret_list(secrets, 0, max_count, max_bytes)
  end

  defp validate_secret_limits(_secrets, _opts), do: error(:resource_limit)

  defp validate_secret_list([], _count, _max_count, _max_bytes), do: :ok

  defp validate_secret_list([secret | rest], count, max_count, max_bytes) do
    cond do
      count >= max_count -> error(:resource_limit)
      not is_binary(secret) -> error(:resource_limit)
      byte_size(secret) > max_bytes -> error(:resource_limit)
      true -> validate_secret_list(rest, count + 1, max_count, max_bytes)
    end
  end

  defp validate_secret_list(_improper_tail, _count, _max_count, _max_bytes),
    do: error(:invalid_secret)

  defp decode_base64(encoded) do
    case Base.decode64(encoded) do
      {:ok, decoded} when byte_size(decoded) > 0 -> {:ok, decoded}
      _ -> :error
    end
  end

  defp authenticate(raw_body, webhook_id, timestamp, keys, signatures) do
    signed_payload = webhook_id <> "." <> timestamp <> "." <> raw_body

    valid =
      Enum.reduce(keys, 0, fn key, key_result ->
        expected = :crypto.mac(:hmac, :sha256, key, signed_payload)

        signature_result =
          Enum.reduce(signatures, 0, fn signature, acc ->
            bor(acc, secure_equal(expected, signature))
          end)

        bor(key_result, signature_result)
      end)

    if valid == 1, do: :ok, else: error(:invalid_signature)
  end

  # `:crypto.hash_equals/2` is constant-time for equal-length binaries. A
  # different length is not a secret and cannot be a valid SHA-256 MAC.
  defp secure_equal(left, right) when byte_size(left) == byte_size(right) do
    if :crypto.hash_equals(left, right), do: 1, else: 0
  end

  defp secure_equal(_left, _right), do: 0

  defp decode_json(raw_body) do
    case Jason.decode(raw_body) do
      {:ok, %{} = payload} -> {:ok, payload}
      _ -> error(:invalid_json)
    end
  end

  defp decode_event(webhook_id, raw_body, payload) do
    case Event.from_payload(webhook_id, raw_body, payload) do
      {:ok, event} -> {:ok, event}
      {:error, _} -> error(:invalid_event)
    end
  end

  defp error(reason, opts \\ []) do
    {:error, VerificationError.exception(Keyword.merge([reason: reason], opts))}
  end
end
