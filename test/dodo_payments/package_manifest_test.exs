defmodule DodoPayments.PackageManifestTest do
  use ExUnit.Case, async: true

  test "Hex package manifest excludes the development example" do
    files = DodoPayments.MixProject.project()[:package][:files]

    refute "examples" in files
    refute Enum.any?(files, &String.starts_with?(&1, "examples/"))
    refute "guides" in files
    refute "priv" in files
    assert "lib" in files
    assert "priv/upstream/source-lock.json" in files
    assert "guides/setup-and-configuration.md" in files
    assert "guides/retries-and-outcomes.md" in files
    assert "guides/custom-clients.md" in files
    assert "guides/deadline-workers-and-client-trust.md" in files
    refute "guides/e2e-constrained-operations.md" in files
  end
end
