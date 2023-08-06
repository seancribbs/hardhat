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

  @doc """
  Default implementation of the "melt test" for circuit breaking. This
  function will cause the circuit breaker to record an error when the
  result of a request is:

  * A TCP-level error, e.g. `{:error, :econnrefused}`
  * An HTTP status that indicates a server error or proxy-level error (>= 500)
  * An `429 Too Many Requests` HTTP status
  """
  def should_melt({:error, _}) do
    true
  end

  def should_melt({:ok, %Tesla.Env{} = env}) do
    env.status >= 500 || env.status == 429
  end
end
