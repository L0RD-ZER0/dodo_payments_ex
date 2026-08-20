defmodule DodoStore.Smoke.Preflight do
  @moduledoc """
  Hard safety checks applied before a credentialed smoke profile starts.

  The smoke harness deliberately has no live-mode escape hatch. A production
  deployment can run its own read-only health check, but this example never
  creates payment fixtures outside Dodo test mode.
  """

  alias DodoPayments.{Client, Secret}
  alias DodoStore.Smoke.PreflightError

  @test_origin "https://test.dodopayments.com"

  @type profile :: :local | :sandbox_api | :sandbox_checkout

  @spec check(profile(), Client.t(), keyword()) :: {:ok, map()} | {:error, PreflightError.t()}
  def check(:local, %Client{}, _opts),
    do: {:ok, %{profile: :local, delivery: :synthetic_valid_signature, network: :blocked}}

  def check(profile, %Client{} = client, opts)
      when profile in [:sandbox_api, :sandbox_checkout] do
    with :ok <- test_environment(client),
         :ok <- test_origin(client),
         :ok <- test_key(client),
         :ok <- webhook_secret(profile, opts) do
      {:ok,
       %{
         profile: profile,
         environment: :test,
         origin: @test_origin,
         delivery: delivery(profile)
       }}
    end
  end

  defp test_environment(%Client{environment: :test}), do: :ok

  defp test_environment(%Client{environment: :live}) do
    error(:live_environment, "smoke fixtures are forbidden in Dodo live mode")
  end

  defp test_environment(%Client{}) do
    error(:custom_environment, "credentialed smoke profiles require Dodo test mode")
  end

  defp test_origin(%Client{base_url: @test_origin}), do: :ok

  defp test_origin(%Client{}) do
    error(
      :unexpected_test_host,
      "credentialed smoke profiles require the canonical Dodo test host"
    )
  end

  defp test_key(%Client{api_key: nil}) do
    error(:missing_api_key, "credentialed smoke profiles require a Dodo test API key")
  end

  defp test_key(%Client{api_key: secret}) do
    case Secret.resolve(secret) do
      {:ok, "dodo_test_" <> suffix} when suffix != "" ->
        :ok

      {:ok, _value} ->
        error(:invalid_test_key, "credentialed smoke profiles require a dodo_test_ key")

      {:error, _error} ->
        error(:invalid_test_key, "the configured Dodo test API key could not be resolved")
    end
  end

  defp webhook_secret(:sandbox_api, _opts), do: :ok

  defp webhook_secret(:sandbox_checkout, opts) do
    case Keyword.get(opts, :webhook_secrets, []) do
      secrets when is_list(secrets) and secrets != [] ->
        :ok

      _value ->
        error(:missing_webhook_secret, "sandbox checkout requires a webhook signing secret")
    end
  end

  defp delivery(:sandbox_api), do: :api_boundary_only
  defp delivery(:sandbox_checkout), do: :dodo_signed_webhook_required

  defp error(reason, message),
    do: {:error, PreflightError.exception(reason: reason, message: message)}
end
