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

  @doc """
  Default implementation of the options to `Hardhat.Middleware.DeadlinePropagation` that
  is included in the default middleware stack.

  These defaults include:
  - `:header` - `"deadline"` is the name of the header added to the request
  """
  def deadline_propagation_opts() do
    [header: "deadline"]
  end

  @doc """
  Default implementation of the options to `Tesla.Middleware.Retry` that is
  included in the default middleware stack.

  These defaults include:
  - `:delay` - The base delay in milliseconds (positive integer, defaults to 50)
  - `:max_retries` - maximum number of retries (non-negative integer, defaults to 3)
  - `:max_delay` - maximum delay in milliseconds (positive integer, defaults to 300)
  - `:should_retry` - function to determine if request should be retried, defaults to `should_retry/1`
  - `:jitter_factor` - additive noise proportionality constant (float between 0 and 1, defaults to 0.2)
  """
  def retry_opts(mod) do
    [
      delay: 50,
      max_retries: 3,
      max_delay: 300,
      should_retry: &mod.should_retry/1,
      jitter_factor: 0.2
    ]
  end

  @doc """
  Default implementation of the "retry test" for retries. This
  function will cause requests to be retried when the result of the
  request is:

  * A TCP-level error, e.g. `{:error, :econnrefused}`
  * An HTTP status that indicates a server error or proxy-level error (>= 500)
  * An `429 Too Many Requests` HTTP status

  In the case where the circuit breaker has been triggered, requests will
  not be retried.
  """
  def should_retry({:error, :unavailable}), do: false

  def should_retry({:error, _}), do: true

  def should_retry({:ok, %Tesla.Env{} = env}) do
    env.status == 429 || env.status >= 500
  end

  @doc """
  Default options for the `Regulator` middleware, which can be used as an
  alternative circuit-breaking strategy to `:fuse`.

  The defaults include:
  * `:min_limit` - The minimum concurrency limit (defaults to 5)
  * `:initial_limit` - The initial concurrency limit when the regulator is installed (deafults to 20)
  * `:max_limit` - The maximum concurrency limit (defaults to 200)
  * `:step_increase` - The number of tokens to add when regulator is increasing the concurrency limit (defaults to 10).
  * `:backoff_ratio` - Floating point value for how quickly to reduce the concurrency limit (defaults to 0.9)
  * `:target_avg_latency` - This is the average latency in milliseconds for the system regulator is protecting. If the average latency drifts above this value Regulator considers it an error and backs off. Defaults to 5.
  * `:should_regulate` - Whether to consider the result of the request as failed, defaults to `should_regulate/1`.
  """
  def regulator_opts(mod) do
    [
      min_limit: 5,
      initial_limit: 20,
      max_limit: 200,
      backoff_ratio: 0.9,
      target_avg_latency: 5,
      step_increase: 10,
      should_regulate: &mod.should_regulate/1
    ]
  end

  @doc """
  Default implementation of the "failure test" for dynamic regulation. This
  function will cause the `Regulator` to record an error when the
  result of a request is:

  * A TCP-level error, e.g. `{:error, :econnrefused}`
  * An HTTP status that indicates a server error or proxy-level error (>= 500)
  * An `429 Too Many Requests` HTTP status
  """
  def should_regulate({:error, _}) do
    true
  end

  def should_regulate({:ok, %Tesla.Env{} = env}) do
    env.status >= 500 || env.status == 429
  end
end
