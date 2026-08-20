defmodule DodoStore.Smoke.RuntimeTest do
  use ExUnit.Case, async: false

  alias DodoStore.Smoke.{PreflightError, Runtime}

  test "a credentialed runtime refuses a live environment before making changes" do
    previous = System.get_env("DODO_PAYMENTS_ENVIRONMENT")
    System.put_env("DODO_PAYMENTS_ENVIRONMENT", "live")

    on_exit(fn -> restore_env("DODO_PAYMENTS_ENVIRONMENT", previous) end)

    # The application is already running under ExUnit, so exercise the same
    # hard policy through the public preflight helper instead of reconfiguring it.
    client = DodoPayments.Client.new!(environment: :live, api_key: "dodo_live_secret")

    assert {:error, %PreflightError{reason: :live_environment}} =
             DodoStore.Smoke.Preflight.check(:sandbox_api, client, [])
  end

  test "an already-started test application exposes an honest runtime descriptor" do
    assert {:ok, %Runtime{} = runtime} = Runtime.start(%{profile: :local, resume: nil, seed: 42})
    assert runtime.endpoint_url == "http://127.0.0.1:4002"
    assert runtime.application_started? == false
    assert runtime.webhook_secret =~ "whsec_"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
