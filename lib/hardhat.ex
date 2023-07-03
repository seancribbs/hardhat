defmodule Hardhat do
  @moduledoc "README.md" |> File.read!() |> String.split("<!-- MDOC -->") |> Enum.at(1)

  defmacro __using__(opts \\ []) do
    quote do
      use Hardhat.Builder, unquote(opts)
    end
  end
end
