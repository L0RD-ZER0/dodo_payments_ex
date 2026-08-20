defmodule DodoPayments.Meters do
  @moduledoc "Usage meter lifecycle operations."
  use DodoPayments.Service
  operation(:list, :meters_list)
  operation(:create, :meters_create)
  operation(:retrieve, :meters_retrieve, path: [:id], params: false)
  operation(:archive, :meters_archive, path: [:id], params: false)
  operation(:unarchive, :meters_unarchive, path: [:id], params: false)
end

defmodule DodoPayments.UsageEvents do
  @moduledoc "Usage event ingestion and inspection. Event IDs provide ingestion idempotency."
  use DodoPayments.Service
  operation(:ingest, :usage_events_ingest)
  operation(:list, :usage_events_list)
  operation(:retrieve, :usage_events_retrieve, path: [:event_id], params: false)
end

defmodule DodoPayments.CreditEntitlements do
  @moduledoc "Credit entitlement definitions. These are distinct from fulfilment entitlements."
  use DodoPayments.Service
  operation(:list, :credit_entitlements_list)
  operation(:create, :credit_entitlements_create)
  operation(:retrieve, :credit_entitlements_retrieve, path: [:id], params: false)
  operation(:delete, :credit_entitlements_delete, path: [:id], params: false)
  operation(:update, :credit_entitlements_update, path: [:id])
  operation(:undelete, :credit_entitlements_undelete, path: [:id], params: false)
end

defmodule DodoPayments.CreditEntitlements.Balances do
  @moduledoc "Per-customer balances for a credit entitlement. Lists are zero-based."
  use DodoPayments.Service
  operation(:list, :credit_balances_list, path: [:credit_entitlement_id])

  operation(:retrieve, :credit_balances_retrieve,
    path: [:credit_entitlement_id, :customer_id],
    params: false
  )

  operation(:list_grants, :credit_balance_grants_list,
    path: [:credit_entitlement_id, :customer_id]
  )

  operation(:list_ledger, :credit_balance_ledger_list,
    path: [:credit_entitlement_id, :customer_id]
  )

  operation(:create_ledger_entry, :credit_balance_ledger_entries_create,
    path: [:credit_entitlement_id, :customer_id]
  )
end
