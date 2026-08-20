# Custom HTTP clients

`DodoPayments.ReqClient` is the supported default. A custom implementation is
appropriate when an organization already standardizes on Tesla, needs an
internal service-mesh client, or wants a deterministic test double.

The replacement boundary is deliberately small:

```elixir
@callback request(state, DodoPayments.HTTP.Request.t()) ::
  {:ok, DodoPayments.HTTP.Response.t()}
  | {:error, DodoPayments.HTTP.TransportError.t()}
```

## Responsibilities

The SDK request engine owns:

- Dodo operation validation and encoding;
- merchant versus public authentication;
- total deadlines and attempt budgeting;
- replay and idempotency policy;
- backoff and `Retry-After`;
- response decoding and typed models;
- Dodo API errors, telemetry, and `OutcomeUnknown`.

The custom client owns:

- translating the prepared request to its HTTP library;
- performing exactly one attempt;
- respecting the supplied attempt timeout;
- buffering at most `request.max_body_bytes`;
- preserving duplicate response headers;
- returning identity-encoded binary response bytes;
- classifying delivery conservatively.

It must not add retries, redirects, authentication, JSON decoding, or mutation
policy. Otherwise one logical SDK retry can multiply into several hidden HTTP
attempts.

## Request and response values

```elixir
%DodoPayments.HTTP.Request{
  method: :post,
  url: "https://live.dodopayments.com/events/ingest",
  headers: [{"authorization", "Bearer ..."}],
  body: "{...}",
  timeout: 9_842,
  max_body_bytes: 10_485_760,
  response_mode: :raw
}
```

Return raw data:

```elixir
{:ok,
 %DodoPayments.HTTP.Response{
   status: 200,
   headers: [{"content-type", "application/json"}],
   body: ~s({"ok":true})
 }}
```

Duplicate headers such as `set-cookie` remain duplicate tuples; do not collapse
them into a map. Header names and values must be binaries. If the underlying
client negotiates HTTP compression, it must perform bounded decompression and
apply `request.max_body_bytes` to the decoded bytes before returning; disabling
compression is the simpler conforming implementation.

## Transport failures

```elixir
{:error,
 %DodoPayments.HTTP.TransportError{
   reason: :timeout,
   delivery: :unknown
 }}
```

Use `delivery: :not_sent` only with positive proof. If in doubt, use
`:unknown`. That conservative answer lets the shared engine return
`OutcomeUnknown` instead of misclassifying an indeterminate mutation. Its
`replay` field tells the application whether repetition is unsafe or permitted
only with identical idempotency data.

The SDK independently enforces the remaining wall-clock deadline around this
callback, even if an adapter ignores `request.timeout`. Expiry is conservatively
unknown delivery for a consequential mutation.

If the buffered response crosses its configured limit, return:

```elixir
{:error,
 %DodoPayments.HTTP.TransportError{
   reason: {:response_too_large, request.max_body_bytes},
   delivery: :unknown,
   partial_response: %{status: status, headers: headers}
 }}
```

## Constructing the SDK client

Adapter state belongs to the application. It may be a Tesla client, PID, pool
name, immutable configuration struct, or test function:

```elixir
client =
  DodoPayments.Client.new!(
    api_key: System.fetch_env!("DODO_PAYMENTS_API_KEY"),
    environment: :live,
    client: {MyApp.DodoHTTP, adapter_state}
  )
```

The SDK does not manage custom adapter pools, connections, or other long-lived
adapter state. Supervise those resources in the application. The SDK root
supervisor always owns its short-lived deadline workers. It also owns the
bounded telemetry task subtree when asynchronous telemetry is enabled.

The callback runs in a deadline-isolated non-linked supervised Task with a snapshot of the SDK
caller's non-system process dictionary and Logger metadata. Process-local
tracing and instrumentation therefore remain visible. The SDK preserves the
Task runtime's own `$callers`, `$ancestors`, and related system entries rather
than replacing them from the caller.

## Trusted-code and process-exit boundary

`DodoPayments.ReqClient` is the supported transport. A replacement
`ClientModule`, including one built on Tesla, is trusted application code rather
than a sandboxed plugin. The SDK contains ordinary exceptions, throws, exits,
invalid return values, and callback timeouts and converts them into its normal
error values. Deadline workers are non-linked and supervised, so a hard worker
exit is reported as a transport or uncertain outcome rather than taking down
the caller. This isolation cannot make delivery durable or undo a request that
may already have reached Dodo.

Do not deliberately kill the callback process, link it to unmanaged workers, or
depend on process death as an adapter error channel. Return
`DodoPayments.HTTP.TransportError` instead. If a caller process does terminate
during an unsafe mutation, its supervisor may restart it, but the application
must still reconcile the payment outcome before repeating the mutation.

See [Deadline workers and client trust](deadline-workers-and-client-trust.md)
for the exact behavior, rationale, and alternatives considered.

## Conformance checklist

Before production use, verify that the adapter:

1. performs one and only one attempt;
2. never follows redirects;
3. does not retain Dodo credentials in reusable state;
4. returns exact binary bodies without decoding;
5. preserves duplicate headers;
6. enforces the attempt timeout and response-size limit while reading (the
   built-in Req/Finch client cancels its stream on overflow);
7. reports uncertain delivery as `:unknown`;
8. passes through public requests without adding merchant credentials;
9. behaves identically for a frozen request body across repeated callbacks;
10. returns failures as `HTTP.TransportError` rather than killing or fatally
    linking the callback process.

HTTP header names are case-insensitive. Normalize or compare them accordingly,
and never interpret differently-cased duplicates as separate credentials. The
SDK strips credential and content-encoding overrides before invoking the
callback; replacement clients should retain the same invariant at their own
adapter boundary.

A local fake `ClientModule` is also the easiest way to test application logic
without network access.
