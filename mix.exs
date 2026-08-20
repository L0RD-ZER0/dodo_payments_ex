defmodule DodoPayments.MixProject do
  use Mix.Project

  @version "VERSION" |> File.read!() |> String.trim()
  @source_url "https://github.com/L0RD-ZER0/dodo_payments_ex"

  def project do
    [
      app: :dodo_payments,
      version: @version,
      elixir: "~> 1.15",
      source_url: @source_url,
      homepage_url: @source_url,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An explicit, Req-first Elixir SDK for Dodo Payments",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      mod: {DodoPayments.Application, []},
      extra_applications: [:crypto, :logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7.3"},
      {:finch, "~> 0.21"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.1 or ~> 3.0"},
      {:telemetry, "~> 1.2"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:plug, "~> 1.16", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md",
        "Dodo Payments" => "https://www.dodopayments.com",
        "Dodo Payments API documentation" => "https://docs.dodopayments.com"
      },
      files: ~w(
          lib
          priv/upstream/source-lock.json
          guides/setup-and-configuration.md
          guides/retries-and-outcomes.md
          guides/custom-clients.md
          guides/deadline-workers-and-client-trust.md
          mix.exs
          .formatter.exs
          VERSION
          README.md
          PHOENIX_EXAMPLE.md
          LICENSE
          CHANGELOG.md
          SECURITY.md
        )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "PHOENIX_EXAMPLE.md",
        "guides/setup-and-configuration.md",
        "guides/retries-and-outcomes.md",
        "guides/custom-clients.md",
        "guides/deadline-workers-and-client-trust.md",
        "CHANGELOG.md",
        "SECURITY.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Client: [DodoPayments.Client, DodoPayments.ClientModule, DodoPayments.ReqClient],
        Webhooks: ~r/^DodoPayments\.Webhooks/,
        Errors: ~r/^DodoPayments\.(?:Error(?:\.|$)|ValidationError$)/
      ]
    ]
  end
end
