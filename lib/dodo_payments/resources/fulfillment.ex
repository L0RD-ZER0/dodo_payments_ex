defmodule DodoPayments.Entitlements do
  @moduledoc "Fulfilment entitlement definitions."
  use DodoPayments.Service
  operation(:list, :entitlements_list)
  operation(:create, :entitlements_create)
  operation(:retrieve, :entitlements_retrieve, path: [:id], params: false)
  operation(:delete, :entitlements_delete, path: [:id], params: false)
  operation(:update, :entitlements_update, path: [:id])
end

defmodule DodoPayments.Entitlements.Files do
  @moduledoc "Files attached to fulfilment entitlements."
  use DodoPayments.Service
  operation(:upload, :entitlement_files_upload, path: [:id], params: false)
  operation(:delete, :entitlement_files_delete, path: [:id, :file_id], params: false)
end

defmodule DodoPayments.EntitlementGrants do
  @moduledoc "Customer grants produced by fulfilment entitlements."
  use DodoPayments.Service
  operation(:list, :entitlement_grants_list, path: [:id])
  operation(:revoke, :entitlement_grants_revoke, path: [:id, :grant_id], params: false)
  operation(:fulfill_license_key, :entitlement_grants_fulfill_license_key, path: [:grant_id])
end

defmodule DodoPayments.LicenseKeys do
  @moduledoc "Merchant management of license keys."
  use DodoPayments.Service
  operation(:list, :license_keys_list)
  operation(:create, :license_keys_create)
  operation(:retrieve, :license_keys_retrieve, path: [:id], params: false)
  operation(:update, :license_keys_update, path: [:id])
end

defmodule DodoPayments.LicenseKeyInstances do
  @moduledoc "Merchant inspection of activated license-key instances."
  use DodoPayments.Service
  operation(:list, :license_key_instances_list)
  operation(:retrieve, :license_key_instances_retrieve, path: [:id], params: false)
  operation(:update, :license_key_instances_update, path: [:id])
end

defmodule DodoPayments.Licenses do
  @moduledoc "Credential-free runtime license activation, deactivation and validation."
  use DodoPayments.Service
  operation(:activate, :licenses_activate)
  operation(:deactivate, :licenses_deactivate)
  operation(:validate, :licenses_validate)
end
