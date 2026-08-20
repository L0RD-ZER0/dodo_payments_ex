defmodule DodoPayments.Webhooks.Event do
  @moduledoc """
  A verified Dodo Payments webhook event.

  Known event types decode to atoms such as `:payment_succeeded`. Dodo can add
  an event before an SDK release; an unknown type is retained losslessly in
  `DodoPayments.UnknownEnum` together with the complete `payload` and exact
  `raw_body` rather than rejected or converted into a new atom.
  """

  @enforce_keys [:webhook_id, :type, :payload, :raw_body]
  defstruct [:webhook_id, :id, :type, :timestamp, :data, :business_id, :payload, :raw_body]

  @type t :: %__MODULE__{
          webhook_id: String.t(),
          id: String.t() | nil,
          type: DodoPayments.Enums.decoded_webhook_event_type(),
          timestamp: String.t() | integer() | nil,
          data: term(),
          business_id: String.t() | nil,
          payload: map(),
          raw_body: binary()
        }

  @doc false
  @spec from_payload(String.t(), binary(), map()) :: {:ok, t()} | {:error, term()}
  def from_payload(webhook_id, raw_body, %{"type" => type} = payload) when is_binary(type) do
    {:ok,
     %__MODULE__{
       webhook_id: webhook_id,
       id: payload["id"],
       type: DodoPayments.Enums.load(:webhook_event_type, type),
       timestamp: payload["timestamp"],
       data: payload["data"],
       business_id: payload["business_id"],
       payload: payload,
       raw_body: raw_body
     }}
  end

  def from_payload(_webhook_id, _raw_body, _payload), do: {:error, :invalid_event}
end

defimpl Inspect, for: DodoPayments.Webhooks.Event do
  import Inspect.Algebra

  def inspect(event, opts) do
    fields = [
      webhook_id: event.webhook_id,
      id: event.id,
      type: event.type,
      timestamp: event.timestamp,
      business_id: event.business_id,
      data: :redacted,
      payload: :redacted,
      raw_body: :redacted
    ]

    concat(["#DodoPayments.Webhooks.Event<", to_doc(fields, opts), ">"])
  end
end
