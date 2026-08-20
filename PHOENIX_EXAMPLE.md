# Phoenix billing patterns example

The complete application is in `examples/phoenix_checkout`. It is one runnable
Phoenix lab with ten isolated vertical slices, one SQLite database, one verified
webhook endpoint, and one supervision tree. Keeping the patterns together avoids
nine copied project skeletons while preserving a named workflow for each case.

Pattern 1 is the original live test-mode checkout. Checkout-based patterns 2,
3, 5, 6, and 9 can also launch real test-mode sessions when you supply Dodo
product IDs; every page retains a safe local action. Integration entry points
live in `DodoStore.Workflows`.

## Run it

```sh
cd examples/phoenix_checkout
mix setup

export DODO_PAYMENTS_API_KEY="your Dodo test-mode key"
export DODO_PAYMENTS_WEBHOOK_SECRETS="whsec_your_endpoint_secret"
mix run scripts/create_product.exs
mix phx.server
```

Open <http://localhost:4000> for one-time checkout and
<http://localhost:4000/patterns> for all patterns. Setup creates the ignored
SQLite database and creates or reuses the sample USD 19 product. Use
`DODO_PRODUCT_ID` to supply an existing product.

## Pattern map

| # | Pattern | Example API | Central invariant |
| --- | --- | --- | --- |
| 1 | One-time checkout | `Workflows.checkout/6` | Persist the expected order, then fulfill once from a verified payment webhook. |
| 2 | SaaS subscription | `Workflows.checkout/7` | Reconcile current state after lifecycle events. |
| 3 | Mixed cart/add-ons | `Workflows.checkout/6` | Track each line item independently. |
| 4 | Usage billing | `Workflows.record_usage/4` | Use a deterministic event ID and durable outbox. |
| 5 | Prepaid credits | `Workflows.authorize_prepaid_usage/4` | Grant on a matched payment and authorize locally. |
| 6 | On-demand charge | Mandate-only checkout + `Workflows.queue_on_demand_charge/3` | Require a reconciled active `on_demand` mandate and persist charge intent before dispatch. |
| 7 | Refund/dispute | `Workflows.queue_refund/3` | Idempotent command plus state reconciliation. |
| 8 | Multiple meters | `Workflows.record_multiple_meter_usage/3` | One stable event ID per meter and operation. |
| 9 | Subscription + usage credits | `Workflows.authorize_hybrid_usage/7` | Subscription grants access; local allowance gates use. |
| 10 | Hard usage limits | `Workflows.authorize_limited_use/6` | Reserve once by action ID before protected work. |

Dodo product configuration determines whether a cart item is one-time,
recurring, metered, or grants credits. The same server-side checkout API accepts
the appropriate product IDs. For example, pattern 3 passes both the recurring
base product and one-time setup product in `product_cart`.

## Webhooks, ordering, and jobs

`POST /webhooks/dodo` preserves the exact raw JSON, verifies the Standard
Webhooks signature, and commits the webhook ID to `webhook_inbox` under a unique
constraint before acknowledging it. A supervised inbox processor can then
restart safely because the work survives process and node restarts.

Lifecycle event order is not trusted. Subscription, refund, and dispute
deliveries schedule a current-resource retrieval instead of applying a
timestamp or arrival-order transition. This prevents a delayed older event from
reverting a newer local state.

Usage, charge, refund, and reconciliation work is stored in `billing_outbox`.
The included dispatcher shows the exact SDK calls. Production applications
should run that dispatcher through Oban or another durable job system. An
uncertain charge/refund is removed from ordinary retries and placed in
`reconciliation_required` rather than blindly repeating a possibly completed
mutation.

Pattern 10 uses a unique action-ID reservation and an atomic conditional
database update, so a retry does not consume the allowance twice. Dodo metering
reports usage for billing, but a remote asynchronous API is not an authorization lock.
ETS is also not sufficient: it loses state on restart and does not coordinate
multiple nodes. SQLite keeps the lab dependency-free; production should use the
application's primary transactional database.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `DODO_PAYMENTS_API_KEY` | required for calls | Merchant test/live key. |
| `DODO_PAYMENTS_ENVIRONMENT` | `test` | Test or live API selection. |
| `DODO_PAYMENTS_WEBHOOK_SECRETS` | none | Comma-separated active webhook secrets. |
| `DODO_PRODUCT_ID` | generated ID | Existing pattern-1 product. |
| `DATABASE_PATH` | `/data/dodo_store.db` in production | Persistent SQLite file. |
| `PHX_HOST` | required in production | Public HTTPS host. |
| `SECRET_KEY_BASE` | required in production | Phoenix endpoint secret. |

The inbox processor is supervised by `DodoStore.Supervisor`. A role dedicated
to serving HTTP can opt out:

```elixir
config :dodo_store, :inbox_processor, enabled: false
```

This is different from unsupervised `spawn/1`: supervision provides restart
semantics, while the database provides durability. The SDK's opt-in telemetry
exporter has its own package supervisor; application-owned billing jobs remain
the application's responsibility.

## Tests and production work

```sh
cd examples/phoenix_checkout
mix test
```

Tests are network-free and cover all ten patterns, duplicate webhook delivery,
signature failure, reversed lifecycle events, deterministic meter IDs, durable
commands, and hard-cap denial.

Before production, adapt the small example domain tables to your own ledger,
add authentication and account ownership checks, dispatch and monitor the
outbox with a durable job runner, and define compensation for reserved usage
when the protected operation fails. The app-local README contains concrete API
examples, setup-lock recovery, CDN/SRI guidance, and a fuller handoff checklist.
