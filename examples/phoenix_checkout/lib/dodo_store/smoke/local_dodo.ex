defmodule DodoStore.Smoke.LocalDodo do
  @moduledoc """
  In-memory Dodo boundary used only by the `local` smoke profile.

  SDK requests are routed to an in-process Plug function, so this module cannot
  contact the test or live Dodo hosts. It stores the final remote resource state
  separately from webhook delivery order, allowing reconciliation code to read
  current state after deliberately out-of-order notifications.
  """

  use Agent

  alias DodoStore.Smoke.Lifecycle

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    agent_opts = Keyword.take(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    Agent.start_link(
      fn -> %{checkouts: %{}, payments: %{}, refunds: %{}, disputes: %{}} end,
      agent_opts
    )
  end

  @spec client(GenServer.server()) :: DodoPayments.Client.t()
  def client(server) do
    DodoPayments.client!(
      environment: :test,
      api_key: "local-smoke-placeholder",
      max_attempts: 1,
      req: Req.new(plug: fn conn -> call(server, conn) end)
    )
  end

  @doc "Builds a client provider suitable for a supervised outbox worker."
  @spec client_from_name(GenServer.server()) :: (-> DodoPayments.Client.t())
  def client_from_name(server), do: fn -> client(server) end

  @spec register_lifecycle(pid(), Lifecycle.t()) :: :ok
  def register_lifecycle(server, %Lifecycle{} = scenario) do
    Agent.update(server, fn state ->
      payment = %{
        "payment_id" => scenario.payment_id,
        "status" => payment_status(scenario.outcome),
        "metadata" => %{
          "example_order_id" => scenario.order_id,
          "example_pattern" => scenario.pattern
        }
      }

      state = put_in(state, [:payments, scenario.payment_id], payment)

      state =
        if scenario.refund_id do
          refund = %{
            "refund_id" => scenario.refund_id,
            "payment_id" => scenario.payment_id,
            "status" => "succeeded"
          }

          put_in(state, [:refunds, scenario.refund_id], refund)
        else
          state
        end

      if scenario.dispute_id do
        dispute = %{
          "dispute_id" => scenario.dispute_id,
          "payment_id" => scenario.payment_id,
          "dispute_status" => "dispute_opened"
        }

        put_in(state, [:disputes, scenario.dispute_id], dispute)
      else
        state
      end
    end)
  end

  @spec payment(pid(), String.t()) :: map() | nil
  def payment(server, payment_id), do: Agent.get(server, &get_in(&1, [:payments, payment_id]))

  @spec checkout(pid(), String.t()) :: map() | nil
  def checkout(server, session_id),
    do: Agent.get(server, &get_in(&1, [:checkouts, session_id]))

  @spec call(pid(), Plug.Conn.t()) :: Plug.Conn.t()
  def call(server, %Plug.Conn{method: "POST", request_path: "/checkouts"} = conn) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, params} when is_map(params) <- Jason.decode(body) do
      metadata = Map.get(params, "metadata", %{})
      order_id = Map.get(metadata, "example_order_id", "unknown")
      session_id = "cks-" <> token(order_id)

      Agent.update(server, fn state ->
        put_in(state, [:checkouts, session_id], %{
          "session_id" => session_id,
          "order_id" => order_id,
          "product_cart" => Map.get(params, "product_cart", []),
          "allowed_payment_method_types" => Map.get(params, "allowed_payment_method_types")
        })
      end)

      Req.Test.json(conn, %{
        "session_id" => session_id,
        "checkout_url" => "https://local-checkout.invalid/session/#{session_id}"
      })
    else
      _error -> conn |> Plug.Conn.send_resp(400, "invalid checkout") |> Plug.Conn.halt()
    end
  end

  def call(server, %Plug.Conn{method: "GET"} = conn) do
    case resource_for_path(server, conn.request_path) do
      nil -> conn |> Plug.Conn.send_resp(404, "not found") |> Plug.Conn.halt()
      resource -> Req.Test.json(conn, resource)
    end
  end

  def call(_server, conn), do: conn |> Plug.Conn.send_resp(404, "not found") |> Plug.Conn.halt()

  defp resource_for_path(server, path) do
    case String.split(path, "/", trim: true) do
      ["payments", id] -> Agent.get(server, &get_in(&1, [:payments, id]))
      ["refunds", id] -> Agent.get(server, &get_in(&1, [:refunds, id]))
      ["disputes", id] -> Agent.get(server, &get_in(&1, [:disputes, id]))
      ["checkouts", id] -> Agent.get(server, &get_in(&1, [:checkouts, id]))
      _other -> nil
    end
  end

  defp payment_status(outcome)
       when outcome in [:accepted, :refunded, :disputed, :processing_accepted],
       do: "succeeded"

  defp payment_status(outcome) when outcome in [:rejected, :processing_rejected], do: "failed"
  defp payment_status(:cancelled), do: "cancelled"

  defp token(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, 9)
    |> Base.url_encode64(padding: false)
  end
end
