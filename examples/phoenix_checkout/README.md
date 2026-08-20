# Phoenix billing patterns lab

This is one small Phoenix application containing ten isolated billing patterns.
Pattern 1 is a live, test-mode hosted checkout. Patterns 2, 3, 5, 6, and 9 also
offer real test-mode checkout forms when you supply the applicable Dodo product
IDs; every pattern has a safe local action. The public functions in
`DodoStore.Workflows` are the corresponding integration boundaries for real
application code.

One app is intentional: it provides one dependency install, server, database,
webhook endpoint, supervision tree, and test command. Each pattern remains a
small vertical slice rather than nine copied Phoenix skeletons.

## Run it

```sh
cd examples/phoenix_checkout
mix setup

export DODO_PAYMENTS_API_KEY="your Dodo test-mode key"
export DODO_PAYMENTS_WEBHOOK_SECRETS="whsec_your_endpoint_secret"
mix run scripts/create_product.exs
mix phx.server
```

Open <http://localhost:4000> for the real one-time checkout and
<http://localhost:4000/patterns> for the complete lab. `mix setup` creates and
migrates the ignored `tmp/dodo_store.db` SQLite database.

The setup script creates **Phoenix Field Guide** for USD 19.00 and saves its
product ID in `tmp/dodo_product_id`. It uses a lock and an atomic write to avoid
duplicate setup. `DODO_PRODUCT_ID` uses an existing product instead. Prices use
the lowest currency denomination, so `1_900` means USD 19.00.

If setup is interrupted, first confirm no `create_product.exs` process is still
running before removing the stale `tmp/dodo_product_id.setup-lock` directory.
Do not delete `tmp/dodo_product_id` merely to retry: losing it can create a
second remote product. Prefer setting `DODO_PRODUCT_ID` to the known product ID.

## The ten patterns

| # | Pattern | Immediate boundary | Durable rule |
| --- | --- | --- | --- |
| 1 | One-time hosted checkout | `Workflows.checkout/6` | Persist the expected order/cart first; fulfill once from `payment.succeeded`, never the return URL. |
| 2 | SaaS subscription | `Workflows.checkout/7` | Re-retrieve current subscription state when lifecycle events arrive. |
| 3 | Mixed cart/add-ons | `Workflows.checkout/6` | Persist and fulfill each cart line independently. |
| 4 | Usage billing | `Workflows.record_usage/4` | Persist a deterministic event ID with the business action. |
| 5 | Prepaid credits | Checkout + `Workflows.authorize_prepaid_usage/4` | A matched payment grants credits once; authorize each action locally. |
| 6 | On-demand charge | Checkout + `Workflows.queue_on_demand_charge/3` | Establish an active mandate, then persist the charge intent before calling Dodo. |
| 7 | Refund/dispute | `Workflows.queue_refund/3` | Use stable command IDs and reconcile webhook state. |
| 8 | Multiple meters | `Workflows.record_multiple_meter_usage/3` | One stable event per meter, sharing one action ID. |
| 9 | Subscription + usage credits | `Workflows.authorize_hybrid_usage/7` | Active subscription grants access; local credits gate each action. |
| 10 | Hard limits | `Workflows.authorize_limited_use/6` | Reserve once by action ID under an atomic database condition. |

Pass Dodo product IDs in the checkout cart; product configuration—one-time,
recurring, metered price, and credit entitlements—lives in Dodo rather than in
the SDK. For account-bound patterns, pass your own authenticated account ID in
the final options argument. It is written to server-controlled checkout
metadata and must match the expected order when the webhook arrives. A mixed
cart is simply multiple items:

```elixir
DodoStore.Workflows.checkout(
  DodoStore.Dodo.client(),
  3,
  [
    %{product_id: "pdt_subscription", quantity: 1},
    %{product_id: "pdt_setup_fee", quantity: 1}
  ],
  "https://app.example/checkout/return",
  "https://app.example/plans",
  "order_123"
)
```

Pattern 6 also sends `subscription_data.on_demand.mandate_only: true`. A local
charge intent is accepted only after a reconciled subscription snapshot says
both that the subscription is active and that `on_demand` is true. Its stable
command ID is embedded in charge metadata so `payment.succeeded` and
`payment.failed` update only the matching local intent. Pattern 9
derives its allowance period from Dodo's `previous_billing_date`; it rejects a
snapshot with no remote billing-period boundary instead of guessing a calendar
month.

Multiple-meter and hard-limit calls use business IDs, not random retry IDs:

```elixir
DodoStore.Workflows.record_multiple_meter_usage("job_123", "cus_123", %{
  "ai.tokens" => 8_000,
  "compute.gpu_seconds" => 42,
  "storage.bytes" => 1_048_576
})

with {:ok, reservation} <-
       DodoStore.Workflows.authorize_limited_use(
         "account_123",
         "exports",
         "2026-08",
         "export_456",
         1,
         3
       ) do
  perform_export(reservation)
end
```

## Reliability model

`POST /webhooks/dodo` receives JSON through a body reader that preserves the
exact bytes, verifies the Standard Webhooks signature, and inserts the webhook
ID under a unique constraint before returning 200. The supervised
`DodoStore.Billing.InboxProcessor` processes that durable inbox. Duplicate
deliveries are harmless.

Subscription, refund, and dispute events do not directly apply arrival order
to local state. They enqueue a retrieve command. This matters because delivery
order is not resource order: retrieving current Dodo state makes an older event
unable to overwrite a newer subscription state.

Successful payments are applied only when their server-controlled metadata
matches a pre-existing local order, pattern, account, and expected product cart.
Another payment ID cannot overwrite a fulfilled order. Mixed carts have durable
line-item rows, and prepaid grants use their payment ID as an exact idempotency
intent.

