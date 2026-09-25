# Dodo Payments for Elixir

An unofficial, explicit, Req-first Elixir SDK for Dodo Payments. It follows
Dodo's own resource names, keeps clients as immutable ordinary values with no
global API key, and makes payment uncertainty visible instead of hiding it
behind automatic retries.

> [!IMPORTANT]
> This independent project is not affiliated with, endorsed by, or maintained
> by Dodo Payments. Use the [official Dodo Payments website][dodo-payments] for
> the API service and first-party support.

The default transport is [Req][req]. The SDK owns a small
root supervision tree for isolating short-lived deadline workers; applications
do not need to add a child for the default client. It does not create a global
API-key or tenant registry. A small `DodoPayments.ClientModule` boundary allows
a company to use Tesla or an internal HTTP stack without changing the public
API. Named Finch pools, custom-client connections, and durable jobs remain
application-owned.

This SDK is a safety-focused public v0. Its API may evolve across `0.x`
releases, but payment-outcome and credential-handling behavior are treated as
hard compatibility boundaries.

## Contents

- [Installation][installation]
- [Five-minute start][five-minute-start]
- [Phoenix example][phoenix-example]
- [Public API style][public-api-style]
- [Pagination][pagination]
- [Retries and uncertain payments][retries-and-uncertain-payments]
- [Webhooks][webhooks]
- [Use an existing Req pipeline][use-an-existing-req-pipeline]
- [Use Tesla or an internal transport][use-tesla-or-an-internal-transport]
- [Operational defaults][operational-defaults]
- [Differences from generated Dodo SDKs][differences-from-generated-dodo-sdks]
- [Development][development]
- [Security][security]
- [License][license-section]

## Installation

Add the package to `mix.exs`:

```elixir
def deps do
  [
    {:dodo_payments, "~> 0.1"}
  ]
end
```

The SDK requires Elixir 1.15 or later and uses Req 0.7.3 or later in the 0.7 series by default.

The SDK does not read client credentials or API behavior from application
configuration and does not automatically load a `.env` file. Client
configuration is explicit: construct a client value from your application's
runtime configuration and pass it to calls. The one application-level setting
is the optional telemetry execution mode described below. See
[Setup and configuration][setup-and-configuration] for `runtime.exs`,
Phoenix/OTP, named Finch, tests, and telemetry examples.

## Five-minute start

Create one client value and pass it to resource functions:

```elixir
client =
  DodoPayments.Client.new!(
    api_key: System.fetch_env!("DODO_PAYMENTS_API_KEY"),
    environment: :test
  )

{:ok, checkout} =
  DodoPayments.CheckoutSessions.create(client, %{
    product_cart: [
      %{product_id: "pdt_123", quantity: 1}
    ]
  })

checkout.checkout_url
```

`:test` is the default environment, which reduces accidental live charges.
Production use is explicit:

```elixir
client =
  DodoPayments.Client.new!(
    api_key: fn -> System.fetch_env!("DODO_PAYMENTS_API_KEY") end,
    environment: :live,
    timeout: 30_000,
    max_attempts: 3
  )
```

The zero-arity key provider supports runtime secret rotation. It is resolved
once per logical API call and is never stored by `DodoPayments.ReqClient`.
Direct keys are validated when the client is constructed or updated; a
provider's returned value is validated when that provider is resolved.

## Phoenix example

The `examples/phoenix_checkout` directory contains one runnable Phoenix billing
lab with ten pattern pages: one-time and subscription checkout, mixed carts,
usage and multi-meter billing, prepaid and hybrid credits, on-demand charges,
refund/dispute reconciliation, and atomic hard limits. It includes a durable
SQLite webhook inbox/outbox, a configurable supervised processor, and network-free
integration tests.

See [Phoenix checkout example][phoenix-checkout-example] for setup, configuration,
workflow APIs, out-of-order webhook handling, and production boundaries.

## Public API style

Modules use Dodo's vocabulary rather than an SDK-specific payment ontology:

```elixir
DodoPayments.Products.list(client, %{page_number: 0, page_size: 25})
DodoPayments.Products.retrieve(client, "pdt_123")
DodoPayments.Subscriptions.retrieve(client, "sub_123")
DodoPayments.UsageEvents.ingest(client, %{events: events})
DodoPayments.Licenses.validate(client, %{license_key: key})
DodoPayments.Invoices.download_payment(client, "pay_123")
DodoPayments.Payouts.download_breakup_csv(client, "payout_123")
```

