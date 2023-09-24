defmodule Hardhat do
  @external_resource "README.md"
  @moduledoc "README.md" |> File.read!() |> String.split("<!-- MDOC -->") |> Enum.at(1)

  defmacro __using__(opts \\ []) do
    quote do
      use Hardhat.Builder, unquote(opts)
    end
  end

  use Hardhat.Builder
end
