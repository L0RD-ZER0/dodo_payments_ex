# Setup and configuration

`DodoPayments` uses explicit immutable client values. It does not read global
API-key or tenant configuration, or load `.env` files. The SDK owns a small root
supervision tree for short-lived deadline-worker isolation; applications do not
need to add a child for the default client. This keeps test, live, and
multi-tenant clients independent and makes the environment used for a financial
call visible at the call site.

## Runtime configuration

Store SDK options under your own OTP application. Keep the API key behind a
zero-arity provider so it is resolved for each logical call rather than copied
into reusable Req state:

```elixir
# config/runtime.exs
import Config

config :my_app, :dodo_payments,
  environment: System.fetch_env!("DODO_PAYMENTS_ENVIRONMENT"),
  api_key: fn -> System.fetch_env!("DODO_PAYMENTS_API_KEY") end,
  timeout: 30_000,
  max_attempts: 3
```

Direct key values are validated when a client is constructed or updated. A
provider function itself can only be shape-checked up front, so its returned
value is validated each time it is resolved for a logical call.

The environment accepts `:test`, `:test_mode`, `:live`, `:live_mode`, `"test"`,
`"live"`, `"test_mode"`, or `"live_mode"`. Unknown values fail during client
construction. Dodo uses separate keys and data for test and live mode, so make
the production value explicit instead of relying on the SDK's safe `:test`
default.

Provide a small application-owned access module:

```elixir
defmodule MyApp.Dodo do
  @spec client() :: DodoPayments.Client.t()
  def client do
    :my_app
    |> Application.fetch_env!(:dodo_payments)
    |> DodoPayments.client!()
  end
end
```

Then application code remains explicit:

```elixir
DodoPayments.Products.list(MyApp.Dodo.client())
```

Constructing a client is local configuration work and does not create a
client-specific process. A long-lived worker may construct it once and keep it
in its state; request
handlers may use the small accessor above. For multi-tenant systems, construct
one value per credential or use a provider that resolves the current tenant's
key. Never mutate application-global SDK configuration per request.

## Configuration options

| Option | Default | Meaning |
| --- | --- | --- |
| `:api_key` | `nil` | Non-empty, header-safe key or zero-arity provider. Merchant calls require it; public license and document calls do not. |
| `:environment` | `:test` | `:test`, `:live`, supported string aliases, or `:custom`. |
| `:base_url` | Environment URL | Absolute HTTPS URL. With no environment it selects `:custom`; if an environment is supplied it must be `:custom`. |
| `:allow_insecure_http` | `false` | Explicitly permit a trusted local/custom plaintext HTTP origin. Never enable it for live credentials. |
| `:req` | New Req request | Credential-free, uncompressed `%Req.Request{}` used by `ReqClient`. |
| `:client` | Req transport | `{ClientModule, state}` for a replacement transport. Mutually exclusive with `:req`. |
| `:timeout` | `30_000` | Total logical-call deadline in milliseconds, from `1` through the BEAM timer ceiling of `4_294_967_295`. |
| `:max_attempts` | `3` | Total attempts, including the first. Replay policy may permit fewer. |
| `:max_response_bytes` | `10_485_760` | Finite Req/Finch streaming limit; the request is cancelled before the full oversized body is buffered. |
| `:retry_base_delay` | `200` | Initial full-jitter backoff ceiling in milliseconds. |
| `:retry_max_delay` | `2_000` | Maximum backoff ceiling in milliseconds. |

A custom origin receives the same bearer credential as a Dodo origin. HTTPS is
therefore required by default. `allow_insecure_http: true` exists only for a
trusted local test server where plaintext transport is an explicit choice.

Unknown client and per-request options return a
`DodoPayments.Error.ConfigurationError` rather than being silently ignored.
Use `DodoPayments.client/1` when configuration errors should be returned and
`DodoPayments.client!/1` during controlled application startup.

## Request-local options and result shapes

Resource calls accept these request-local options in their final keyword-list
argument:

