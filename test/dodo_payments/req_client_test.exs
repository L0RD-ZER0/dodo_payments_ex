defmodule DodoPayments.ReqClientTest do
  use ExUnit.Case, async: true

  alias DodoPayments.HTTP
  alias DodoPayments.ReqClient

  defmodule Adapter do
    @moduledoc false

    def run(request) do
      request
      |> Req.Request.get_private(:dodo_payments_test_adapter)
      |> then(& &1.(request))
    end
  end

  test "finite limits halt a streaming adapter before remaining chunks are consumed" do
    parent = self()

    adapter = fn request ->
      response = Req.Response.new(status: 200, headers: [{"x-request-id", "req_stream"}])

      Enum.reduce_while(["abc", "def", "ghi"], {request, response}, fn chunk, acc ->
        send(parent, {:chunk, chunk})

        case request.into.({:data, chunk}, acc) do
          {:cont, next} -> {:cont, next}
          {:halt, next} -> {:halt, next}
        end
      end)
    end

    observe = fn {request, response} ->
      send(parent, :oversized_response_step_called)
      {request, response}
    end

    state =
      request_with_adapter(adapter)
      |> Req.Request.append_response_steps(consumer_observer: observe)
      |> ReqClient.from_req!()

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      max_body_bytes: 5
    }

    assert {:error,
            %HTTP.TransportError{
              reason: {:response_too_large, 5},
              partial_response: %{status: 200}
            }} = ReqClient.request(state, request)

    assert_received {:chunk, "abc"}
    assert_received {:chunk, "def"}
    refute_received {:chunk, "ghi"}
    refute_received :oversized_response_step_called
  end

  test "the final protection step strips credentials added by earlier Req steps" do
    parent = self()

    inject = fn request ->
      request
      |> Req.Request.put_header("cookie", "SENTINEL_COOKIE")
      |> Req.Request.put_header("x-api-key", "SENTINEL_KEY")
    end

    adapter = fn request ->
      send(parent, {:request, request})
      {request, Req.Response.new(status: 200, body: "{}")}
    end

    req =
      request_with_adapter(adapter, user_agent: "consumer/1.0")
      |> Req.Request.append_request_steps(inject_credentials: inject)

    state = ReqClient.from_req!(req)

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      headers: [{"authorization", "Bearer sdk-key"}, {"user-agent", DodoPayments.user_agent()}]
    }

    assert {:ok, %HTTP.Response{status: 200}} = ReqClient.request(state, request)
    assert_received {:request, protected}

    assert Req.Request.get_header(protected, "authorization") == ["Bearer sdk-key"]
    assert Req.Request.get_header(protected, "user-agent") == ["consumer/1.0"]
    assert Req.Request.get_header(protected, "cookie") == []
    assert Req.Request.get_header(protected, "x-api-key") == []
  end

  test "reusable Req state cannot replace the SDK protection step" do
    request =
      Req.new()
      |> Req.Request.append_request_steps(dodo_payments_protect: &Function.identity/1)

    assert {:error, %DodoPayments.Error.ConfigurationError{message: message}} =
             ReqClient.from_req(request)

    assert message =~ ":dodo_payments_protect"

    request =
      Req.new()
      |> Req.Request.append_response_steps(dodo_payments_finalize_response: &Function.identity/1)

    assert {:error, %DodoPayments.Error.ConfigurationError{message: message}} =
             ReqClient.from_req(request)

    assert message =~ ":dodo_payments_finalize_response"
  end

  test "credential-bearing reusable Req state is rejected consistently" do
    for header <- DodoPayments.Redaction.credential_headers() do
      request = Req.new(headers: [{header, "SENTINEL"}])

      assert {:error, %DodoPayments.Error.ConfigurationError{}} =
               ReqClient.from_req(request)
    end

    assert {:error, %DodoPayments.Error.ConfigurationError{}} =
             ReqClient.from_req(Req.new(auth: {:bearer, "SENTINEL"}))
  end

  test "AWS signing, cache, and security-token state is rejected without echoing values" do
    for req <- [
          Req.new(aws_sigv4: [access_key_id: "ACCESS_SENTINEL", secret_access_key: "SECRET"]),
          Req.new(cache: true),
          Req.new(headers: [{"x-amz-security-token", "SESSION_SENTINEL"}])
        ] do
      assert {:error, %DodoPayments.Error.ConfigurationError{message: message}} =
               ReqClient.from_req(req)

      refute message =~ "SENTINEL"
    end
  end

  test "ReqClient inspection never exposes wrapped request options" do
    client = %ReqClient{request: Req.new(aws_sigv4: [secret_access_key: "SESSION_SENTINEL"])}
    rendered = inspect(client)

    refute rendered =~ "SESSION_SENTINEL"
    assert rendered =~ "request_state_redacted"
  end

  test "high-byte request headers are rejected before adapter dispatch" do
    parent = self()

    adapter = fn _request ->
      send(parent, :dispatched)
      {Req.Request.new(), Req.Response.new()}
    end

    state = adapter |> request_with_adapter() |> ReqClient.from_req!()

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      headers: [{"x-sentinel", <<255>>}]
    }

    assert {:error, %DodoPayments.HTTP.TransportError{delivery: :not_sent}} =
             ReqClient.request(state, request)

    refute_received :dispatched
  end

  test "mixed-case raw credential and compression headers are rejected" do
    for header <- [
          "Authorization",
          "Cookie",
          "X-Api-Key",
          "Accept-Encoding",
          "x_api_key",
          :proxy_authorization,
          :accept_encoding
        ] do
      request = Req.Request.new(headers: [{header, "SENTINEL"}])

      assert {:error, %DodoPayments.Error.ConfigurationError{}} =
               ReqClient.from_req(request)
    end
  end

  test "final protection strips mixed-case headers injected by request steps" do
    parent = self()

    inject = fn request ->
      headers =
        request.headers
        |> Map.put("Authorization", ["Bearer SENTINEL"])
        |> Map.put("Accept-Encoding", ["gzip"])
        |> Map.put(:x_api_key, ["SENTINEL_ATOM_KEY"])

      %{request | headers: headers}
    end

    adapter = fn request ->
      send(parent, {:protected_headers, request.headers})
      {request, Req.Response.new(status: 200, body: "{}")}
    end

    state =
      request_with_adapter(adapter)
      |> Req.Request.append_request_steps(inject_mixed_case: inject)
      |> ReqClient.from_req!()

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      headers: [{"authorization", "Bearer sdk-key"}]
    }

    assert {:ok, %HTTP.Response{status: 200}} = ReqClient.request(state, request)
    assert_received {:protected_headers, headers}
    assert headers["authorization"] == ["Bearer sdk-key"]

    refute Enum.any?(Map.keys(headers), fn name ->
             DodoPayments.Redaction.header_name(name) in [
               "accept-encoding",
               "authorization",
               "x-api-key"
             ] and name != "authorization"
           end)
  end

  test "SDK and explicitly configured user agents have predictable precedence" do
    parent = self()

    adapter = fn request ->
      send(parent, {:user_agent, request.headers["user-agent"]})
      {request, Req.Response.new(status: 200, body: "{}")}
    end

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      headers: [{"user-agent", DodoPayments.user_agent()}]
    }

    default = adapter |> request_with_adapter() |> ReqClient.from_req!()
    assert {:ok, %HTTP.Response{}} = ReqClient.request(default, request)
    assert_received {:user_agent, [sdk_user_agent]}
    assert sdk_user_agent == DodoPayments.user_agent()

    custom = adapter |> request_with_adapter(user_agent: "consumer/1.0") |> ReqClient.from_req!()
    assert {:ok, %HTTP.Response{}} = ReqClient.request(custom, request)
    assert_received {:user_agent, ["consumer/1.0"]}
  end

  test "duplicate request header values reach the Req adapter" do
    parent = self()

    adapter = fn request ->
      send(parent, {:duplicate_header, request.headers["x-many"]})
      {request, Req.Response.new(status: 200, body: "{}")}
    end

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      headers: [{"x-many", "a"}, {"x-many", "b"}]
    }

    state = adapter |> request_with_adapter() |> ReqClient.from_req!()
    assert {:ok, %HTTP.Response{}} = ReqClient.request(state, request)
    assert_received {:duplicate_header, ["a", "b"]}
  end

  test "the Finch streaming path preserves duplicate response headers" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listener)

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 1_000)

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\n",
            "content-length: 2\r\n",
            "set-cookie: first=1\r\n",
            "set-cookie: second=2\r\n",
            "connection: close\r\n\r\n{}"
          ])

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(server), do: Process.exit(server, :kill)
    end)

    request = %HTTP.Request{
      method: :get,
      url: "http://127.0.0.1:#{port}/duplicate-headers",
      timeout: 1_000
    }

    assert {:ok, %HTTP.Response{headers: headers, body: "{}"}} =
             ReqClient.request(ReqClient.new!(), request)

    assert Enum.filter(headers, fn {name, _value} -> name == "set-cookie" end) == [
             {"set-cookie", "first=1"},
             {"set-cookie", "second=2"}
           ]
  end

  test "compressed reusable Req state is rejected instead of returning undecodable bytes" do
    assert {:error, %DodoPayments.Error.ConfigurationError{message: compressed_message}} =
             ReqClient.from_req(Req.new(compressed: true))

    assert compressed_message =~ ":compressed"

    assert {:error, %DodoPayments.Error.ConfigurationError{message: header_message}} =
             ReqClient.from_req(Req.new(headers: [{"accept-encoding", "gzip"}]))

    assert header_message =~ "accept-encoding"

    for header <- ["content-length", "transfer-encoding", "host"] do
      assert {:error, %DodoPayments.Error.ConfigurationError{message: message}} =
               ReqClient.from_req(Req.new(headers: [{header, "SENTINEL"}]))

      assert message =~ header
    end

    into_request = Req.new(into: [])

    assert {:error, %DodoPayments.Error.ConfigurationError{message: into_message}} =
             ReqClient.from_req(into_request)

    assert into_message =~ ":into"

    base_request = Req.new()

    output_request = %{
      base_request
      | options: Map.put(base_request.options, :output, "/tmp/dodo-response")
    }

    assert {:error, %DodoPayments.Error.ConfigurationError{message: output_message}} =
             ReqClient.from_req(output_request)

    assert output_message =~ ":output"
  end

  test "consumer response steps receive a finalized binary body" do
    parent = self()

    adapter = fn request ->
      response = Req.Response.new(status: 200)
      request.into.({:data, ~s({"product_id":"pdt_1"})}, {request, response}) |> elem(1)
    end

    observe = fn {request, response} ->
      send(parent, {:consumer_body, response.body})
      {request, response}
    end

    inject_observer = fn request ->
      Req.Request.prepend_response_steps(request, injected_observer: observe)
    end

    state =
      request_with_adapter(adapter)
      |> Req.Request.append_request_steps(inject_observer: inject_observer)
      |> Req.Request.append_response_steps(consumer_observer: observe)
      |> ReqClient.from_req!()

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1"
    }

    assert {:ok, %HTTP.Response{body: ~s({"product_id":"pdt_1"})}} =
             ReqClient.request(state, request)

    assert_received {:consumer_body, ~s({"product_id":"pdt_1"})}
    assert_received {:consumer_body, ~s({"product_id":"pdt_1"})}
  end

  test "the final protection step strips accept-encoding added by request options or steps" do
    parent = self()

    inject = fn request -> Req.Request.put_header(request, "accept-encoding", "gzip") end

    adapter = fn request ->
      send(parent, {
        :compression,
        Req.Request.get_header(request, "accept-encoding"),
        Req.Request.get_option(request, :compressed)
      })

      {request, Req.Response.new(status: 200, body: "{}")}
    end

    req =
      request_with_adapter(adapter)
      |> Req.Request.append_request_steps(inject_compression: inject)

    request = %HTTP.Request{
      method: :get,
      url: "https://dodo.invalid/products/pdt_1",
      headers: [{"accept-encoding", "gzip"}]
    }

    assert {:ok, %HTTP.Response{status: 200}} =
             ReqClient.request(ReqClient.from_req!(req), request)

    assert_received {:compression, [], false}
  end

  test "request and response inspection share the canonical header policy" do
    headers =
      Enum.map(DodoPayments.Redaction.credential_headers(), &{&1, "SENTINEL"}) ++
        [{:x_api_key, "SENTINEL"}, {"proxy_authorization", "SENTINEL"}]

    request = %HTTP.Request{method: :get, url: "https://dodo.invalid", headers: headers}
    response = %HTTP.Response{status: 200, headers: [{"set-cookie", "SENTINEL"}], body: ""}

    refute inspect(request) =~ "SENTINEL"
    refute inspect(response) =~ "SENTINEL"
  end

  test "bodyless operations remain bodyless on the Req request" do
    parent = self()

    adapter = fn request ->
      send(parent, {:body, request.body, Req.Request.get_header(request, "content-type")})
      {request, Req.Response.new(status: 204, body: "")}
    end

    state = adapter |> request_with_adapter() |> ReqClient.from_req!()

    request = %HTTP.Request{
      method: :delete,
      url: "https://dodo.invalid/products/pdt_1",
      body: nil
    }

    assert {:ok, %HTTP.Response{status: 204}} = ReqClient.request(state, request)
    assert_received {:body, nil, []}
  end

  defp request_with_adapter(adapter, options \\ []) do
    options
    |> Keyword.put(:adapter, Adapter)
    |> Req.new()
    |> Req.Request.put_private(:dodo_payments_test_adapter, adapter)
  end
end
