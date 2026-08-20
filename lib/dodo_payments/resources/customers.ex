defmodule DodoPayments.Customers do
  @moduledoc "Customer lifecycle operations."
  use DodoPayments.Service
  operation(:list, :customers_list)
  operation(:create, :customers_create)
  operation(:retrieve, :customers_retrieve, path: [:customer_id], params: false)
  operation(:update, :customers_update, path: [:customer_id])
end

defmodule DodoPayments.Customers.PaymentMethods do
  @moduledoc "Stored customer payment methods."
  use DodoPayments.Service
  operation(:list, :customer_payment_methods_list, path: [:customer_id], params: false)

  operation(:delete, :customer_payment_methods_delete,
    path: [:customer_id, :payment_method_id],
    params: false
  )
end

defmodule DodoPayments.Customers.CreditEntitlements do
  @moduledoc "Credit entitlements belonging to a customer."
  use DodoPayments.Service
  operation(:list, :customer_credit_entitlements_list, path: [:customer_id], params: false)
end

defmodule DodoPayments.Customers.Entitlements do
  @moduledoc "Fulfilment entitlements and grants belonging to a customer."
  use DodoPayments.Service
  operation(:list, :customer_entitlements_list, path: [:customer_id], params: false)
  operation(:list_grants, :customer_entitlement_grants_list, path: [:customer_id])
end

defmodule DodoPayments.Customers.PortalSessions do
  @moduledoc "Customer self-service portal sessions."
  use DodoPayments.Service
  operation(:create, :customer_portal_sessions_create, path: [:customer_id])
end

defmodule DodoPayments.Customers.Wallets do
  @moduledoc "Customer money wallets. These are distinct from credit balances."
  use DodoPayments.Service
  operation(:list, :customer_wallets_list, path: [:customer_id], params: false)
end

defmodule DodoPayments.Customers.Wallets.LedgerEntries do
  @moduledoc "Customer wallet adjustments and history."
  use DodoPayments.Service
  operation(:list, :customer_wallet_ledger_entries_list, path: [:customer_id])
  operation(:create, :customer_wallet_ledger_entries_create, path: [:customer_id])
end

defmodule DodoPayments.Balances do
  @moduledoc "Merchant balance ledger history."
  use DodoPayments.Service
  operation(:list_ledger, :balance_ledger_list)
end
