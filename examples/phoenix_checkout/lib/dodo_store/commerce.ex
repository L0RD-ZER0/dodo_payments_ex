defmodule DodoStore.Commerce do
  @moduledoc """
  Minimal application-owned order, entitlement, and subscription state.

  Dodo owns payment state. This module owns the local expectations that make a
  payment safe to apply: which order was created, its exact cart, the account it
  belongs to, and whether an observed payment has already been consumed.
  """

  import Ecto.Query

  alias DodoStore.Commerce.{CreditGrant, Order, OrderItem, Subscription}
  alias DodoStore.Repo
  alias Ecto.Multi

  @active_states ~w(active trialing)

  @spec expect_order(String.t(), 1..10, [map()], keyword()) ::
          {:ok, Order.t()} | {:error, term()}
  def expect_order(order_id, pattern, cart, opts \\ []) do
    normalized = normalize_cart(cart)

    attrs = %{
      order_id: order_id,
      pattern: pattern,
      account_id: opts[:account_id],
      status: "checkout_pending",
      expected_cart: normalized,
      credits: opts[:credits]
    }

    with :ok <- validate_expectation(attrs) do
      persist_expected_order(attrs, normalized)
    end
  end

  defp persist_expected_order(attrs, normalized) do
    Multi.new()
    |> Multi.insert(:order, Order.changeset(%Order{}, attrs))
    |> Multi.run(:items, fn repo, %{order: order} ->
      normalized
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, items} ->
        item_attrs = %{
          order_id: order.id,
          line_key: Integer.to_string(index),
          product_id: item["product_id"],
          quantity: item["quantity"],
          status: "awaiting_payment"
        }

        case repo.insert(OrderItem.changeset(%OrderItem{}, item_attrs)) do
          {:ok, inserted} -> {:cont, {:ok, [inserted | items]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, order}
      {:error, :order, changeset, _changes} -> resolve_duplicate_order(changeset, attrs)
      {:error, _step, error, _changes} -> {:error, error}
    end
  end

  @spec mark_checkout_created(String.t(), String.t()) :: {:ok, Order.t()} | {:error, term()}
  def mark_checkout_created(order_id, session_id) do
    change_order(order_id, status: "checkout_created", checkout_session_id: session_id)
  end

  @spec mark_checkout_failed(String.t()) :: {:ok, Order.t()} | {:error, term()}
  def mark_checkout_failed(order_id), do: change_order(order_id, status: "checkout_failed")

  @doc "Applies a payment only to the exact, pre-existing local order expectation."
  @spec fulfill_payment(map(), String.t()) ::
          {:ok, Order.t(), :accepted | :duplicate} | {:error, term()}
  def fulfill_payment(data, webhook_id) do
    metadata = string_map(data["metadata"] || %{})
    order_id = metadata["example_order_id"]
    pattern = parse_integer(metadata["example_pattern"])
    payment_id = data["payment_id"]

    Repo.transaction(fn ->
      order = order_id && Repo.get_by(Order, order_id: order_id)

      with %Order{} <- order,
           true <- is_binary(payment_id) or {:error, :missing_payment_id},
           true <- pattern == order.pattern or {:error, :pattern_mismatch},
           :ok <- account_matches(order.account_id, metadata["example_account_id"]),
           :ok <- cart_hash_matches(order.expected_cart, metadata["example_cart_hash"]),
           :ok <- cart_matches(order.expected_cart, payment_cart(data)),
           :ok <- payment_available(order, payment_id) do
        if order.payment_id == payment_id do
          {order, :duplicate}
        else
          now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

          {_, _} =
            Repo.update_all(
              from(item in OrderItem,
                where: item.order_id == ^order.id and item.status != "fulfilled"
              ),
              set: [status: "fulfilled", fulfilled_at: now, updated_at: now]
            )

          {:ok, fulfilled} =
            order
            |> Order.changeset(%{status: "fulfilled", payment_id: payment_id})
            |> Repo.update()

          :ok = maybe_grant_prepaid_credits(fulfilled, webhook_id)
          {fulfilled, :accepted}
        end
      else
        nil -> Repo.rollback(:unknown_order)
        {:error, reason} -> Repo.rollback(reason)
        false -> Repo.rollback(:invalid_payment)
      end
    end)
    |> case do
      {:ok, {order, disposition}} -> {:ok, order, disposition}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stores the latest subscription retrieved from Dodo, never webhook arrival state."
  @spec apply_subscription_snapshot(DodoPayments.Subscription.t() | map()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def apply_subscription_snapshot(snapshot) do
    data = if is_struct(snapshot), do: Map.from_struct(snapshot), else: snapshot
    metadata = string_map(value(data, :metadata) || %{})
    subscription_id = value(data, :subscription_id)
    pattern = parse_integer(metadata["example_pattern"])
    account_id = metadata["example_account_id"]
    status = to_string(value(data, :status) || "unknown")
    period = period_from_snapshot(data)
    credits = parse_integer(metadata["example_credits_per_period"])
    on_demand? = value(data, :on_demand) == true

    attrs = %{
      subscription_id: subscription_id,
      account_id: account_id,
      pattern: pattern,
      status: status,
      mandate_ready: pattern == 6 and on_demand? and status in @active_states,
      period: period,
      period_ends_at: parse_datetime(value(data, :next_billing_date)),
      credits_per_period: credits
    }

    with true <- is_binary(subscription_id) or {:error, :missing_subscription_id},
         true <- is_binary(account_id) or {:error, :missing_account_metadata},
         true <- pattern in [2, 6, 9] or {:error, :invalid_pattern},
         :ok <- validate_period_allowance(pattern, period, credits),
         :ok <- validate_subscription_identity(attrs) do
      persist_subscription_snapshot(attrs)
    else
      {:error, _reason} = error -> error
    end
  end

  @spec active_subscription(String.t(), 2 | 6 | 9) ::
          {:ok, Subscription.t()} | {:error, :inactive_subscription}
  def active_subscription(account_id, pattern) do
    query =
      from(subscription in Subscription,
        where:
          subscription.account_id == ^account_id and subscription.pattern == ^pattern and
            subscription.status in ^@active_states,
        order_by: [desc: subscription.updated_at],
        limit: 1
      )

    case Repo.one(query) do
      %Subscription{} = subscription -> {:ok, subscription}
      nil -> {:error, :inactive_subscription}
    end
  end

  @spec mandate_subscription(String.t()) :: {:ok, Subscription.t()} | {:error, :mandate_not_ready}
  def mandate_subscription(subscription_id) do
    case Repo.get_by(Subscription, subscription_id: subscription_id, mandate_ready: true) do
      %Subscription{} = subscription -> {:ok, subscription}
      nil -> {:error, :mandate_not_ready}
    end
  end

  @spec granted_credits(String.t(), String.t()) :: non_neg_integer()
  def granted_credits(account_id, period) do
    Repo.one(
      from(grant in CreditGrant,
        where: grant.account_id == ^account_id and grant.period in [^period, "prepaid"],
        select: coalesce(sum(grant.amount), 0)
      )
    )
  end

  @doc "Idempotently grants an exact credit intent; conflicting reuse is rejected."
  def grant_credits_once(account_id, source_id, period, amount, kind) do
    grant_once(%{
      account_id: account_id,
      source_id: source_id,
      period: period,
      amount: amount,
      kind: kind
    })
  end

  def get_order(order_id), do: Repo.get_by(Order, order_id: order_id)

  def order_items(order_id) do
    case get_order(order_id) do
      nil ->
        []

      order ->
        Repo.all(from(item in OrderItem, where: item.order_id == ^order.id, order_by: item.id))
    end
  end

  @doc "Stable fingerprint embedded in server-created checkout metadata."
  def cart_fingerprint(cart) do
    cart
    |> normalize_cart()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp normalize_cart(cart) do
    Enum.map(cart, fn item ->
      map = string_map(item)
      %{"product_id" => map["product_id"], "quantity" => map["quantity"] || 1}
    end)
  end

  defp resolve_duplicate_order(changeset, attrs) do
    if unique_error?(changeset, :order_id) do
      existing = Repo.get_by!(Order, order_id: attrs.order_id)

      comparable = [:pattern, :account_id, :expected_cart, :credits]

      if Enum.all?(comparable, &(Map.get(existing, &1) == Map.get(attrs, &1))) do
        if existing.status == "checkout_created",
          do: {:error, :checkout_already_created},
          else: {:ok, existing}
      else
        {:error, :idempotency_conflict}
      end
    else
      {:error, changeset}
    end
  end

  defp payment_available(%Order{payment_id: nil}, _payment_id), do: :ok
  defp payment_available(%Order{payment_id: payment_id}, payment_id), do: :ok
  defp payment_available(%Order{}, _payment_id), do: {:error, :payment_conflict}

  defp account_matches(nil, _actual), do: :ok
  defp account_matches(expected, expected), do: :ok
  defp account_matches(_expected, _actual), do: {:error, :account_mismatch}

  defp cart_hash_matches(expected, actual) when is_binary(actual) do
    expected_hash = cart_fingerprint(expected)

    if byte_size(actual) == byte_size(expected_hash) and
         Plug.Crypto.secure_compare(actual, expected_hash),
       do: :ok,
       else: {:error, :cart_hash_mismatch}
  end

  defp cart_hash_matches(_expected, _actual), do: {:error, :missing_cart_hash}

  defp cart_matches(_expected, nil), do: :ok

  defp cart_matches(expected, actual),
    do: if(normalize_cart(actual) == expected, do: :ok, else: {:error, :cart_mismatch})

  defp payment_cart(data) do
    data["product_cart"] || data["product_cart_items"] ||
      case data["product_id"] do
        product when is_binary(product) ->
          [%{"product_id" => product, "quantity" => data["quantity"] || 1}]

        _other ->
          nil
      end
  end

  defp maybe_grant_prepaid_credits(%Order{pattern: 5} = order, _webhook_id) do
    attrs = %{
      account_id: order.account_id,
      source_id: "payment:#{order.payment_id}",
      period: "prepaid",
      amount: order.credits,
      kind: "prepaid"
    }

    case grant_once(attrs) do
      {:ok, _disposition} -> :ok
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp maybe_grant_prepaid_credits(_order, _webhook_id), do: :ok

  defp maybe_grant_subscription_credits(%Subscription{pattern: 9, status: status} = subscription)
       when status in @active_states do
    grant_once(%{
      account_id: subscription.account_id,
      source_id: "subscription:#{subscription.subscription_id}:#{subscription.period}",
      period: subscription.period,
      amount: subscription.credits_per_period,
      kind: "subscription_allowance"
    })
    |> case do
      {:ok, _disposition} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp maybe_grant_subscription_credits(_subscription), do: :ok

  defp grant_once(attrs) do
    case %CreditGrant{} |> CreditGrant.changeset(attrs) |> Repo.insert() do
      {:ok, grant} ->
        {:ok, grant}

      {:error, changeset} ->
        if unique_error?(changeset, :source_id) do
          existing = Repo.get_by!(CreditGrant, source_id: attrs.source_id)

          if Enum.all?([:account_id, :period, :amount, :kind], fn field ->
               Map.get(existing, field) == Map.get(attrs, field)
             end),
             do: {:ok, existing},
             else: {:error, :idempotency_conflict}
        else
          {:error, changeset}
        end
    end
  end

  defp upsert_subscription(attrs) do
    changeset = Subscription.changeset(%Subscription{}, attrs)

    Repo.insert(changeset,
      on_conflict:
        {:replace,
         [
           :account_id,
           :pattern,
           :status,
           :mandate_ready,
           :period,
           :period_ends_at,
           :credits_per_period,
           :updated_at
         ]},
      conflict_target: [:subscription_id],
      returning: true
    )
  end

  defp persist_subscription_snapshot(attrs) do
    Repo.transaction(fn ->
      with {:ok, subscription} <- upsert_subscription(attrs),
           :ok <- maybe_grant_subscription_credits(subscription) do
        subscription
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, subscription} -> {:ok, subscription}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_period_allowance(9, period, credits)
       when is_binary(period) and is_integer(credits) and credits > 0,
       do: :ok

  defp validate_period_allowance(9, nil, _credits), do: {:error, :missing_billing_period}
  defp validate_period_allowance(9, _period, _credits), do: {:error, :invalid_period_allowance}
  defp validate_period_allowance(_pattern, _period, _credits), do: :ok

  defp validate_subscription_identity(attrs) do
    case Repo.get_by(Subscription, subscription_id: attrs.subscription_id) do
      nil ->
        :ok

      existing ->
        if existing.account_id == attrs.account_id and existing.pattern == attrs.pattern,
          do: :ok,
          else: {:error, :subscription_identity_conflict}
    end
  end

  defp change_order(order_id, changes) do
    case Repo.get_by(Order, order_id: order_id) do
      nil -> {:error, :unknown_order}
      order -> order |> Ecto.Changeset.change(changes) |> Repo.update()
    end
  end

  defp validate_expectation(%{pattern: pattern, account_id: account_id})
       when pattern in [2, 5, 6, 9] and not is_binary(account_id),
       do: {:error, :account_id_required}

  defp validate_expectation(%{pattern: 5, credits: credits})
       when not is_integer(credits) or credits <= 0,
       do: {:error, :credits_required}

  defp validate_expectation(%{expected_cart: []}), do: {:error, :empty_cart}

  defp validate_expectation(%{expected_cart: cart}) do
    if Enum.all?(
         cart,
         &(is_binary(&1["product_id"]) and is_integer(&1["quantity"]) and &1["quantity"] > 0)
       ),
       do: :ok,
       else: {:error, :invalid_cart}
  end

  defp unique_error?(changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_message, options}} -> options[:constraint] == :unique
      _other -> false
    end)
  end

  defp period_from_snapshot(data) do
    value(data, :previous_billing_date)
    |> parse_datetime()
    |> case do
      %DateTime{} = datetime ->
        Date.to_iso8601(Date.beginning_of_month(DateTime.to_date(datetime)))

      nil ->
        nil
    end
  end

  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp string_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _error -> nil
    end
  end

  defp parse_integer(_value), do: nil
end
