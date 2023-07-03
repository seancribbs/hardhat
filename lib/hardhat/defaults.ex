defmodule Hardhat.Defaults do
  @moduledoc """
  Contains default implementations of functions that can be overridden in
  clients that `use Hardhat`.
  """

  @doc """
  The default options for the connection pool that will be created when your
  client is added to the supervision tree.

  This creates a connection pool of size `10`.
  """
  def pool_options(_overrides \\ []) do
    %{
      default: [size: 10]
    }
  end
end