Calls normally return `{:ok, value} | {:error, exception}`. Response objects are
typed where a stable schema is useful, while unknown fields remain in `extra`
and known server enum values decode to atoms. A value added by Dodo before an
SDK update becomes `%DodoPayments.UnknownEnum{}` with its exact wire string;
server input is never converted into a new atom. Every JSON operation in the
2.47 catalogue has a typed response contract: object responses return SDK
structs, paginated responses contain typed items, and bare arrays contain typed
items or decoded enum atoms. Empty responses return `nil`; PDF, CSV, and other
binary operations return binaries.

Struct fields carry field-specific types derived from the locked upstream SDK.
Every field also permits `nil` because structs have nullable defaults and the
decoder is forward-compatible rather than a required-field validator. Nested
objects and lists deliberately remain string-keyed maps for compatibility, so
existing access such as `payment.customer["customer_id"]` continues to work.

JSON number fields in responses retain Jason's integer/float representation;
response decoding does not synthesize `Decimal` values. Outbound `Decimal`
values are supported and encode as exact decimal strings rather than passing
through a binary floating-point number. Use the currency's lowest denomination
where an endpoint documents integer minor units.

Credit balance and grant amount fields accept both decimal strings declared by
the source-locked SDK and JSON numbers currently observed in Dodo's test API.
The union is intentional: it preserves real wire behavior without silently
coercing precision-bearing strings.

Every operation that accepts a Dodo parameter map also publishes an
endpoint-local type, such as `create_params` on `DodoPayments.CheckoutSessions`
or `update_params` on `DodoPayments.Subscriptions`. These types expose the exact
top-level atom fields, requiredness, and primitive/list/object shapes from the
source-locked upstream declarations. Atom keys, string keys, and mixed maps are
all accepted at runtime; the broad compatibility branch in each type exists
because Elixir typespecs cannot express a required literal string key. Nested
objects stay recursively encodable maps, but every nested field in the locked
2.47 request surface has a named type. This includes discriminated product
prices, recursive meter filters, checkout themes and custom fields, entitlement
integration unions, refund items, collection groups, discount currency options,
and subscription credit/on-demand controls. Source-locked TypeScript
string-literal enums become atom unions such as `:active | :cancelled`; the
request codec converts them back to Dodo's exact JSON strings and rejects an
unknown atom before dispatch. Existing string values remain accepted during
v0.x for compatibility. Metadata is a flat string/number/boolean map, while
webhook headers and metadata are string-only as declared upstream. Outbound
`Date`, `DateTime`, `NaiveDateTime`, and `Decimal` values retain their existing
ISO/string codec behavior; exact upstream numeric fields remain `number()`
because a `Decimal` encodes as a JSON string.

For status, headers, and the Dodo request ID:

```elixir
{:ok, response} =
  DodoPayments.Products.retrieve(client, "pdt_123", return: :response)

response.data
response.status
response.request_id
response.headers
```

Operations that normally accept a parameter map also accept request options
directly when no parameters are needed:

```elixir
{:ok, response} = DodoPayments.Products.list(client, return: :response)
```

Request-local options are consistent across resource modules:

| Option | Meaning |
| --- | --- |
| `:headers` | Map or list of header pairs. Values may be scalars or non-empty lists for repeated values. Credentials and transport-owned `host`, framing, and encoding headers are removed. |
| `:timeout` | Set this logical call's fresh total deadline in milliseconds, from `1` through `4_294_967_295`. |
| `:max_attempts` | Override the maximum attempt count; replay policy may permit fewer. |
| `:max_response_bytes` | Override the bounded response limit or use `:infinity`. |
| `:return` | `:data` (default) or `:response` for status, headers, and request ID. |

Errors are returned as values. `ValidationError` and `ConfigurationError` mean
no valid request was prepared. `APIError` is a conclusive application-level
Dodo response. Its routine message surfaces HTTP status, request ID, and a
string `code` from Dodo's known top-level or nested error envelope; any server
message and unrecognized envelope fields remain available only in the retained
body and are not echoed by default.
`TransportError`, `TimeoutError`, `DecodeError`, and `ResponseTooLarge` describe
transport or response handling; retry only according to the operation's replay
policy. `OutcomeUnknown.replay` is either `:unsafe` or `:identical_only`; follow
that value and the accompanying reconciliation guidance before another attempt.

