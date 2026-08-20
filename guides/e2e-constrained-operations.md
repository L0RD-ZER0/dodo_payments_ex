# E2E constrained-operation register

Last verified: 2026-08-19 against Dodo test mode and the audited
`dodopayments` TypeScript SDK 2.47.0 contract.

The workflow matrix currently contains 140 terminal operations:

- 132 have successful effects observed through the Elixir SDK plus an
  independent observer: Dodo MCP where a read path exists, and an automated
  browser for hosted-only effects.
- 7 file/image operations are accepted as complete-for-now by the owner. Their
  API boundary was exercised, while object-store upload/delete behavior is
  intentionally deferred until a real integration needs it.
- 1 operation, payout-invoice download, cannot acquire its prerequisite in
  Dodo test mode. Dodo explicitly disables bank payouts there.

This register preserves the distinction between verified behavior,
owner-accepted deferral, and a platform constraint. "Done for now" never means
that unperformed byte-level verification occurred.

## Closed with live state transitions

| # | Operation | Live evidence |
| --- | --- | --- |
| 6 | `customer_portal_sessions_create` | Elixir created a time-limited portal session. Headless Chromium loaded `test.customer.dodopayments.com` and observed subscriptions, payments, invoices, and working Manage Subscription controls. The capability link was not logged. |
| 7 | `customer_payment_methods_delete` | Elixir deleted `pm_vwiwSxEC9FcOtoLJmHUe`; both Elixir and MCP observed an empty saved-method list afterward. A later browser flow created a fresh recurring-enabled method, proving creation and deletion were not artifacts of an empty account. |
| 8 | `subscriptions_charge` | An active on-demand subscription accepted a charge, and its resulting payment was independently read back. |
| 9 | `subscriptions_change_plan` | Elixir scheduled a plan change on active subscription `sub_0Nlg6mndF5f1C6SPqraBv`; MCP observed the scheduled change. |
| 10 | `subscriptions_update_payment_method` | Elixir initiated a new-method session, the real hosted Dodo test checkout saved card `4242`, MCP observed recurring-enabled method `pm_GX5WxCGOuIm4Urf6junm` selected on the subscription, and Elixir read back the same IDs. |
| 11 | `subscriptions_preview_change_plan` | Elixir returned a successful next-billing-date preview with the complete price breakdown. |
| 12 | `subscriptions_cancel_change_plan` | Elixir cancelled the scheduled change; MCP and Elixir both observed `scheduled_change: nil`. |
| 13 | `refunds_create` | Successful test payments produced succeeded refunds, which were independently retrieved. |
| 14 | `entitlement_grants_fulfill_license_key` | A manual-license purchase produced pending grant `entg_0NlgGzVLUuyj4cOxTMaCI`; Elixir fulfilled it and MCP observed `Delivered` with a generated license key. |
| 15 | `refunds_retrieve` | Succeeded refunds `ref_0Nlg8HYU1Lja9ACIObJsE` and `ref_0Nlg7wjWvUztzDOjfjPNe` were retrievable through both clients. |
| 16 | `disputes_retrieve` | Elixir created a one-time ACH checkout using Dodo's documented succeeds-then-disputes account. After `SM11AA` microdeposit verification, MCP observed payment `pay_0NlgMzGbNzVYHiYVaFrvw` succeed and dispute `dp_cOqriveon3WJQE9Oil67` open; Elixir then retrieved and listed that exact dispute. |
| 18 | `invoices_refund_download` | Elixir and MCP downloaded the same succeeded-refund PDF: 51,453 bytes, `%PDF-1.7` magic, SHA-256 `cbb1b772a4653a01a10a68ad7a48004d7dc6062174f5a26c60f09c0ac956f79a`. |

## Owner-accepted file boundary

These operations are marked done for the current release sweep. Reopen the
specific row if a real file integration exposes an issue.

| # | Operation | What was exercised | Deferred boundary |
| --- | --- | --- | --- |
| 1 | `addons_update_images` | Elixir and MCP returned an image ID and presigned URL. | Upload bytes, attach the image, and read it back. |
| 2 | `brands_update_images` | Elixir and MCP returned an image ID and presigned URL. | Upload bytes, attach the image, and read it back. |
| 3 | `products_update_files` | Elixir and MCP returned a file ID and presigned URL. | Upload bytes, attach the file, and verify delivery metadata. |
| 4 | `product_images_update` | Elixir and MCP returned an image ID and presigned URL. | Upload bytes, attach the image, and read it back. |
| 5 | `product_collections_update_images` | Elixir and MCP returned an image ID and presigned URL. | Upload bytes, attach the image, and read it back. |
| 17 | `entitlement_files_delete` | Both clients reached the effective delete route. | The current business has no linked merchant for this file lifecycle; retry with a real merchant-linked file if needed. |
| 20 | `entitlement_files_upload` | Both clients reached Dodo's endpoint and exposed the published no-body contract. | Dodo currently rejects it for a missing multipart boundary, but neither published SDK exposes a file/body argument. Reopen when Dodo publishes the multipart contract. |

## Remaining platform constraint

| # | Operation | Evidence | Exit condition |
| --- | --- | --- | --- |
| 19 | `invoices_payout_download` | Dodo's test/live feature matrix marks **Payouts to Bank Account** unavailable in test mode. The test account's payout list is empty, the API has no payout-create operation, and the public example payout ID returns `404` from both documented hosts. | Supply a successful payout ID from an authorized account, or use a future Dodo-provided test payout fixture. Do not mutate a live payout merely to close this test. |

## Important protocol observations

- `subscriptions_update_payment_method` with `type: new` is a hosted customer
  action. Sending its zero-amount intent through Dodo's raw one-time-card
  confirmation endpoint fails because the processor requires a SetupIntent;
  the hosted flow succeeds and persists the recurring method.
- ACH test accounts require microdeposit verification. Stripe's hosted form
  renders the `SM` prefix itself, so the editable suffix for the documented
  `SM11AA` test code is `11AA`.
- The ACH dispute is asynchronous. The payment first became `succeeded`, then
  the `dispute_opened` record appeared roughly sixteen seconds later. Tests
  must poll or consume webhooks instead of assuming the dispute is atomic with
  payment completion.

## Recheck procedure

Use only test-mode, run-owned fixtures. For each reopened row:

1. Perform the transition with the Elixir SDK.
2. Complete any documented hosted customer action in a test browser.
3. Read the resulting state through Dodo MCP.
4. Read it again through the Elixir SDK where an API read path exists.
5. Record IDs and state, but never persist API keys, client secrets, signed
   capability URLs, invoice contents, or real customer data.
6. Keep platform constraints explicit instead of turning a `404` into a false
   pass.

Private machine-readable evidence lives under `tmp/e2e/` with mode `0600` and
is intentionally ignored by Git.
