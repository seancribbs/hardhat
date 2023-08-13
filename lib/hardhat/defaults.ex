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

  @doc """
  Default implementation of the options to the `Tesla.Middleware.Fuse` that is
  included in the default middleware stack.

  Takes the client module name as an argument.

  These defaults include:
  - `:opts` - The fuse will blow after 50 errors with 1 second, and reset after 2 seconds
  - `:keep_original_error` - The original error will be returned when a fuse first blows
  - `:should_melt` - The `should_melt/1` function defined in the client module is used
     (by default this is `Hardhat.Defaults.should_melt/1`)
  - `:mode` - The fuse uses `:async_dirty` mode to check the failure rate, which may result
    in some delay in blowing the fuse under high concurrency, but it will not serialize
    checks to the fuse state through a single process

  See `Tesla.Middleware.Fuse` for more information on how to configure the middleware.
  """
  def fuse_opts(mod) do
    [
      opts: {{:standard, 50, 1_000}, {:reset, 2_000}},
      keep_original_error: true,
      should_melt: &mod.should_melt/1,
      mode: :async_dirty
    ]
  end
end
