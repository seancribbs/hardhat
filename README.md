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

As mentioned in the example above, it is imperative for you to supervise the client module that includes the `use Hardhat` macro. Without starting the client under supervision, you will not be able to make requests. See [Connection pools](#module-connection-pools) below for more information.

## General behavior

TODO: Contents of the default middleware, link to other sections

`Hardhat` is built on top of `Tesla`, and uses `Finch` as the adapter. Because
`Tesla` is the foundation, you are welcome to utilize publicly available
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
* `Tesla.Middleware.Retry`
* Either `Tesla.Middleware.Fuse` or `Hardhat.Middleware.Regulator` ([See below](#module-failure-detection)
* `Tesla.Middleware.Telemetry`
* `Tesla.Middleware.OpenTelemetry`
* `Hardhat.Middleware.PathParams`

## Connection pools

TODO: Sizing the pool, `Finch` options

## Telemetry and tracing

TODO: `:telemetry` events, `OpenTelemetry` spans and events, propagation

## Failure detection

TODO: `:fuse` mode and configuration, `Regulator` mode and configuration

## Retries

TODO: default options, note about interactions with failure detection

## Timeouts and deadlines

TODO: Custom timeout middleware, `Deadline` support

## Testing

TODO: overriding the adapter to use a mock or bypass
