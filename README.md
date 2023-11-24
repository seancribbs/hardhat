# hardhat

[![Build status](https://github.com/seancribbs/hardhat/actions/workflows/ci.yaml/badge.svg)](https://github.com/seancribbs/hardhat/actions/workflows/ci.yaml) [![Hex.pm](https://img.shields.io/hexpm/v/hardhat.svg)](https://hex.pm/packages/hardhat)

<!-- MDOC -->
An opinionated, production-ready HTTP client for Elixir services. 👷🌐

## What's included

- Connection pooling per-client module
- Integration with `telemetry` and `opentelemetry` instrumentation
- Circuit breaking for repeatedly failed requests
- Automatic retries for failed requests
- Timeout and `deadline` support

## Why Hardhat?

In 2021, my employer was in the process of [refactoring its monolithic Phoenix application into a small number of decoupled services](https://www.youtube.com/watch?v=Py8WK4rBNqQ), so we needed better reliability and observability at the boundaries of our services. We had experienced multiple production incidents related to exhaustion of a single, shared connection pool for outgoing HTTP requests. Additionally, we had built a number of custom clients for external SaaS APIs but had no consistency between them.

I set out to address these problems by creating a standard HTTP client library, upon which individual teams could build clients for internal and external APIs and get reliability and observability, relatively for-free. `Hardhat` was born (its name comes from "hardened HTTP client", and that you should wear a hardhat to protect your head in dangerous construction areas).

`Hardhat` attempts to walk the line of baking-in sensible defaults so the upfront effort is minimal, but also allowing you to customize and extend almost every part of the built-in functionality. It is not a low-level HTTP client, but adds functionality on top of `Tesla` and `Finch`, and draws upon well-crafted libraries like `:opentelemetry`, `:telemetry`, `:fuse`, `Regulator`, and `Deadline`.

Regrettably, my employer did not see fit to release `Hardhat` as open-source software, so this library recreates it from scratch, built only from my own recollections and the help of the community.

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

* `Hardhat.Middleware.DeadlinePropagation` ([see below](#module-deadline-propagation))
* `Tesla.Middleware.Retry` ([see below](#module-retries))
* Either `Tesla.Middleware.Fuse` or `Hardhat.Middleware.Regulator` ([see below](#module-failure-detection))
* `Tesla.Middleware.Telemetry` ([see below](#module-telemetry-and-tracing))
* `Tesla.Middleware.OpenTelemetry` ([see below](#module-telemetry-and-tracing))
* `Hardhat.Middleware.PathParams`

Each of the included middlewares that have configuration have defaults defined by functions in `Hardhat.Defaults` and can be customized by defining a function of the same name in your client module. Inside those functions you can set your own static defaults or get runtime configuration using `Application.get_env/3`. The [options](`t:Keyword.t/0`) you return will be merged with the defaults when the middleware is invoked. Examples of this pattern are in each of the sections below.

## Connection pools

As mentioned above, `Hardhat` uses `Finch` as the adapter. By [default](`Hardhat.Defaults.pool_configuration/1`), `Hardhat` specifies a connection pool of size `10` but sets no [other options](`Finch.start_link/1`) on the adapter. The name of the `Finch` process is proscribed by the `use Hardhat` macro, but you can set any other options for the pool that you like, including creating more than one pool or setting the HTTP protocol or TLS options by overriding the `pool_configuration/1` function.

```elixir
defmodule H2Client do
  use Hardhat

  # This function overrides the configuration coming from `Hardhat.Defaults`.
  # The `overrides` will be passed from your process supervision initial
  # arguments.
  def pool_configuration(_overrides \\ %{}) do
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
* Dynamic request rate regulation ([AIMD](`Regulator.Limit.AIMD`)) with `Regulator` (via `Hardhat.Middleware.Regulator`)

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
      opts: {{:standard, 10, 500}, {:reset, 1_000}}
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
      backoff_ratio: 0.5
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

### Disabling failure detection

> #### Warning {: .warning}
> We do not recommend disabling failure detection and backoff strategies because they expose you to encountering cascading failure and slowdown when the target service or network is encountering issues.

If you want to disable failure detection, set the strategy to `:none`:

```elixir
defmodule WildAndFree do
  use Hardhat, strategy: :none
end
```

## Retries

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
      max_delay: 500
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

Timeouts are an essential liveness technique that help prevent your application from waiting a long time for a slow response to come back from a request. Deadlines extend the timeout pattern to cover entire workflows spanning multiple services, and ensure responsiveness for requests at the edge of your infrastructure while avoiding doing work that will not complete in a timely fashion.

Hardhat supports both individual timeouts and global deadlines via its custom `Hardhat.Middleware.Timeout` middleware, but it is **not** included in the default middleware stack.

When a timeout value is specified in the middleware options, the lesser of that value and any active deadline will be used for the timeout duration. If the configured timeout is shorter than the active deadline, the deadline propagated downstream will be set to the shorter timeout value.

```elixir
defmodule TimeoutClient do
  use Hardhat

  # Requests will time out after 100ms
  plug Hardhat.Middleware.Timeout, timeout: 100
end

# Set a deadline of 50ms
Deadline.set(50)

# This will timeout after 50ms instead of the configured 100ms
TimeoutClient.get("http://google.com")

# Set a deadline of 500ms
Deadline.set(500)

# This will timeout after 100ms (not 500ms), propagating a deadline of 100ms
TimeoutClient.get("http://elixir-lang.org")
```

When a timeout occurs, a `:timeout_exceeded` event will be added to the current `OpenTelemetry` span.

> ### Using `Tesla.Middleware.Timeout` instead {: .warning}
> Because implementing timeouts requires spawning a process that carries out the rest of the request, we recommend using `Hardhat`'s bundled timeout middleware. If you use the standard middleware bundled with `Tesla`, you must propagate `OpenTelemetry` context and `Deadline` information yourself.

### Deadline propagation

The default middleware stack will propagate any `Deadline` you have set for the current process, regardless of whether you are using the `Hardhat.Middleware.Timeout` middleware in your client. The propagation consists of a request header (default `"deadline"`) whose value is the current deadline as an integer in milliseconds. To change the header name, override the [`deadline_propagation_opts`](`Hardhat.Defaults.deadline_propagation_opts/0`) callback:

```elixir
defmodule CustomPropagationClient do
  use Hardhat

  def deadline_propagation_opts do
    [
      header: "countdown-expires-in"
    ]
  end
end
```

## Testing

Testing HTTP clients can be tricky, partly because they are software designed to interact with the outside world. Here are the primary strategies that one can take when testing `Hardhat` clients:

* [`Mox`](https://hexdocs.pm/mox/Mox.html), which can generate a mock `Tesla.Adapter`.
* [`Bypass`](https://hexdocs.pm/bypass/Bypass.html), which runs a `Plug` web server to handle requests from your client.
* [`ExVCR`](https://hexdocs.pm/exvcr/readme.html), which replaces the adapter-level library with a double that records and replays responses.

We do not recommend using `Tesla.Mock` for testing. Any of the three options above have superior behavior under complicated testing conditions, including spawning child processes via timeouts.

### `Mox`

`Mox` allows us to define a custom `Tesla.Adapter` for use only in tests. First, we need to generate the mock adapter (put this in `test_helper.exs`):

```elixir
Mox.defmock(MockAdapter, for: Tesla.Adapter)
```

Then configure your `Hardhat`-based client to use this adapter in `config/test.exs`:

```elixir
import Config

config :tesla, MyHardhatClient, adapter: MockAdapter
```

Then in your tests, set expectations on the adapter:

```elixir
defmodule MyHardhatClient.Test do
  use ExUnit.Case, async: true
  import Mox

  # Checks your mock expectations on each test
  setup :verify_on_exit!

  test "it works" do
    expect(MockAdapter, :call, fn env, opts -> {:ok, %{env | status: 204}} end)

    assert {:ok, %Tesla.Env{status: 204}} = MyHardhatClient.get("https://foo.bar/")
  end
end
```

This setup will work even if you are using `Hardhat.Middleware.Timeout` in your middleware, as child processes automatically inherit expectations and stubs defined by `Mox`.

### `Bypass`

`Bypass` starts a web server in a new process that handles requests from your client. In order to use it effectively in tests, you will need to be able to set the hostname for each request (or for the current process), which might be challenging if you are already using `Tesla.Middleware.BaseUrl` in your client. One strategy using the process dictionary is shown below:

```elixir
defmodule ClientWithBypassUrl do
  use Hardhat

  plug Tesla.Middleware.BaseUrl, base_url()

  def base_url do
    Process.get(:bypass_url) ||
      Application.get_env(:my_app, __MODULE__, [])[:base_url]
  end
end
```

And then in the test:

```elixir
defmodule ClientWithBypassUrl.Test do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    Process.put(:bypass_url, "http://localhost:#{bypass.port}")
    {:ok, %{bypass: bypass}}
  end

  test "works with bypass", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 204, "") end)

    assert {:ok, %Tesla.Env{status: 204}} = ClientWithBypassUrl.get("/test")
  end
end
```

### `ExVCR`

[`exvcr`](https://hexdocs.pm/exvcr) intercepts calls into specific HTTP client libraries (like `Finch`) and returns pre-determined responses. Developers can execute tests in a recording mode, which will initialize the "cassettes" by executing real requests and recording the real responses into JSON files on disk. Once recorded, a call to `use_cassette` inside the test selects a particular session for replay.

```elixir
defmodule PreRecordedClient.Test do
  use ExUnit.Case, async: true
  # Be sure to set Finch as the adapter in this call, or whatever you configured
  # your Hardhat client to use
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

  test "returns a recorded response" do
    use_cassette "example" do
      assert {:ok, %Tesla.Env{status: 204}} = PreRecordedClient.get("/")
    end
  end
end
```
