defmodule DodoStore.Smoke.OptionsRegistryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias DodoStore.Smoke.{Options, PaymentMethodRegistry}
  alias DodoStore.Smoke.PaymentMethodRegistry.Entry

  test "defaults are safe, bounded, and make the local lifecycle seed-replayable" do
    options = Options.parse!(["--seed", "41"])

    assert %Options{
             profile: :local,
             features: [:core],
             methods: :all,
             families: :all,
             interaction: :automated,
             execution: :sequential,
             coverage: :strict,
             max_concurrency: 4,
             timeout: 60_000,
             dry_run: false,
             seed: 41,
             outcomes: [:random]
           } = options
  end

  test "parses the complete CLI contract without creating input-derived atoms" do
    options =
      Options.parse!([
        "--profile",
        "sandbox-checkout",
        "--features",
        "payment-method-types,resilience",
        "--methods",
        "credit,ach",
        "--interaction",
        "automated",
        "--execution",
        "parallel",
        "--coverage",
        "informational",
        "--max-concurrency",
        "8",
        "--timeout",
        "120000",
        "--resume",
        "run_123",
        "--report",
        "/tmp/dodo-smoke.json",
        "--outcome",
        "accepted,rejected",
        "--seed",
        "123"
      ])

    assert options.profile == :sandbox_checkout
    assert options.features == [:payment_method_types, :resilience]
    assert options.methods == [:credit, :ach]
    assert options.interaction == :automated
    assert options.execution == :parallel
    assert options.coverage == :informational
    assert options.max_concurrency == 8
    assert options.timeout == 120_000
    assert options.resume == "run_123"
    assert options.report == "/tmp/dodo-smoke.json"
    assert options.outcomes == [:accepted, :rejected]
    assert options.seed == 123
  end

  test "accepts repeatable selectors and rejects reserved-selector mixtures" do
    options =
      Options.parse!([
        "--features",
        "payment-method-types",
        "--methods",
        "credit",
        "--methods",
        "ach",
        "--outcome",
        "accepted",
        "--outcome",
        "disputed",
        "--seed",
        "7"
      ])

    assert options.methods == [:credit, :ach]
    assert options.outcomes == [:accepted, :disputed]

    assert_raise Options.Error, ~r/--outcome all cannot be combined/, fn ->
      Options.parse!(["--outcome", "all,accepted", "--seed", "7"])
    end

    assert_raise Options.Error, ~r/--methods all cannot be combined/, fn ->
      Options.parse!([
        "--features",
        "payment-method-types",
        "--methods",
        "all,credit",
        "--seed",
        "7"
      ])
    end
  end

  test "rejects incompatible flags and malformed values" do
    invalid_argv = [
      ["--methods", "credit", "--seed", "5"],
      ["--families", "wallet", "--seed", "5"],
      ["--interaction", "manual", "--execution", "parallel", "--seed", "5"],
      ["--profile", "sandbox-api", "--outcome", "random", "--seed", "5"],
      ["--resume", "run_1", "--dry-run", "--seed", "5"],
      ["--max-concurrency", "0", "--seed", "5"],
      ["--timeout", "-1", "--seed", "5"],
      ["--seed", "-1"],
      ["--features", "invented", "--seed", "5"],
      ["--features", "core,,refunds", "--seed", "5"],
      ["--features", "payment-method-types", "--methods", "", "--seed", "5"],
      ["--wat", "value", "--seed", "5"],
      ["positional", "--seed", "5"]
    ]

    Enum.each(invalid_argv, fn argv ->
      assert {:error, %Options.Error{message: message}} = Options.parse(argv)
      assert is_binary(message) and message != ""
    end)
  end

  test "registry exactly covers the source-locked types and all families once" do
    entries = PaymentMethodRegistry.all()
    expected_types = DodoPayments.Enums.values(:payment_method_type) |> Enum.sort()
    expected_families = DodoPayments.Enums.values(:payment_method_family) |> Enum.sort()

    assert length(entries) == 105
    assert Enum.map(entries, & &1.type) == expected_types
    assert entries |> Enum.map(& &1.type) |> Enum.uniq() |> length() == 105
    assert entries |> Enum.map(& &1.family) |> Enum.uniq() |> Enum.sort() == expected_families
    assert PaymentMethodRegistry.families() == expected_families

    assert Enum.all?(entries, fn %Entry{} = entry ->
             entry.family_source == :inferred and
               entry.support_expectation in [
                 :documented_supported,
                 :merchant_gated,
                 :regional,
                 :device_or_manual_required,
                 :enum_only
               ] and entry.interaction in [:automated, :manual, :unknown]
           end)
  end

  test "registry identity is pinned to the repository source lock" do
    lock_path = Path.expand("../../../../../priv/upstream/source-lock.json", __DIR__)
    lock = lock_path |> File.read!() |> Jason.decode!()
    registry_lock = PaymentMethodRegistry.source_lock()

    assert registry_lock.source == lock["source"]
    assert registry_lock.version == lock["version"]
    assert registry_lock.tarball_sha256 == lock["tarball_sha256"]
    assert Date.to_iso8601(registry_lock.audited_on) == lock["audited_on"]
  end

  test "registry labels evidence honestly instead of treating enum presence as availability" do
    assert %Entry{
             support_expectation: :documented_supported,
             interaction: :automated,
             completion_driver: :test_card
           } = PaymentMethodRegistry.fetch!(:credit)

    assert %Entry{
             support_expectation: :device_or_manual_required,
             interaction: :manual,
             completion_driver: nil
           } = PaymentMethodRegistry.fetch!(:apple_pay)

    assert %Entry{
             support_expectation: :enum_only,
             interaction: :unknown,
             completion_driver: nil
           } = PaymentMethodRegistry.fetch!(:ach)

    assert PaymentMethodRegistry.source_lock().version == "2.47.0"
    assert :error = PaymentMethodRegistry.fetch(:not_a_real_method)
  end

  test "selectors expand the exact requested method scenarios" do
    options =
      Options.parse!([
        "--features",
        "payment-method-types",
        "--methods",
        "credit,ach",
        "--outcome",
        "accepted",
        "--seed",
        "99"
      ])

    scenarios = PaymentMethodRegistry.expand(options)

    assert Enum.map(scenarios, & &1.id) == [
             "payment-method-type:credit:accepted",
             "payment-method-type:ach:accepted"
           ]

    assert Enum.all?(scenarios, &(&1.verification_target == :local_contract))
  end

  test "random outcomes replay from a seed and all expands every lifecycle" do
    random =
      Options.parse!([
        "--features",
        "payment-method-types",
        "--methods",
        "credit,ach",
        "--outcome",
        "random",
        "--seed",
        "2026"
      ])

    first = PaymentMethodRegistry.expand(random)
    second = PaymentMethodRegistry.expand(random)

    assert first == second
    assert Enum.all?(first, &(&1.outcome in Options.lifecycle_outcomes()))
    assert Enum.all?(first, &(&1.seed == 2026))

    all =
      Options.parse!([
        "--features",
        "payment-method-types",
        "--methods",
        "credit",
        "--outcome",
        "all",
        "--seed",
        "2026"
      ])

    assert PaymentMethodRegistry.expand(all) |> Enum.map(& &1.outcome) ==
             Options.lifecycle_outcomes()
  end

  test "refund and dispute features cannot pass without their causal lifecycle" do
    assert_raise Options.Error, ~r/features refunds requires/, fn ->
      Options.parse!(["--features", "refunds", "--outcome", "accepted", "--seed", "3"])
    end

    refund =
      Options.parse!(["--features", "refunds", "--outcome", "all", "--seed", "3"])

    dispute =
      Options.parse!(["--features", "disputes", "--outcome", "disputed", "--seed", "3"])

    assert [%{feature: :refunds, outcome: :refunded}] = PaymentMethodRegistry.expand(refund)
    assert [%{feature: :disputes, outcome: :disputed}] = PaymentMethodRegistry.expand(dispute)
  end

  test "explicit seeds make every random lifecycle reachable and replayable" do
    observed =
      0..100
      |> Enum.map(fn seed ->
        options = Options.parse!(["--outcome", "random", "--seed", Integer.to_string(seed)])
        [%{outcome: outcome, seed: ^seed}] = PaymentMethodRegistry.expand(options)
        outcome
      end)
      |> MapSet.new()

    assert observed == MapSet.new(Options.lifecycle_outcomes())
  end

  test "all expands every feature, method, family, and lifecycle without ambiguity" do
    options = Options.parse!(["--features", "all", "--outcome", "all", "--seed", "8"])
    scenarios = PaymentMethodRegistry.expand(options)

    # Core, every type, every family, and resilience each expand to all seven
    # checkout lifecycles. Refund and dispute features retain only the matching
    # causal terminal path.
    assert length(scenarios) == 122 * 7 + 2
    assert scenarios |> Enum.map(& &1.id) |> Enum.uniq() |> length() == length(scenarios)
  end

  test "the default combined inventory retains causal refund and dispute scenarios" do
    options = Options.parse!(["--features", "all", "--seed", "18"])
    scenarios = PaymentMethodRegistry.expand(options)
    ids = MapSet.new(scenarios, & &1.id)

    assert MapSet.member?(ids, "refunds:refunded")
    assert MapSet.member?(ids, "disputes:disputed")
    assert length(scenarios) == 124
  end

  test "Mix task dry-run prints the replay seed and exact plan" do
    output =
      capture_io(fn ->
        Mix.Tasks.Dodo.Smoke.run([
          "--features",
          "payment-method-types",
          "--methods",
          "credit",
          "--outcome",
          "disputed",
          "--seed",
          "17",
          "--dry-run"
        ])
      end)

    assert output =~ "Dodo smoke seed: 17"
    assert output =~ "scenarios=1"
    assert output =~ "PLAN payment-method-type:credit:disputed"
    refute output =~ "dodo_test_"
  end
end
