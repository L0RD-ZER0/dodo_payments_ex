defmodule DodoPayments.Request.RetryPolicy do
  @moduledoc false

  alias DodoPayments.HTTP

  # 425 means the server refused to risk processing the early request. It is
  # retryable for replay-safe operations, but unlike 408/5xx it is conclusive:
  # a final 425 is an APIError rather than an ambiguous mutation outcome.
  @retryable_statuses [408, 425, 429]

  @spec replayable?(DodoPayments.Operation.replay(), map() | nil) :: boolean()
  def replayable?(:safe, _params), do: true

  def replayable?({:idempotent_by, fields}, params) do
    Enum.all?(fields, fn
      path when is_list(path) -> stable_path?(params || %{}, path)
      field when is_atom(field) -> stable_path?(params || %{}, [field])
    end)
  end

  def replayable?(_replay, _params), do: false

  @spec retryable_status?(integer()) :: boolean()
  def retryable_status?(status), do: status in @retryable_statuses or status in 500..599

  @spec ambiguous_status?(integer()) :: boolean()
  def ambiguous_status?(status), do: status == 408 or status in 500..599

  @spec consequential_mutation?(map()) :: boolean()
  def consequential_mutation?(context), do: context.operation.consequential

  @spec outcome_replay(map()) :: DodoPayments.Error.OutcomeUnknown.replay()
  def outcome_replay(context) do
    if context.replayable?, do: :identical_only, else: :unsafe
  end

  @spec available?(map(), pos_integer()) :: boolean()
  def available?(context, attempt_number), do: attempt_number < context.max_attempts

  @spec delay(DodoPayments.Client.t(), pos_integer(), HTTP.Response.t() | nil) ::
          non_neg_integer()
  def delay(client, attempt_number, response) do
    case retry_after(response) do
      milliseconds when is_integer(milliseconds) ->
        milliseconds

      nil ->
        exponential = capped_exponential(client, attempt_number)

        if exponential == 0, do: 0, else: :rand.uniform(exponential + 1) - 1
    end
  end

  defp capped_exponential(%{retry_base_delay: 0}, _attempt_number), do: 0
  defp capped_exponential(%{retry_max_delay: 0}, _attempt_number), do: 0

  defp capped_exponential(client, attempt_number) do
    exponent_cap = exponent_cap(div(client.retry_max_delay, client.retry_base_delay), 0)
    exponent = min(attempt_number - 1, exponent_cap)

    min(client.retry_base_delay * Integer.pow(2, exponent), client.retry_max_delay)
  end

  defp exponent_cap(0, count), do: count
  defp exponent_cap(value, count), do: exponent_cap(div(value, 2), count + 1)

  defp retry_after(nil), do: nil

  defp retry_after(response) do
    case HTTP.Response.header(response, "retry-after") do
      nil ->
        nil

      value ->
        value = String.trim(value)

        case Integer.parse(value) do
          {seconds, ""} when seconds >= 0 -> seconds * 1_000
          _other -> retry_after_date(value)
        end
    end
  end

  defp retry_after_date(value) do
    with [_, day, month, year, hour, minute, second] <-
           Regex.run(
             ~r/^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$/,
             value
           ),
         {:ok, date} <-
           Date.new(String.to_integer(year), month_number(month), String.to_integer(day)),
         {:ok, time} <-
           Time.new(String.to_integer(hour), String.to_integer(minute), String.to_integer(second)),
         {:ok, retry_at} <- DateTime.new(date, time, "Etc/UTC") do
      max(DateTime.diff(retry_at, DateTime.utc_now(), :millisecond), 0)
    else
      _invalid -> nil
    end
  end

  defp month_number(month) do
    Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == month)) + 1
  end

  defp stable_path?(value, []), do: is_binary(value) and value != ""

  defp stable_path?(values, path) when is_list(values) do
    values != [] and Enum.all?(values, &stable_path?(&1, path))
  end

  defp stable_path?(map, [field | rest]) when is_map(map) do
    case DodoPayments.Validation.fetch(map, field) do
      {:ok, value} -> stable_path?(value, rest)
      :error -> false
    end
  end

  defp stable_path?(_value, _path), do: false
end
