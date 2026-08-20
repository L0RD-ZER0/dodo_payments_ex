defmodule DodoPayments.ReqClient do
  @moduledoc """
  First-class `Req` implementation of `DodoPayments.ClientModule`.

  The state wraps a reusable, credential-free `%Req.Request{}`. Its plugins,
  adapter, Finch pool, and non-protected options are preserved. Dodo Payments
  credentials are resolved by the request engine and are never retained in this
  state.

  Each callback invocation disables Req retries and redirects and performs one
  request. A final request step protects the absolute URL, method, body,
  authorization, response mode, and timeout after caller-provided request steps
  have run. Finite response limits are enforced while Finch streams chunks, before
  the complete body can be buffered. Response compression is disabled because
  Req's decompression step requires a fully buffered body. Caller-provided steps
  remain trusted application code. The internal `:dodo_payments_protect` step
  name is reserved and rejected when wrapping an existing request.

  Wrapped state must also be credential-free and may not enable Req cache or AWS
  signing behavior. User-agent precedence is reusable Req configuration, then a
  request-local header, then the SDK default.
  """

  @behaviour DodoPayments.ClientModule

  alias DodoPayments.Error.ConfigurationError
  alias DodoPayments.HTTP
  alias DodoPayments.HTTP.TransportError
  alias DodoPayments.Request.Preparation

  @protect_step :dodo_payments_protect
  @finalize_response_step :dodo_payments_finalize_response
  @response_error_private :dodo_payments_response_error

  @enforce_keys [:request]
  defstruct [:request]

  @opaque t :: %__MODULE__{request: Req.Request.t()}

  @doc "Creates adapter state around a new Req request."
  @spec new(keyword()) :: {:ok, t()} | {:error, ConfigurationError.t()}
  def new(opts \\ []) do
    if Keyword.keyword?(opts) do
      try do
        opts
        |> Req.new()
        |> from_req()
      rescue
        exception ->
          configuration_error("invalid Req options", exception, __STACKTRACE__)
      end
    else
      configuration_error("Req options must be a keyword list")
    end
  end

  @doc "Creates adapter state around a new Req request or raises a configuration error."
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    case new(opts) do
      {:ok, state} -> state
      {:error, exception} -> raise exception
    end
  end

  @doc "Wraps an existing credential-free Req request without rebuilding it."
  @spec from_req(Req.Request.t()) :: {:ok, t()} | {:error, ConfigurationError.t()}
  def from_req(%Req.Request{} = request) do
    with :ok <- validate_reserved_steps(request),
         :ok <- validate_credentials(request),
         :ok <- validate_credential_options(request),
         :ok <- validate_transport_options(request),
         :ok <- validate_base_header_values(request),
         :ok <- validate_response_sink(request),
         :ok <- validate_connection_options(request) do
      {:ok, %__MODULE__{request: request}}
    end
  end

  def from_req(_request), do: configuration_error("expected a %Req.Request{}")

  defp validate_reserved_steps(request) do
    cond do
      Keyword.has_key?(request.request_steps, @protect_step) ->
        configuration_error(
          "ReqClient state must not define the reserved request step #{inspect(@protect_step)}"
        )

      Keyword.has_key?(request.response_steps, @finalize_response_step) ->
        configuration_error(
          "ReqClient state must not define the reserved response step #{inspect(@finalize_response_step)}"
        )

      true ->
        :ok
    end
  end

  defp validate_credentials(request) do
    case Enum.find(request.headers, fn {name, _values} ->
           DodoPayments.Redaction.credential_header?(name)
         end) do
      nil ->
        if Req.Request.get_option(request, :auth) == nil,
          do: :ok,
          else: configuration_error("ReqClient state must not contain Req's :auth option")

      {header, _values} ->
        configuration_error(
          "ReqClient state must not contain credential header #{DodoPayments.Redaction.header_name(header)}"
        )
    end
  end

  # Req's authentication, cache, and AWS signing steps can add credentials or
  # return a response without contacting the Dodo endpoint.  A wrapped request
  # is deliberately a safe, reusable transport template, so those stateful
  # options are rejected instead of being silently overridden later.
  defp validate_credential_options(request) do
    cond do
      option_present?(request, :aws_sigv4) ->
        configuration_error("ReqClient state must not contain Req's :aws_sigv4 option")

      option_present?(request, :cache) or option_present?(request, :cache_dir) ->
        configuration_error("ReqClient state must not contain Req's cache options")

      credential_option?(request.options) ->
        configuration_error("ReqClient state must not contain signing or credential options")

      proxy_credential_header?(request) ->
        configuration_error("ReqClient state must not contain credential proxy headers")

      true ->
        :ok
    end
  end

  defp option_present?(request, key) do
    Map.has_key?(request.options, key) and not is_nil(Req.Request.get_option(request, key))
  end

  defp credential_option?(value) when is_map(value) do
    Enum.any?(value, fn {key, nested} ->
      credential_option_key?(key) or credential_option?(nested)
    end)
  end

  defp credential_option?(value) when is_list(value) do
    Enum.any?(value, fn
      {key, nested} -> credential_option_key?(key) or credential_option?(nested)
      nested when is_map(nested) or is_list(nested) -> credential_option?(nested)
      _ -> false
    end)
  end

  defp credential_option?(_value), do: false

  defp credential_option_key?(key) when is_atom(key) or is_binary(key) do
    normalized = key |> to_string() |> String.downcase() |> String.replace("-", "_")

    normalized in [
      "access_key_id",
      "secret_access_key",
      "session_token",
      "security_token",
      "credential",
      "credentials",
      "signing_key",
      "signature",
      "signing"
    ]
  end

  defp credential_option_key?(_key), do: false

  defp proxy_credential_header?(request) do
    case Req.Request.get_option(request, :connect_options) do
      options when is_list(options) ->
        case Keyword.get(options, :proxy_headers, []) do
          headers when is_list(headers) ->
            Enum.any?(headers, fn
              {name, _value} -> DodoPayments.Redaction.credential_header?(name)
              _ -> false
            end)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp validate_transport_options(request) do
    cond do
      Req.Request.get_option(request, :compressed, false) == true ->
        configuration_error(
          "ReqClient does not support Req's :compressed option because response limits are enforced while streaming"
        )

      header = retained_header(request, Preparation.transport_owned_headers()) ->
        configuration_error(
          "ReqClient state must not contain transport-owned header #{inspect(header)}"
        )

      true ->
        :ok
    end
  end

  defp validate_base_header_values(request) do
    invalid? =
      Enum.any?(Req.get_headers_list(request), fn {_name, value} ->
        not encodable_header_value?(value)
      end) or
        case Req.Request.get_option(request, :user_agent) do
          nil -> false
          value -> not encodable_header_value?(to_string(value))
        end

    if invalid?,
      do: configuration_error("ReqClient state contains a header value that cannot be encoded"),
      else: :ok
  end

  defp validate_response_sink(request) do
    cond do
      request.into != nil ->
        configuration_error(
          "ReqClient state must not define :into because the SDK installs its bounded response collector"
        )

      Req.Request.get_option(request, :output) != nil ->
        configuration_error(
          "ReqClient state must not use Req's :output option because the SDK consumes the response body"
        )

      true ->
        :ok
    end
  end

  defp validate_connection_options(request) do
    if Req.Request.get_option(request, :finch) != nil and
         Req.Request.get_option(request, :connect_options) != nil,
       do: configuration_error("ReqClient state cannot combine :finch and :connect_options"),
       else: :ok
  end

  defp retained_header(request, names),
    do: Enum.find(names, &(header_values(request, &1) != []))

  @doc "Wraps an existing credential-free Req request or raises a configuration error."
  @spec from_req!(Req.Request.t()) :: t()
  def from_req!(request) do
    case from_req(request) do
      {:ok, state} -> state
      {:error, exception} -> raise exception
    end
  end

  @impl true
  def request(%__MODULE__{request: base}, %HTTP.Request{} = request) do
    case validate_wire_request(request) do
      :ok ->
        configured_user_agent = configured_user_agent(base)
        protected = fn req -> protect(req, request, configured_user_agent) end

        req =
          base
          |> Req.merge(retry: false, redirect: false, decode_body: false)
          |> Req.Request.append_request_steps([{@protect_step, protected}])

        try do
          case Req.request(req) do
            {:ok, response} -> normalize_response(response, request.max_body_bytes)
            {:error, reason} -> {:error, transport_error(reason)}
          end
        rescue
          exception -> {:error, transport_error(exception)}
        catch
          :exit, reason -> {:error, transport_error({:exit, reason})}
        end

      {:error, reason} ->
        {:error, %TransportError{reason: reason, delivery: :not_sent}}
    end
  end

  defp validate_wire_request(%HTTP.Request{headers: headers}) do
    case Enum.find(headers, fn {_name, value} -> not encodable_header_value?(value) end) do
      {name, _value} -> {:error, {:invalid_header, DodoPayments.Redaction.header_name(name)}}
      nil -> :ok
    end
  end

  defp encodable_header_value?(value) when is_binary(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.all?(fn
      9 -> true
      byte when byte in 32..126 -> true
      _ -> false
    end)
  end

  defp encodable_header_value?(_value), do: false

  defp protect(req, request, configured_user_agent) do
    headers =
      request.headers
      |> normalize_request_headers()
      |> Enum.reject(&credential_request_header?/1)
      |> maybe_replace_user_agent(configured_user_agent)

    request_options = protected_request_options(req, request.timeout)

    req
    |> delete_credential_headers()
    |> Req.Request.delete_option(:auth)
    |> Req.Request.delete_option(:output)
    |> delete_headers(["user-agent" | Preparation.transport_owned_headers()])
    |> put_headers(headers)
    |> delete_headers(Preparation.transport_owned_headers())
    |> Req.Request.merge_options(request_options)
    |> ensure_finalize_response_step()
    |> put_protected_fields(request)
  end

  defp credential_request_header?({name, value}) do
    if name == "authorization",
      do: String.starts_with?(value, "AWS4-HMAC-SHA256"),
      else: DodoPayments.Redaction.credential_header?(name)
  end

  defp put_protected_fields(%Req.Request{} = req, %HTTP.Request{} = request) do
    %Req.Request{
      req
      | method: request.method,
        url: URI.parse(to_string(request.url)),
        body: request.body,
        into: response_collector(request.max_body_bytes),
        async: nil
    }
  end

  defp response_collector(limit) do
    fn {:data, chunk}, {req, response} ->
      {size, chunks} = response_accumulator(response.body)
      next_size = size + byte_size(chunk)

      if limit != :infinity and next_size > limit do
        {:halt, {req, %{response | body: {:dodo_response_too_large, limit}}}}
      else
        {:cont, {req, %{response | body: {:dodo_response_body, next_size, [chunk | chunks]}}}}
      end
    end
  end

  defp response_accumulator({:dodo_response_body, size, chunks}), do: {size, chunks}
  defp response_accumulator(_body), do: {0, []}

  defp ensure_finalize_response_step(%Req.Request{} = request) do
    remaining = Keyword.delete(request.response_steps, @finalize_response_step)
    %{request | response_steps: [{@finalize_response_step, &finalize_response/1} | remaining]}
  end

  defp finalize_response({request, response}) do
    case response_body(response.body) do
      {:ok, body} ->
        {request, %{response | body: body}}

      {:error, reason} ->
        response =
          response
          |> Req.Response.put_private(@response_error_private, reason)
          |> Map.put(:body, "")

        {%{request | halted: true}, response}
    end
  end

  defp protected_request_options(req, timeout) do
    options = [
      retry: false,
      redirect: false,
      decode_body: false,
      compressed: false,
      http_errors: :return,
      receive_timeout: timeout,
      pool_timeout: timeout
    ]

    if Req.Request.get_option(req, :finch) == nil do
      Keyword.put(options, :connect_options, merge_connect_timeout(req, timeout))
    else
      options
    end
  end

  defp merge_connect_timeout(req, timeout) do
    case Req.Request.get_option(req, :connect_options) do
      options when is_list(options) -> Keyword.put(options, :timeout, timeout)
      _ -> [timeout: timeout]
    end
  end

  defp delete_credential_headers(req) do
    headers =
      Map.reject(req.headers, fn {name, _values} ->
        DodoPayments.Redaction.credential_header?(name)
      end)

    %{req | headers: headers}
  end

  defp delete_headers(%Req.Request{} = req, names) do
    names = MapSet.new(names, &String.downcase/1)

    headers =
      Map.reject(req.headers, fn {name, _values} ->
        DodoPayments.Redaction.header_name(name) in names
      end)

    %{req | headers: headers}
  end

  defp put_headers(%Req.Request{} = req, headers) do
    grouped =
      Enum.reduce(headers, %{}, fn {name, value}, acc ->
        Map.update(acc, name, [value], &(&1 ++ [value]))
      end)

    req = delete_headers(req, Map.keys(grouped))
    %{req | headers: Map.merge(req.headers, grouped)}
  end

  defp configured_user_agent(%Req.Request{} = req) do
    case header_values(req, "user-agent") do
      [] -> Req.Request.get_option(req, :user_agent)
      values -> List.last(values)
    end
  end

  defp maybe_replace_user_agent(headers, nil), do: headers

  defp maybe_replace_user_agent(headers, user_agent) do
    [{"user-agent", to_string(user_agent)} | Enum.reject(headers, &(elem(&1, 0) == "user-agent"))]
  end

  defp header_values(%Req.Request{} = req, wanted) do
    wanted = String.downcase(wanted)

    Enum.flat_map(req.headers, fn {name, values} ->
      if DodoPayments.Redaction.header_name(name) == wanted, do: List.wrap(values), else: []
    end)
  end

  defp normalize_request_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {String.downcase(to_string(name)), to_string(value)}
    end)
  end

  defp normalize_response(%Req.Response{} = response, max_body_bytes) do
    result =
      case Req.Response.get_private(response, @response_error_private) do
        nil -> response_body(response.body)
        reason -> {:error, reason}
      end

    case result do
      {:error, {:response_too_large, limit}} ->
        {:error,
         %TransportError{
           reason: {:response_too_large, limit},
           delivery: :unknown,
           partial_response: %{status: response.status, headers: Req.get_headers_list(response)}
         }}

      {:ok, body} ->
        headers = Req.get_headers_list(response)

        if max_body_bytes != :infinity and byte_size(body) > max_body_bytes do
          {:error,
           %TransportError{
             reason: {:response_too_large, max_body_bytes},
             delivery: :unknown,
             partial_response: %{status: response.status, headers: headers}
           }}
        else
          {:ok,
           %HTTP.Response{
             status: response.status,
             headers: headers,
             body: body
           }}
        end

      {:error, reason} ->
        {:error, %TransportError{reason: reason, delivery: :unknown}}
    end
  end

  defp response_body(nil), do: {:ok, ""}

  defp response_body({:dodo_response_too_large, limit}),
    do: {:error, {:response_too_large, limit}}

  defp response_body({:dodo_response_body, _size, chunks}) do
    {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp response_body(body) when is_binary(body), do: {:ok, body}

  defp response_body(body) when is_list(body) do
    try do
      {:ok, IO.iodata_to_binary(body)}
    rescue
      _ -> {:error, :non_binary_response_body}
    end
  end

  defp response_body(_body), do: {:error, :non_binary_response_body}

  defp transport_error(reason) do
    %TransportError{reason: reason, delivery: delivery(reason)}
  end

  # Only failures that positively occur before a connection is established are
  # marked not-sent. Everything else deliberately remains unknown.
  defp delivery(%Req.TransportError{reason: reason}), do: delivery(reason)
  defp delivery(:nxdomain), do: :not_sent
  defp delivery(:econnrefused), do: :not_sent
  defp delivery({:failed_connect, _}), do: :not_sent
  defp delivery({:failed_connect, _, _}), do: :not_sent
  defp delivery(_), do: :unknown

  defp configuration_error(message, cause \\ nil, stacktrace \\ []) do
    {:error, ConfigurationError.exception(message: message, cause: cause, stacktrace: stacktrace)}
  end
end

defimpl Inspect, for: DodoPayments.ReqClient do
  import Inspect.Algebra

  # Req's own inspector redacts authorization but intentionally retains most
  # option values.  The SDK state is opaque and may contain plugin metadata,
  # therefore never delegate inspection of the wrapped request wholesale.
  def inspect(_client, opts) do
    concat(["#DodoPayments.ReqClient<", to_doc(:request_state_redacted, opts), ">"])
  end
end
