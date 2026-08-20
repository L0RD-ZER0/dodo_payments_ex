defmodule DodoPayments.Webhooks do
  @moduledoc """
  Verifies and decodes Dodo Payments webhooks using the Standard Webhooks
  signing scheme.

  Always pass the exact request body bytes. Parsing and re-encoding JSON changes
  those bytes and makes an otherwise valid signature fail.

      with {:ok, event} <-
             DodoPayments.Webhooks.verify(raw_body, headers, webhook_secret) do
        handle_event(event)
      end

  A list of active secrets enables non-disruptive secret rotation. All secrets
  are checked without exposing which one matched.

  Verification is deliberately stateless. Dodo may retry or replay a delivery,
  and webhook events are not guaranteed to arrive in creation order. A
  successful verification therefore does not claim that the event is new or
  that it is the next event for a resource. Persist `event.webhook_id` in a
  durable inbox with a unique constraint before acknowledging the request, and
  make the business operation idempotent at the resource or order level as
  well. Do not use the webhook timestamp as a generic last-write-wins ordering
  key. Acknowledge only after processing has completed or the delivery has
  been durably enqueued; an ETS or process-local cache is not a durable replay
  or ordering mechanism.
  """

  alias DodoPayments.Webhooks.{Event, VerificationError, Verifier}

  @doc "Verifies the signature and returns a decoded, lossless event."
  @spec verify(binary(), map() | [{term(), term()}], binary() | [binary()], keyword()) ::
          {:ok, Event.t()} | {:error, VerificationError.t()}
  def verify(raw_body, headers, secrets, opts \\ []) do
    Verifier.verify(raw_body, headers, secrets, opts)
  end

  @doc "Like `verify/4`, but raises `VerificationError` when verification fails."
  @spec verify!(binary(), map() | [{term(), term()}], binary() | [binary()], keyword()) ::
          Event.t()
  def verify!(raw_body, headers, secrets, opts \\ []) do
    case verify(raw_body, headers, secrets, opts) do
      {:ok, event} -> event
      {:error, error} -> raise error
    end
  end

  @doc "Verifies authenticity without decoding the JSON event body."
  @spec verify_signature(binary(), map() | [{term(), term()}], binary() | [binary()], keyword()) ::
          :ok | {:error, VerificationError.t()}
  def verify_signature(raw_body, headers, secrets, opts \\ []) do
    Verifier.verify_signature(raw_body, headers, secrets, opts)
  end
end