## Pagination

Numbered and iterator pagination are deliberately distinct. Dodo's numbered
lists are zero-based, and the SDK preserves those page numbers directly.
Iterator pages expose Dodo's names without aliases: `iterator`,
`prev_iterator`, and `done?`.

```elixir
{:ok, first} = DodoPayments.Products.list(client, %{page_number: 0})

case DodoPayments.Page.next(first) do
  {:ok, second} -> second.items
  :done -> []
  {:error, error} -> raise error
end
```

Automatic traversal is opt-in, lazy, cycle-checked, and bounded:

```elixir
products =
  first
  |> DodoPayments.Page.stream(max_pages: 20, max_items: 250)
  |> Enum.to_list()
```

Stopping or closing the stream stops requests; it does not prefetch another
page. See the pagination module docs for manual page traversal and its bounded
page/item closure behavior.

## Retries and uncertain payments

The SDK—not Req or a custom adapter—owns retries. An adapter performs exactly
one attempt. Reads and explicitly safe operations may retry transient failures.
Mutations retry only when Dodo's operation semantics and stable idempotency data
make that safe.

If a mutation may have reached Dodo but no conclusive response arrives:

```elixir
case DodoPayments.Subscriptions.charge(client, "sub_123", params) do
  {:ok, payment} ->
    {:ok, payment}

  {:error, %DodoPayments.Error.OutcomeUnknown{} = error} ->
    case error.replay do
      :unsafe -> {:reconcile_before_repeating, error}
      :identical_only -> {:retry_only_with_identical_idempotency_data, error}
    end

  {:error, error} ->
    {:error, error}
end
```

See [Retries and uncertain outcomes][retries-and-outcomes].

## Webhooks

Verification implements the Standard Webhooks signing scheme. Pass the **exact
raw body bytes**, before JSON parsing or re-encoding:

```elixir
case DodoPayments.Webhooks.verify(raw_body, request_headers, webhook_secret) do
  {:ok, %DodoPayments.Webhooks.Event{type: :payment_succeeded} = event} ->
    Payments.mark_paid(event.data)

  {:ok, %DodoPayments.Webhooks.Event{type: %DodoPayments.UnknownEnum{}} = event} ->
    # New Dodo event types are not discarded. The complete decoded map and raw
    # body remain available as event.payload and event.raw_body.
    Events.store_for_later(event)

  {:error, %DodoPayments.Webhooks.VerificationError{}} ->
    {:error, :unauthorized}
end
```

Use `DodoPayments.Enums.dump!/2` when persisting or forwarding an enum in its
wire form—for example,
`DodoPayments.Enums.dump!(:webhook_event_type, event.type)`.

Secret rotation does not require downtime:

```elixir
DodoPayments.Webhooks.verify(raw_body, headers, [new_secret, previous_secret])
```

The verifier checks timestamp tolerance (five minutes by default) and compares
HMACs in constant time. Verification is stateless: Dodo retries and manual
replays are expected, and webhook events may arrive out of order. Persist
`event.webhook_id` in a durable inbox with a unique constraint before
acknowledging the request. A unique business-resource or order constraint is
also needed so two distinct webhook IDs cannot fulfill the same purchase.
Timestamps are useful metadata but are not a generic ordering guarantee. Do
not acknowledge after merely spawning an unpersisted task, and do not use an
ETS or process-local cache as replay or ordering storage. Reconcile current
resource state when an out-of-order event could otherwise regress local state.

Untrusted verifier work is bounded by default to a 1 MiB body, 16 KiB of
headers, 32 signatures, and 8 active secrets. The corresponding
`:max_body_bytes`, `:max_header_bytes`, `:max_signatures`, and `:max_secrets`
options can adjust those ceilings; each encoded secret is additionally limited
to 4 KiB by `:max_secret_bytes`.

## Use an existing Req pipeline

