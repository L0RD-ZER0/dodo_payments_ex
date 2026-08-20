# Retries and uncertain outcomes

Payments are not ordinary CRUD. A network timeout does not prove that a charge,
refund, subscription change, or checkout creation failed. The request may have
reached Dodo Payments and its response may have been lost.

This SDK has one retry owner: its shared request engine. Req retries and
redirects are disabled, and every `DodoPayments.ClientModule` callback
represents exactly one HTTP attempt.

## Replay classes

Each operation carries reviewed replay policy:

| Policy | Behavior |
|---|---|
| Safe read/preview | May retry transient transport failures and retryable statuses |
| Idempotent using stable fields | May retry only when every required stable value exists |
| Unsafe mutation | Never retries an ambiguously delivered attempt |

Usage ingestion is a useful example. A batch is replayable only when every
event has a non-empty `event_id`. A partially identified batch is treated as
unsafe rather than optimistically retrying it.

## Delivery evidence

A transport reports one of two values:

```elixir
:not_sent
:unknown
```

`:not_sent` requires positive proof that no portion of the request reached the
remote service—for example, a DNS failure or refused connection before any
request was delivered. Every uncertain timeout, closed connection, adapter
exception, or invalid adapter result is `:unknown`.

The small distinction is intentional. The SDK does not pretend to reconstruct
socket history that an HTTP client cannot actually prove.

## `OutcomeUnknown`

An unknown transport result—or an ambiguous `408`/`5xx` response—for a
consequential mutation returns:

```elixir
%DodoPayments.Error.OutcomeUnknown{
  operation: :subscriptions_charge,
  reason: reason,
  status: status_when_known,
  request_id: request_id_when_known,
  attempts: attempt_count,
  replay: :unsafe | :identical_only,
  reconciliation: guidance
}
```

This also covers a successful mutation response that the SDK cannot safely
consume, such as malformed JSON or an oversized response body. An oversized
ambiguous `408`/`5xx` response, or an overflow where no status was obtained, is
classified the same way. Dodo may already have committed the mutation even when
it returned a server error.

The `replay` field makes the next action explicit:

| `replay` | Meaning |
|---|---|
| `:unsafe` | Do not repeat before reconciling the affected resource or webhook stream. |
| `:identical_only` | Another attempt is safe only with the identical request and the same stable idempotency values. Never generate a new value merely because the first result was unclear. |

For conditionally idempotent operations, the SDK retries within the configured
attempt/deadline budget first. Once an attempt has an ambiguous result, that
uncertainty remains latched until a successful response resolves it. A later
proven-not-sent failure, application error, or deadline cannot establish that
the earlier attempt did not commit. The final result therefore remains
`OutcomeUnknown` with `replay: :identical_only` rather than being classified
solely from the last attempt.

Replayability and remote consequences are separate properties. Reads and previews
are non-consequential even when implemented as POST requests. Operation-idempotent
mutations may be safe to replay while still requiring `OutcomeUnknown` when the
SDK cannot establish whether the first attempt changed Dodo state.

The application workflow is:

1. Keep the business operation's own stable correlation ID.
2. Inspect the affected Dodo Payment, Subscription, Refund, or Checkout where
   one can be identified.
3. Check authenticated webhook events.
4. If `replay == :identical_only`, the application may instead repeat the exact
   request with its original stable idempotency values.
5. If `replay == :unsafe`, repeat only after establishing that it did not happen.

A conclusive application response such as HTTP `409` remains an `APIError` when
no earlier attempt was ambiguous; it does not become `OutcomeUnknown` merely
because it is non-successful.
Reads and explicitly safe previews also retain ordinary API/transport errors
after exhausting retries because they have no consequential mutation to
reconcile.

## Identical retry bytes

Request validation and JSON encoding happen once before the first attempt. All
SDK retries reuse the same URL, headers, and body bytes. Credential-provider
functions are also resolved once per logical call.

This prevents map ordering, changing clocks, rotating configuration, or custom
serializers from quietly changing the operation between attempts.

## Deadlines and `Retry-After`

`timeout` is a total wall-clock deadline, not a fresh timeout for every attempt.
Local preparation, API-key providers, adapter work, and backoff consume the same
budget. The SDK isolates and terminates an adapter callback that exceeds the
remaining time. For consequential mutations, adapter expiry is `OutcomeUnknown`
because termination cannot prove that Dodo did not commit the request; its
`replay` field still distinguishes identical replay from unsafe repetition.

Retry delays honor both integer delay-seconds and standard IMF-fixdate
(`HTTP-date`) `Retry-After` values. A date is interpreted relative to the
current UTC clock and a past date means no delay; invalid or ambiguous values
fall back to bounded jittered exponential backoff. The selected delay must fit
inside the same logical deadline. A valid server-supplied delay is honored
without client jitter or capping only when it fits; otherwise the received
conclusive API response is returned instead of being replaced by a local
timeout.
Request-local overrides are available:

```elixir
DodoPayments.Products.retrieve(client, "pdt_123",
  timeout: 5_000,
  max_attempts: 2
)
```

Reducing `max_attempts` to `1` disables SDK retries for that call without
changing transport behavior.

## Deadline-worker exits

Deadline enforcement uses short-lived non-linked workers owned by the SDK root
supervisor. Expected callback failures are contained: ordinary exceptions,
throws, exits, invalid adapter results, and timeouts enter the retry and
outcome-classification policy described above. A hard-killed worker cannot
terminate the SDK caller; an in-flight consequential mutation is still
`OutcomeUnknown` when delivery cannot be proven absent. Custom clients remain
trusted application code and must return `DodoPayments.HTTP.TransportError`
for failures rather than deliberately killing their callback process.

For an unsafe mutation, a caller crash does not prove that the remote operation
failed. Supervising and restarting the application process improves local
availability, but it does not make blindly replaying a charge safe. Preserve a
business correlation identifier and reconcile with Dodo before retrying, just
as with `OutcomeUnknown`.

See [Deadline workers and client trust](deadline-workers-and-client-trust.md)
for the full tradeoff analysis.
