defmodule DodoPayments.Payments do
  @moduledoc "Payment creation and inspection."
  use DodoPayments.Service
  operation(:list, :payments_list)

  operation(:create, :payments_create,
    deprecated: "Use DodoPayments.CheckoutSessions.create/2 for new integrations"
  )

  operation(:retrieve, :payments_retrieve, path: [:payment_id], params: false)
  operation(:list_line_items, :payment_line_items_list, path: [:payment_id], params: false)
end

defmodule DodoPayments.Subscriptions do
  @moduledoc "Subscription lifecycle, plan and usage operations."
  use DodoPayments.Service
  operation(:list, :subscriptions_list)

  operation(:create, :subscriptions_create,
    deprecated: "Use DodoPayments.CheckoutSessions.create/2 for new integrations"
  )

  operation(:retrieve, :subscriptions_retrieve, path: [:subscription_id], params: false)
  operation(:update, :subscriptions_update, path: [:subscription_id])
  operation(:charge, :subscriptions_charge, path: [:subscription_id])
  operation(:change_plan, :subscriptions_change_plan, path: [:subscription_id])
  operation(:usage_history, :subscriptions_usage_history, path: [:subscription_id])

  operation(:update_payment_method, :subscriptions_update_payment_method,
    path: [:subscription_id]
  )

  operation(:preview_change_plan, :subscriptions_preview_change_plan, path: [:subscription_id])
  operation(:credit_usage, :subscriptions_credit_usage, path: [:subscription_id], params: false)

  operation(:cancel_scheduled_change_plan, :subscriptions_cancel_change_plan,
    path: [:subscription_id],
    params: false
  )
end

defmodule DodoPayments.Refunds do
  @moduledoc "Refund creation and inspection."
  use DodoPayments.Service
  operation(:list, :refunds_list)
  operation(:create, :refunds_create)
  operation(:retrieve, :refunds_retrieve, path: [:refund_id], params: false)
end

defmodule DodoPayments.Disputes do
  @moduledoc "Payment dispute inspection."
  use DodoPayments.Service
  operation(:list, :disputes_list)
  operation(:retrieve, :disputes_retrieve, path: [:dispute_id], params: false)
end