Supply a credential-free `%Req.Request{}`. Plugins, adapters, and Finch options
are retained, except for response compression, caller-provided `:into`
collectors, and Req's body-consuming `:output` option. The SDK protects method,
absolute URL, body, authorization, response mode, remaining timeout, retry
ownership, redirect behavior, and identity response encoding at execution time.

```elixir
req =
  Req.new(
    finch: [name: MyApp.DodoFinch],
    user_agent: "my-app/1.0"
  )
  |> Req.Request.append_request_steps(my_tracing: &MyApp.ReqTracing.attach/1)

client =
  DodoPayments.Client.new!(
    api_key: System.fetch_env!("DODO_PAYMENTS_API_KEY"),
    environment: :live,
    req: req
  )
```

Caller-provided Req steps are trusted application code. The SDK rejects a base
request that already contains credentials, `compressed: true`, or an
SDK-owned transport header such as `host`, `content-length`, `transfer-encoding`,
or `accept-encoding`. Req skips whole-body decompression when a streaming
collector is installed, so the SDK deliberately disables compression instead
of advertising support it cannot bound safely. `decode_body: false` is also
forced while the collector is active; the SDK decodes the bounded
identity-encoded binary body after collection. Header names are compared
case-insensitively. User-agent precedence is reusable Req configuration, then a
request-local `user-agent` header, then the SDK's versioned default. Response
steps receive the bounded response body as a normal binary rather than the SDK's
streaming accumulator.

If `MyApp.DodoFinch` is a named Finch, your application must supervise it. The
SDK does not start named pools. The setup guide includes a complete child spec
and explains where its connection timeout is configured.

## Use Tesla or an internal transport

Implement one callback that performs one attempt. Do not copy a plain
`Tesla.request/2` wrapper for production: Tesla adapters ordinarily return an
already-buffered body, which cannot enforce `request.max_body_bytes` while the
response is being read. The transport underneath Tesla must stream into a bounded
collector (or reject finite limits before sending):

```elixir
defmodule MyApp.DodoTeslaClient do
  @behaviour DodoPayments.ClientModule

  alias DodoPayments.HTTP

  @impl true
  def request(tesla_client, %HTTP.Request{} = request) do
    # Application-owned integration with the chosen Tesla adapter. It must
    # perform one attempt and return HTTP.Response or HTTP.TransportError.
    MyApp.BoundedTesla.request(tesla_client,
      method: request.method,
      url: to_string(request.url),
      headers: request.headers,
      body: request.body,
      timeout: request.timeout,
      max_body_bytes: request.max_body_bytes
    )
  end
end

client =
  DodoPayments.Client.new!(
    api_key: System.fetch_env!("DODO_PAYMENTS_API_KEY"),
    environment: :live,
    client: {MyApp.DodoTeslaClient, tesla_client}
  )
```

`MyApp.BoundedTesla` is deliberately application-specific because bounded
streaming and cancellation differ by Tesla adapter. See
[Custom clients][custom-clients] for the complete contract and return
shapes. The supported Req client already implements bounded streaming.

## Operational defaults

```elixir
DodoPayments.Client.new!(
  api_key: "...",
  environment: :test,
  timeout: 30_000,                 # total logical call deadline
  max_attempts: 3,                 # attempts, not retries
  max_response_bytes: 10_485_760,  # reject responses over 10 MiB
  retry_base_delay: 200,
  retry_max_delay: 2_000
)
```

Telemetry events are emitted under `[:dodo_payments, :request, ...]` for
logical-call `:start`/`:stop`, attempt `:start`/`:stop`, and `:retry`. Attempt
metadata includes the attempt number and, when known, status, request ID, or a
low-cardinality error category. Metadata never includes API keys, raw transport
errors, request bodies, or customer parameters. A `:retry` event is emitted only
after its backoff has completed and the engine has retained enough deadline
budget to begin the next attempt. Attempt-start handlers are bounded with a
small follow-up reserve so an emitted start is not allowed to consume the
entire dispatch budget.

Deadline isolation uses short-lived non-linked supervised Tasks. Before each
preparation or adapter Task starts, the SDK snapshots the caller's non-system
process dictionary and Logger metadata. This preserves process-local key
providers, tracing context, and Req instrumentation while retaining the Task's
own `$callers`, `$ancestors`, and other runtime-owned dictionary entries. A
worker that exceeds the deadline or dies is converted to the SDK's normal
timeout/transport outcome instead of terminating the caller.