Usage, charge, and refund mutations first enter `billing_outbox`.
`DodoStore.Billing.OutboxDispatcher.dispatch/2` shows the SDK calls. In a real
system, replace the example's supervised polling child with Oban or another
durable job runner. Commands are claimed before I/O. An uncertain charge/refund
moves to `reconciliation_required` and cannot return to the ordinary retry
queue; do not blindly repeat a mutation merely because the caller timed out.

SQLite is used to make the example runnable with no external service. For a
multi-node production deployment, use your primary transactional database.
ETS is useful for caches but cannot provide webhook replay safety, outbox
durability, or cross-node hard limits.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `DODO_PAYMENTS_API_KEY` | required for Dodo calls | Merchant test/live key. |
| `DODO_PAYMENTS_ENVIRONMENT` | `test` | `test`, `test_mode`, `live`, or `live_mode`. |
| `DODO_PAYMENTS_WEBHOOK_SECRETS` | none | Comma-separated active secrets for rotation. |
| `DODO_PRODUCT_ID` | generated local ID | Existing pattern-1 product. |
| `DODO_ALLOW_LIVE_EXAMPLE` | unset | Must be `true` before setup can touch live mode. |
| `DATABASE_PATH` | `/data/dodo_store.db` in production | Persistent SQLite path. |
| `PHX_HOST` | required in production | Public HTTPS callback host. |
| `PORT` | `4000` | Listener port. |
| `SECRET_KEY_BASE` | required in production | Phoenix endpoint secret. |

Configure the Dodo endpoint URL as
`https://your-host.example/webhooks/dodo`. Rotate secrets by temporarily
supplying old and new values separated by a comma.

The inbox processor is an ordinary supervised child and can be disabled for a
role that only serves HTTP:

```elixir
config :dodo_store, :inbox_processor, enabled: false
config :dodo_store, :outbox_processor, enabled: false
```

The SDK's own opt-in telemetry exporter uses its package supervisor. The
application still owns durable billing jobs; supervision keeps a worker alive,
but does not make in-memory work durable.

## Test it

```sh
mix test
```

The suite uses `Req.Test` and the Ecto SQL sandbox, with no Dodo network calls.
It covers all ten demo paths, stable meter and command IDs, the hard cap,
signature rejection, duplicate delivery, durable fulfillment, and deliberately
out-of-order subscription events. `mix test --cover` enforces a 70% whole-app
floor; that total includes generated Phoenix view/router glue as well as the
billing domain.

### Production-shaped smoke command

`mix dodo.smoke` adds a heavier, process-level check. The local profile starts
an isolated SQLite database, a real loopback Bandit endpoint, the supervised
inbox/outbox workers, and a network-blocked in-memory Dodo boundary. Checkout is
created through the public workflow and SDK, webhook bodies cross HTTP with a
valid synthetic Standard Webhooks signature, and the command waits for durable
inbox processing plus refund/dispute reconciliation.

```sh
# One seeded random lifecycle. The generated/default seed is always printed.
MIX_ENV=test mix dodo.smoke --profile local --features core

# Exercise accepted, rejected, cancelled, refunded, disputed, and both
# processing-to-terminal paths in one run.
MIX_ENV=test mix dodo.smoke \
  --profile local --features core --outcome all --seed 20260820

# Check individual payment-method enum lanes.
MIX_ENV=test mix dodo.smoke \
  --profile local --features payment-method-types \
  --methods credit,ach --outcome random --seed 20260820

# Expand all 105 source-locked method types and run isolated scenarios with a
# bounded amount of concurrency.
MIX_ENV=test mix dodo.smoke \
  --profile local --features payment-method-types --methods all \
  --execution parallel --max-concurrency 4 --seed 20260820 \
  --report tmp/payment-method-smoke.json
```

Use `--features payment-method-families --families ...` for family lanes, or
`--features all` for the combined feature inventory. `--dry-run` prints the
exact expansion without starting the application, opening a listener, or
making a network call. Repeating the printed `--seed` reproduces every random
lifecycle choice.

The local profile proves application contracts, not payment-method
availability. Dodo's enum is broader than the methods enabled for any one
merchant, country, currency, browser, or device, so reports retain an explicit
support expectation instead of treating enum membership as checkout support.
Its signatures are locally generated and valid, but they do not prove Dodo
origin or delivery. The `sandbox-api` and `sandbox-checkout` names are reserved
for credentialed drivers and currently fail closed rather than silently using
the local simulator.

Every non-dry run writes a durable manifest before checkout intent is claimed,
then stores only opaque resource IDs and secret-safe observations. A supplied
`--report` path receives an atomically replaced JSON report. `--resume` also
fails closed for now: safe continuation needs to retain the original claim
owner and continue from an already-recorded checkout without creating another
one. The persisted manifest is still useful for diagnosis; it is deliberately
not used as permission to replay a checkout.

## Deliberate production boundaries

The lab does not invent authentication, taxation, accounting ledgers, access
control, or product IDs for your business. Replace generic projections with
domain tables, dispatch the outbox with your durable job system, authorize
account ownership on every route, monitor dead jobs, and define how a reserved
unit is released if protected work fails. Keep the unique webhook/command IDs,
atomic authorization condition, exact-body verification, and reconciliation
behavior intact.

## Checkout browser asset

The overlay page pins `dodopayments-checkout` to a specific version. For a
production Content Security Policy, preferably vendor that exact JavaScript in
your own asset pipeline. If you keep a CDN script, add `integrity` and
`crossorigin="anonymous"`, calculate the SRI hash from the exact pinned bytes,
and update the version and hash together. Never copy an integrity hash from a
different release. The full-page `checkout_url` remains the fallback when the
overlay is blocked.