| Option | Meaning |
| --- | --- |
| `:headers` | Map or list of `{name, value}` pairs. A value may be a scalar or non-empty list for repeated values. Credentials and transport-owned authority, framing, hop-by-hop, and encoding headers are removed. |
| `:timeout` | Total logical-call deadline override in milliseconds, up to `4_294_967_295`. |
| `:max_attempts` | Attempt ceiling override; unsafe operations can still use fewer. |
| `:max_response_bytes` | Response limit override or `:infinity`. |
| `:return` | `:data` or `:response`; the latter returns a `DodoPayments.Response` envelope. |

Typed operations return SDK structs and keep unknown server fields in `extra`.
Endpoints without a reviewed schema return decoded maps/lists, empty operations
return `nil`, and PDF/CSV/binary endpoints return binaries. This partial-typing
boundary is intentional for v0: it keeps the billing core ergonomic without
pretending incomplete schemas are authoritative.

Local validation and configuration failures mean no valid HTTP attempt was
prepared. `APIError` is a conclusive application-level Dodo response. For
`OutcomeUnknown`, inspect `replay`: `:unsafe` requires reconciliation before
another attempt, while `:identical_only` permits only the same request with the
same stable idempotency values. Other transport/decode/timeout errors may only
be repeated when the operation's replay policy permits it.

## Default Req versus a named Finch

The default Req configuration needs no child in your supervision tree. Req owns
its default Finch infrastructure.

Use a named Finch when your application needs explicit pool sizing, isolation,
or pool telemetry:

```elixir
# lib/my_app/application.ex
children = [
  {Finch,
   name: MyApp.DodoFinch,
   pools: %{
     default: [
       size: 10,
       count: 1,
       conn_opts: [timeout: 5_000]
     ]
   }}
]

Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
```

Build the SDK client around that pool:

```elixir
defmodule MyApp.Dodo do
  def client do
    options = Application.fetch_env!(:my_app, :dodo_payments)

    req =
      Req.new(
        finch: [name: MyApp.DodoFinch],
        user_agent: "my-app/1.0"
      )

    DodoPayments.client!(Keyword.put(options, :req, req))
  end
end
```

For a named Finch, connection establishment options belong to its supervised
pool (`conn_opts` above). The SDK still applies the remaining logical budget as
Req's receive and pool-checkout timeouts. Do not configure both Req's `:finch`
and `:connect_options`; client construction rejects that conflict.

TLS is configurable without replacing `ClientModule`. With Req's dynamic pool,
put Mint transport options on the credential-free request:

```elixir
req =
  Req.new(
    connect_options: [
      transport_opts: [cacertfile: "/etc/my-app/corporate-ca.pem"]
    ]
  )

DodoPayments.client!(api_key: api_key, environment: :live, req: req)
```

For a named Finch, place the same `transport_opts` under that pool's
`conn_opts`. Client certificates and protocol restrictions use the same Mint
transport configuration surface.

Do not set Req's `compressed: true`, `:into`, or `:output` options, or manually
provide transport-owned headers such as `host`, `content-length`,
`transfer-encoding`, or `accept-encoding`. The
SDK enforces response limits with a streaming collector, while Req only performs
automatic decompression for fully buffered responses. `ReqClient` rejects those
base settings and removes protected headers or body sinks added by a later
request step. It forces `decode_body: false` while collecting, then decodes the
bounded identity-encoded binary body itself. Consumer response steps run after the collector has been
finalized, so they receive a normal bounded binary body. A successful response
step must leave a binary-compatible body for the SDK decoder.

## Tests without network access

Req's Plug-backed test adapter requires Plug as a test dependency in the
consumer application:

```elixir
{:plug, "~> 1.16", only: :test}
```

Create a test client with one attempt so a missing expectation is not repeated:

```elixir
defmodule MyApp.DodoTest do
  def client(stub \\ MyApp.DodoStub) do
    DodoPayments.client!(
      environment: :test,
      api_key: "sk_test",
      max_attempts: 1,
      req: Req.new(plug: {Req.Test, stub})
    )
  end
end
```

Then use normal `Req.Test` ownership and expectations:

