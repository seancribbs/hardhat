defmodule Hardhat.MixProject do
  use Mix.Project

  def project do
    [
      app: :hardhat,
      version: "1.0.0-rc.2",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An opinionated, production-ready HTTP client for Elixir services.",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.7"},
      {:finch, "~> 0.16.0"},
      {:telemetry, "~> 1.2"},
      {:opentelemetry_tesla, "~> 2.2"},
      {:opentelemetry, "~> 1.3", only: :test},
      {:opentelemetry_process_propagator, "~> 0.2.2"},
      {:fuse, "~> 2.5"},
      {:regulator, "~> 0.5.0"},
      {:deadline, "~> 0.7.1"},
      # NOTE: Upgrade ex_doc past 0.30.6 when they fix the broken CSS
      {:ex_doc, "0.30.6", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4.0", only: :dev},
      {:bypass, "~> 2.1.0", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/seancribbs/hardhat"
      }
    ]
  end

  defp docs do
    [
      main: "Hardhat"
    ]
  end
end