By default telemetry handlers run within the request's bounded work. Opt into
asynchronous telemetry with the application configuration below when handlers
must not consume request deadline time:

```elixir
config :dodo_payments, DodoPayments.Telemetry,
  mode: :async,
  max_concurrency: 64,
  timeout: 1_000
```

Only `:async` mode starts the separate bounded telemetry supervisor and its
temporary non-linked tasks; the default mode does not leave a telemetry worker
subtree running. The mode is selected when the SDK application starts, so
changing it at runtime requires restarting the application. Async events are
best-effort: events are dropped when capacity is exhausted, have no
ordering guarantee, are not retried, and never affect the payment result or
request deadline. Telemetry metadata remains low-cardinality and redacted; it
does not include payloads, credentials, customer parameters, or raw errors.

That snapshot is compatibility behavior, not a secret store. Avoid placing
credentials or large values in the process dictionary; use the client's key
provider and normal tracing metadata instead.

For finite `max_response_bytes` values, the default Req/Finch adapter counts
response chunks and cancels the stream as soon as the next chunk would cross
the limit. Custom `ClientModule` implementations receive the same limit and
must enforce it while reading; the SDK also rejects an oversized custom-client
body defensively if an adapter violates that contract.

Response envelopes and both pagination structs use redacted `Inspect`
implementations. Canonical secrets in typed or untyped response data and
sensitive response headers are not printed by routine debugging.

SDK error structs retain bounded raw response or adapter details when those are
needed for programmatic reconciliation. Do not serialize whole exceptions into
logs, analytics, crash metadata, or user responses: generic serializers do not
use Elixir's redacted `Inspect` implementations. Use the deliberately small
summary instead:

```elixir
Logger.warning("Dodo request failed",
  dodo: DodoPayments.Error.safe_summary(error)
)
```

The response byte limit bounds input and stops an oversized stream early; it is
not a heap limit. JSON parsing and schema construction temporarily allocate more
memory than the wire body, so choose a lower `max_response_bytes` for endpoints
whose expected payloads are small.

## Differences from generated Dodo SDKs

This SDK intentionally defaults to test mode, uses one total logical deadline,
and retries only operations whose identical replay is safe. Numbered pages are
zero-based. It does not treat 409 as retryable, does not honor a proprietary
`x-should-retry` header, and treats a final 425 as a conclusive refusal. When
migrating, review retry and reconciliation behavior instead of copying timeout
or page assumptions from another language SDK.

## Development

```console
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=test mix coveralls
mix credo --strict
mix dialyzer
```

The test suite uses local `ClientModule` fakes and Req adapters; it makes no
calls to Dodo Payments.

## Security

Report suspected SDK vulnerabilities privately to `security@developing.tools`.
Do not open a public issue for an undisclosed vulnerability or include live API
keys, webhook secrets, customer data, or unredacted request and response bodies
in a report. Vulnerabilities in Dodo Payments' hosted API or service should be
reported directly to Dodo Payments. See the repository's complete
[security policy][security-policy] for scope, contacts, and the current `0.x`
support policy.

## License

Released under the [MIT License][license].

[custom-clients]: guides/custom-clients.md
[development]: #development
[differences-from-generated-dodo-sdks]: #differences-from-generated-dodo-sdks
[dodo-payments]: https://www.dodopayments.com/
[five-minute-start]: #five-minute-start
[installation]: #installation
[license]: LICENSE
[license-section]: #license
[operational-defaults]: #operational-defaults
[pagination]: #pagination
[phoenix-checkout-example]: PHOENIX_EXAMPLE.md
[phoenix-example]: #phoenix-example
[public-api-style]: #public-api-style
[req]: https://hexdocs.pm/req/
[retries-and-outcomes]: guides/retries-and-outcomes.md
[retries-and-uncertain-payments]: #retries-and-uncertain-payments
[security]: #security
[security-policy]: SECURITY.md
[setup-and-configuration]: guides/setup-and-configuration.md
[use-an-existing-req-pipeline]: #use-an-existing-req-pipeline
[use-tesla-or-an-internal-transport]: #use-tesla-or-an-internal-transport
[webhooks]: #webhooks
