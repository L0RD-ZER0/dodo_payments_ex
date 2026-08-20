defmodule DodoStore.Smoke.PreflightTest do
  use ExUnit.Case, async: true

  alias DodoPayments.Client
  alias DodoStore.Smoke.{Preflight, PreflightError}

  test "local profile is explicitly synthetic and network blocked" do
    client = Client.new!(environment: :custom, base_url: "https://merchant.invalid")

    assert {:ok, %{profile: :local, delivery: :synthetic_valid_signature, network: :blocked}} =
             Preflight.check(:local, client, [])
  end

  test "credentialed profiles reject live and custom environments" do
    live = Client.new!(environment: :live, api_key: "dodo_live_secret")

    assert {:error, %PreflightError{reason: :live_environment}} =
             Preflight.check(:sandbox_api, live, [])

    custom =
      Client.new!(
        environment: :custom,
        base_url: "https://test-proxy.invalid",
        api_key: "dodo_test_secret"
      )

    assert {:error, %PreflightError{reason: :custom_environment}} =
             Preflight.check(:sandbox_api, custom, [])
  end

  test "sandbox API accepts only a canonical test client and test-prefixed key" do
    valid = Client.new!(environment: :test, api_key: "dodo_test_secret")

    assert {:ok, %{profile: :sandbox_api, delivery: :api_boundary_only}} =
             Preflight.check(:sandbox_api, valid, [])

    invalid = Client.new!(environment: :test, api_key: "sk_test")

    assert {:error, %PreflightError{reason: :invalid_test_key} = error} =
             Preflight.check(:sandbox_api, invalid, [])

    refute inspect(error) =~ "sk_test"
  end

  test "sandbox checkout additionally requires webhook verification material" do
    client = Client.new!(environment: :test, api_key: "dodo_test_secret")

    assert {:error, %PreflightError{reason: :missing_webhook_secret}} =
             Preflight.check(:sandbox_checkout, client, [])

    assert {:ok, %{delivery: :dodo_signed_webhook_required}} =
             Preflight.check(:sandbox_checkout, client, webhook_secrets: ["whsec_encoded_secret"])
  end
end
