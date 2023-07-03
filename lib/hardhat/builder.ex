defmodule Hardhat.Builder do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    quote do
      use Tesla.Builder, unquote(opts)
    end
  end
end
