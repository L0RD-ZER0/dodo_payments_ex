# Changelog

## 0.1.0

- Raised the default transport baseline to Req 0.7.3 while retaining Elixir
  1.15 support, adopting Req's module-based Finch adapter and current named-pool
  option shape without weakening bounded response streaming.
- Advanced the audited Dodo source lock from TypeScript SDK 2.44.0 to 2.47.0,
  adding permanent brand archive, archived-brand filtering, subscription
  pause/unpause types, the `live_tutoring` tax category, and the
  `subscription.unpaused` webhook event.
- Typed payment line-item responses and added `paused_at` to subscription
  structs after live sandbox probes found those previously generic fields.
- Replaced every remaining generic nested request field with a reusable locked
  2.47 type and typed the add-on, brand, customer, discount, meter, refund,
  entitlement, and webhook response families.
- Completed typed response coverage for all 140 operations, including safe
  decoding for bare arrays and every remaining catalog, collection, customer,
  wallet, subscription, dispute, credit, license, and payout response family.
  Live test-mode checks also captured the server's numeric credit-balance and
  grant amounts alongside the source-locked SDK's declared string form.
- Added a durable E2E constrained-operation register with the exact evidence and
  exit condition for each of the 20 test-account or upstream-blocked operations.
- Made source-locked Dodo enums idiomatic Elixir atom unions at the public API
  boundary, with exact string encoding, lossless `UnknownEnum` response values,
  and no dynamic atom creation from API or webhook data.
- Bounded deadline-worker startup itself so an unavailable or restarting task
  supervisor cannot exit or indefinitely block an SDK caller.
- Reserved follow-up deadline budget around attempt-start and retry telemetry,
  preventing those events from announcing adapter work that a slow handler
  leaves no time to begin.
- Started the asynchronous telemetry subtree only when async mode is enabled,
  broadened the direct Finch constraint to the Req-compatible 0.21 series, and
  added `refresh_token` to canonical recursive redaction.
- Corrected response-number documentation: decoded JSON retains Jason
  integers/floats, while outbound `Decimal` values encode as exact strings.
- Rejected recursive request-map keys that collide after JSON name conversion,
  preventing silent data loss, and documented when key-provider values are
  validated.
- Rejected improper custom-client response headers as one-attempt invalid
  results, bounded timeout configuration to the BEAM timer ceiling, and stopped
  emitting retry telemetry for delays that cannot fit the remaining deadline.
- Pinned every GitHub Action used by CI to a verified immutable commit.
- Latched ambiguous mutation outcomes across retries so a later not-sent
  failure, application error, or deadline cannot erase an earlier attempt that
  may have committed.
- Reserved HTTP authority, framing, hop-by-hop, and body-encoding headers for
  the SDK and transport instead of forwarding contradictory caller values.
- Finalized bounded Req response streams before consumer response steps,
  stopped those steps on overflow, and rejected incompatible body sinks.
- Tightened generated path types, pagination option validation, saturated
  retry backoff before exponentiation, and compiled test support with warnings
  as errors in CI.
- Preserved `OutcomeUnknown` for oversized successful responses from
  operation-idempotent but consequential mutations.
- Rejected literal `.` and `..` path parameters in parity with the pinned
  upstream SDK, preventing intermediary dot-segment normalization.
- Extended the shared logical deadline across request validation, attached
  telemetry handlers, and response decoding using supervised short-lived
  workers plus an opt-in bounded async-telemetry subtree.
- Made webhook header and secret limit checks stop at their configured bounds
  instead of pre-scanning complete untrusted lists.
- Corrected nine remaining required-body contracts so generated resource APIs
  cannot issue empty mutations that Dodo will always reject.
- Added typed, redacted presigned-upload and customer-portal responses so
  capability URLs remain safe in normal and response-envelope inspection.
- Accepted Dodo's empty terminal webhook iterator and rejected non-advancing
  cursor pages before duplicate items can reach consumers.
- Locked and independently verified the Phoenix example dependency graph,
  updated it for current Phoenix conventions, and made its CI cache key local
  to the example lockfile.
- Removed unusable empty-parameter arities from required-body operations and
  made keyword-list ambiguity fail with a map-vs-options configuration error.
- Generated operation-aware resource docs and result types, including typed
  page items and response envelopes.
- Split request preparation, deadlines, adapter validation, decoding, retries,
  telemetry, and pagination-envelope parsing into focused internal modules.
- Derived audited SDK version and operation-count metadata directly from the
  bundled source lock and removed the Operation/catalog compile cycle.
- Added a complete source-level verification suite covering retry safety,
  uncertain mutation outcomes, deadlines, Req streaming limits, credential
  stripping, webhook verification, redaction, schemas, and configuration.
- Enforced finite Req/Finch response limits during streaming instead of after
  buffering the complete body.
- Unified webhook option validation under `VerificationError` results.
- Added strict Credo, Dialyzer, formatter, warnings-as-errors, and CI gates.
- Enforced a 65% coverage floor in CI to prevent the current safety suite from
  silently regressing while broader resource coverage grows.
- Centralized redaction and version metadata; made custom endpoint selection
  explicit and moved operation-specific validation policy into the catalogue.
- Classified oversized ambiguous mutation responses as `OutcomeUnknown` and
  retained their partial status/request ID in telemetry.
- Added redacted inspection for response envelopes and pages, rejected invalid
  adapter header types, and made Req response compression explicitly unsupported
  so streaming response limits remain truthful.
- Corrected ambiguous-result classification for conditionally idempotent
  mutations, rejected nested atom/string key collisions before replay analysis,
  and reserved the final Req protection-step name against caller collisions.
- Added a complete Phoenix checkout example with a hard-coded product, guarded
  setup script, server-side checkout-session creation, overlay fallback, and
  network-free controller tests, plus root-level companion instructions.
- Classified exhausted ambiguous `408`/`5xx` and transport results for
  idempotent mutations as `OutcomeUnknown`, distinguishing `:identical_only`
  replay from mutations that remain `:unsafe` to repeat.
- Separated remote consequences from replayability, enforced object-shaped typed
  responses, and corrected webhook-create idempotency and change-plan decoding.
- Redacted credential-bearing document URLs, rejected unsafe API-key header bytes,
  supported HTTP-date `Retry-After`, and hardened webhook resource accounting.
- Made Phoenix product setup locally serialized, atomically persisted, and
  recoverable when remote creation succeeds but saving its ID fails.

- Initial Req-first Dodo Payments SDK implementation.
- Added explicit runtime configuration, named Finch, Req.Test, and telemetry
  setup guidance.