```elixir
defmodule MyApp.CheckoutTest do
  use ExUnit.Case, async: true
  setup {Req.Test, :verify_on_exit!}

  test "loads a product" do
    Req.Test.expect(MyApp.DodoStub, fn conn ->
      Req.Test.json(conn, %{
        "product_id" => "pdt_123",
        "name" => "Starter"
      })
    end)

    assert {:ok, %DodoPayments.Product{name: "Starter"}} =
             DodoPayments.Products.retrieve(MyApp.DodoTest.client(), "pdt_123")
  end
end
```

The SDK's deadline Tasks preserve Task caller ancestry and caller tracing
context, allowing `Req.Test` ownership to resolve the test process.

## Deadline-worker trust boundary

The SDK root supervisor owns short-lived, non-linked deadline workers for
preparation, API-key resolution, each HTTP attempt, and response decoding.
Normal callback failures—including ordinary exceptions, throws, exits, invalid
return values, and timeouts—are caught or normalized into SDK errors. A worker
that is brutally terminated cannot take down the caller; the request is
reported as a timeout or uncertain outcome according to the operation's replay
policy.

No extra setup is required for Req users. Applications choosing a custom client
should run ordinary request handlers or jobs under their application supervisor,
avoid linking the adapter callback to unmanaged processes, and return
`DodoPayments.HTTP.TransportError` for failures. Process restart does not resolve
the outcome of an in-flight payment mutation; reconcile it before replaying.

See [Deadline workers and client trust](deadline-workers-and-client-trust.md)
for the detailed model and the boundary around trusted custom clients.

## Telemetry setup

Attach handlers once during your application's startup, not for every request:

```elixir
events = [
  [:dodo_payments, :request, :start],
  [:dodo_payments, :request, :stop],
  [:dodo_payments, :request, :attempt, :start],
  [:dodo_payments, :request, :attempt, :stop],
  [:dodo_payments, :request, :retry]
]

:ok =
  :telemetry.attach_many(
    "my-app-dodo-payments",
    events,
    &MyApp.DodoTelemetry.handle_event/4,
    nil
  )
```

Handlers must remain fast and must not raise. Metadata is bounded and redacted;
it never contains the API key, request body, customer parameters, or raw
transport error. A logical-call `:stop` for `OutcomeUnknown` includes
`error_category: :outcome_unknown`, `outcome_replay`, attempt count, and known
status/request ID so operators can separate unsafe reconciliation from safe
identical replay.

In the default `:request_bounded` mode each dispatch runs in a temporary
deadline worker. It receives a snapshot of Logger metadata and the caller's
non-system process dictionary, but handler writes to process-local state do not
carry into later events. Keep cross-event span state in the telemetry backend,
keyed by event metadata rather than worker process identity.
When the logical deadline is already exhausted, later best-effort telemetry
events may be omitted; request results and attempt accounting remain authoritative.

The `:retry` event is emitted only after the selected delay has completed and
the next attempt still has retained deadline budget. A retry rejected because
its delay would exceed the deadline produces the final timeout or
uncertain-outcome result without a misleading retry event. Attempt-start and
retry handlers retain a small follow-up reserve so a slow handler cannot consume
all of the budget after announcing work that never begins.

To keep observability from consuming payment-request capacity, asynchronous
telemetry is opt-in:

```elixir
config :dodo_payments, DodoPayments.Telemetry,
  mode: :async,
  max_concurrency: 64,
  timeout: 1_000
```

Async handlers use a separate bounded supervisor and temporary non-linked
workers. That subtree is started only when `:async` is configured before the SDK
application starts; restart the application after changing the mode. Events are
dropped when capacity is exhausted, are not retried, and
have no ordering guarantee. They run outside the request deadline and cannot
change the request result. Payloads, credentials, customer parameters, and raw
errors are never included in telemetry metadata.

## Webhook secrets

Webhook verification uses the webhook signing secret, not the merchant API
key. Read it independently at runtime and pass the exact raw request body:

```elixir
DodoPayments.Webhooks.verify(
  raw_body,
  request_headers,
  System.fetch_env!("DODO_PAYMENTS_WEBHOOK_SECRET")
)
```

During rotation, pass `[new_secret, previous_secret]`. Do not place either
secret in the reusable Req request.
