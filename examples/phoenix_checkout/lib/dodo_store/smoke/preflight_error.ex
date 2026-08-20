defmodule DodoStore.Smoke.PreflightError do
  @moduledoc "A secret-safe smoke-profile prerequisite failure."

  defexception [:message, :reason]

  @type reason ::
          :live_environment
          | :custom_environment
          | :unexpected_test_host
          | :missing_api_key
          | :invalid_test_key
          | :missing_webhook_secret

  @type t :: %__MODULE__{message: String.t(), reason: reason()}
end
