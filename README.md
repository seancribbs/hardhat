# hardhat

[![Build status](https://github.com/seancribbs/hardhat/actions/workflows/ci.yaml/badge.svg)](https://github.com/seancribbs/hardhat/actions/workflows/ci.yaml) [![Hex.pm](https://img.shields.io/hexpm/v/hardhat.svg)](https://hex.pm/packages/hardhat)

<!-- MDOC -->
An opinionated, production-ready HTTP client for Elixir services.

## What's included

- [X] Connection pooling per-client module
- [X] Integration with `telemetry` and `opentelemetry` instrumentation
- [X] Circuit breaking for repeatedly failed requests
- [X] Automatic retries for failed requests
- [X] Timeout and `deadline` support

## Why Hardhat?

TODO

## Installation

Add `hardhat` to the dependencies in your `mix.exs`:

```elixir
  def deps do
    [
      {:hardhat, "~> 1.0.0"}
    ]
  end
```

## Getting started

`Hardhat` is designed to be easy for creating quick wrappers around HTTP APIs,
but includes many options for customization. To define a simple client, do something like the following:

```elixir
# Define a client module:
defmodule SocialMediaAPI do
  use Hardhat
end

# Add it to your supervisor (required):
defmodule MyApp.Sup do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      SocialMediaAPI
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Use your client to make requests:
SocialMediaAPI.get("http://media-api.social/posts")
```

As mentioned in the example above, it is **imperative** for you to supervise the client module that includes the `use Hardhat` macro. Without starting the client under supervision, you will not be able to make requests. See [Connection pools](#module-connection-pools) below for more information.

## General behavior

`Hardhat` is built on top of `Tesla`, and uses `Finch` as the adapter. Because
`Tesla` is the foundation, you are welcome to use publicly available
`Tesla.Middleware` modules in your `Hardhat`-based client (with the exception
that [we recommend](#module-timeouts-and-deadlines) you use
`Hardhat.Middleware.Timeout` instead of `Tesla.Middleware.Timeout`).

```elixir
defmodule SomeJSONAPI do
  use Hardhat

  plug Tesla.Middleware.BaseUrl, "https://my-json.api/"
  plug Tesla.Middleware.JSON
end
```

In addition to the adapter selection and default `Tesla` behavior,
`use Hardhat` will inject the common functionality [listed above](#module-what-s-included) *after* any middleware that you supply via [`plug`](`Tesla.Builder.plug/2`). The current list is as follows:

* `Hardhat.Middleware.DeadlinePropagation`
* `Tesla.Middleware.Retry` ([see below](#module-retries))
* Either `Tesla.Middleware.Fuse` or `Hardhat.Middleware.Regulator` ([See below](#module-failure-detection)
* `Tesla.Middleware.Telemetry` ([see below](#module-telemetry-and-tracing))
* `Tesla.Middleware.OpenTelemetry` ([see below](#module-telemetry-and-tracing))
* `Hardhat.Middleware.PathParams`

## Connection pools

As mentioned above, `Hardhat` uses `Finch` as the adapter. By [default](`Hardhat.Defaults.pool_options/1`), `Hardhat` specifies a connection pool of size `10` but sets no [other options](`Finch.start_link/1`) on the adapter. The name of the `Finch` process is proscribed by the `use Hardhat` macro, but you can set any other options for the pool that you like, including creating more than one pool or setting the HTTP protocol or TLS options by overriding the `pool_options/1` function.

```elixir
defmodule H2Client do
  use Hardhat

  # This function overrides the default coming from `Hardhat.Defaults`.
  # The `overrides` will be passed from your process supervision initial
  # arguments.
  def pool_options(_overrides \\ []) do
    %{
      # By default we'll use HTTP/2, with 3 pools of one connection each
      :default => [
        protocol: :http2,
        count: 3
      ],
      # For this host only, we're using HTTP/1.1 and a single pool of 20
      # connections
      "https://some-http1-only-host.com/" => [
        size: 20
      ]
    }
  end
end
```

## Telemetry and tracing

`Hardhat` includes the stock `Tesla.Middleware.Telemetry` for injecting your own metrics and monitoring systems into its operation. The events emitted by this middleware are:

* `[:tesla, :request, :start]` - at the beginning of the request
* `[:tesla, :request, :stop]` - at the completion of the request
* `[:tesla, :request, :exception]` - when a non-HTTP-status exception occurs

```elixir
defmodule TelemetryClient do
  use Hardhat
end

:telemetry.attach(
  "my handler",
  [:tesla, :request, :stop],
  fn _event, measures, _metadata, _config ->
     # Don't do this, attach to your metrics system instead
     IO.puts("Made a request in #{measures.duration}")
  end,
  nil
)
```

`Hardhat` wraps each request in an [OpenTelemetry](`Tesla.Middleware.OpenTelemetry`) span and propagates the trace context to the destination host. It does not currently expose the ability to change the span name in the trace, but it will observe any [path parameters](`Hardhat.Middleware.PathParams`) you interpolate into the URL so that similar spans can be easily aggregated.

## Failure detection

`Hardhat` provides two different failure detection and backoff strategies:

* Static circuit breaking with `:fuse` (`Tesla.Middleware.Fuse`)
* Dynamic request rate regulation ([AIMD](`Regulator.Limit.AIMD`) with `Regulator` (`Hardhat.Middleware.Regulator`)

These strategies cannot be used together safely, so you must choose one when defining your client. If your needs are simple and hard failures are relatively rare, `:fuse` is an easier strategy to comprehend and implement because it uses a straightforward failure-counting algorithm, and completely turns off requests when the configured threshold is reached. If you have a more complicated setup or high traffic, and do not want to spend as much time tuning your failure behavior, the `:regulator` strategy might be for you. `Regulator` allows your client to adapt to rapidly changing conditions by reducing the amount of concurrent work in the presence of failure, without causing a hard stop to activity. On the other hand, if your concurrent utilization is low, it might also bound your maximum concurrency even when requests are not failing.

### The Fuse strategy

The `:fuse` failure detection strategy is configured with two functions in your client which have default implementations that are injected at compile-time:

* [`fuse_opts()`](`Hardhat.Defaults.fuse_opts/1`) - configuration for the middleware
* [`should_melt(result)`](`Hardhat.Defaults.should_melt/1`) - whether the result of the request is considered a failure

You can override their default behavior by redefining the functions:

```elixir
# This module uses `:fuse` for failure detection and backoff.
defmodule HardCutoffClient do
  use Hardhat # defaults to `:fuse`

  # This is also valid:
  # use Hardhat, strategy: :fuse

  # Customize fuse's circuit-breaking behavior
  def fuse_opts do
    [
      # 10 failed requests in 0.5sec flips the breaker, which resets after 1sec
      opts: {{:standard, 10, 500}, {:reset, 1_000}},
      # Return the error that caused the fuse to break
      keep_original_error: true,
      # Use our custom failure test
      should_melt: &__MODULE__.should_melt/1
      # Go fast and a little loose
      mode: :async_dirty
    ]
  end

  # Customize how responses are determined to be failures,
  # in this case only TCP/adapter-type errors are considered
  # failures, any valid response is fine.
  def should_melt(result) do
    case result do
      {:error, _} -> true
      {:ok, %Tesla.Env{}} -> false
    end
  end
end
```

### The Regulator strategy

The `:regulator` failure detection strategy is configured with two functions in your client which have default implementations that are injected at compile-time:

* [`regulator_opts()`](`Hardhat.Defaults.regulator_opts/1`) - configuration for the middleware
* [`should_regulate(result)`](`Hardhat.Defaults.should_regulate/1`) - whether the result of the request is considered a failure

You can override their default behavior by redefining the functions:

```elixir
# This module uses `Regulator` for failure detection and backoff
defmodule DynamicRegulationClient do
  use Hardhat, strategy: :regulator # overrides default of `:fuse`

  # Customize Regulator's ramp-up and backoff strategy
  def regulator_opts do
    [
      # Backoff on failure by half instead of 90%
      backoff_ratio: 0.5,
      should_regulate: &__MODULE__.should_regulate/1
    ]
  end

  # Customize how responses are determined to be failures,
  # in this case TCP/adapter-level errors are considered failures,
  # as well as HTTP `429 Too Many Requests` responses.
  def should_regulate(result) do
    case result do
      {:error, _} -> true
      {:ok, %Tesla.Env{status: 429}} -> true
      {:ok, %Tesla.Env{}} -> false
    end
  end
end
```
## Retries

TODO: default options, note about interactions with failure detection

`Hardhat` injects automatic retries on your requests using `Tesla.Middleware.Retry`. Retries are configured with two functions in your client which have default implementations that are injected at compile-time:

* [`retry_opts()`](`Hardhat.Defaults.retry_opts/1`) - configuration for the middleware
* [`should_retry(result)`](`Hardhat.Defaults.should_retry/1`) - whether the result of the request can be retried

You can override their default behavior by redefining the functions:

```elixir
# This client retries requests
defmodule SomeRetriesClient do
  use Hardhat

  def retry_opts do
    [
      # Retry up to 5 times
      max_retries: 5,
      # Delay at least 75ms between attempts
      delay: 75,
      # Delay at most 500ms between any attempts
      max_delay: 500,
      # Use the default retry rubric
      should_retry: &__MODULE__.should_retry/1,
      # Add jitter of up to 20% to delays
      jitter_factor: 0.2
    ]
  end
end

# This client disables retries entirely!
defmodule NoRetriesClient do
  use Hardhat

  # Override should_retry to disable retries
  def should_retry(_), do: false
end
```

> ### Interaction with failure detection {: .warning}
> Retries can interact very negatively with [failure detection](#module-failure-detection), potentially triggering backoff behavior too quickly. Be sure to avoid retrying when the failure detector returns `{:error, :unavailable}`, which indicates that the circuit breaker has blown in the `:fuse` strategy, or the limiter is out of capacity in the `:regulator` strategy.
>
> The default implementation of `should_retry/1` implements this behavior.

## Timeouts and deadlines

TODO: Custom timeout middleware, `Deadline` support

## Testing

TODO: overriding the adapter to use a mock or bypass
