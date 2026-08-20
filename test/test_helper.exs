ExUnit.start()

defmodule DodoPayments.TestClient do
  @moduledoc false
  @behaviour DodoPayments.ClientModule

  @impl true
  def request(fun, request) when is_function(fun, 1), do: fun.(request)
end

defmodule DodoPayments.TestSupport do
  @moduledoc false
  alias DodoPayments.HTTP

  def client(fun, opts \\ []) do
    defaults = [
      environment: :custom,
      base_url: "https://dodo.invalid",
      api_key: "sk_test",
      client: {DodoPayments.TestClient, fun},
      max_attempts: 3,
      retry_base_delay: 0,
      retry_max_delay: 0
    ]

    DodoPayments.client!(Keyword.merge(defaults, opts))
  end

  def response(status, body, headers \\ []) do
    {:ok,
     %HTTP.Response{
       status: status,
       headers: headers,
       body: body
     }}
  end

  def transport(reason, delivery \\ :unknown, partial_response \\ nil) do
    {:error,
     %HTTP.TransportError{
       reason: reason,
       delivery: delivery,
       partial_response: partial_response
     }}
  end
end
