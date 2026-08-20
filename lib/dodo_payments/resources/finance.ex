defmodule DodoPayments.Payouts do
  @moduledoc "Dodo payout inspection."
  use DodoPayments.Service
  operation(:list, :payouts_list)
  operation(:retrieve_breakup, :payout_breakup_retrieve, path: [:payout_id], params: false)
  operation(:list_breakup_details, :payout_breakup_details_list, path: [:payout_id])

  operation(:download_breakup_csv, :payout_breakup_csv_download,
    path: [:payout_id],
    params: false
  )
end

defmodule DodoPayments.Invoices do
  @moduledoc "PDF invoice downloads."
  use DodoPayments.Service
  operation(:download_payment, :invoices_payment_download, path: [:payment_id], params: false)
  operation(:download_refund, :invoices_refund_download, path: [:refund_id], params: false)
  operation(:download_payout, :invoices_payout_download, path: [:payout_id], params: false)
end

defmodule DodoPayments.WebhookEndpoints do
  @moduledoc "Webhook endpoint management. For signature verification use `DodoPayments.Webhooks`."
  use DodoPayments.Service
  operation(:list, :webhook_endpoints_list)
  operation(:create, :webhook_endpoints_create)
  operation(:retrieve, :webhook_endpoints_retrieve, path: [:webhook_id], params: false)
  operation(:delete, :webhook_endpoints_delete, path: [:webhook_id], params: false)
  operation(:update, :webhook_endpoints_update, path: [:webhook_id])

  operation(:retrieve_secret, :webhook_endpoints_retrieve_secret,
    path: [:webhook_id],
    params: false
  )
end

defmodule DodoPayments.WebhookEndpoints.Headers do
  @moduledoc "Custom headers configured for a webhook endpoint."
  use DodoPayments.Service
  operation(:retrieve, :webhook_headers_retrieve, path: [:webhook_id], params: false)
  operation(:update, :webhook_headers_update, path: [:webhook_id])
end
