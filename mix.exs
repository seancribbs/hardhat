defmodule Hardhat.MixProject do
  use Mix.Project

  def project do
    [
      app: :hardhat,
      version: "0.1.0-alpha.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An opinionated, production-ready HTTP client for Elixir services.",
      package: package()
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
      # {:recon, "~> 2.5.3", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3.0", only: :dev},
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
end
