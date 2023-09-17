defmodule Hardhat.Middleware.DeadlinePropagation do
  @moduledoc """
  Propagates `Deadline` information to the server being called via
  an HTTP header. _This middleware is part of the default stack_.

  Expects a `:header` option, which defaults to `"deadline"`. See `Hardhat.Defaults.deadline_propagation_opts/0`.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    header = Keyword.fetch!(opts, :header)

    env =
      case Deadline.time_remaining() do
        :infinity -> env
        value -> Tesla.put_header(env, header, to_string(value))
      end

    Tesla.run(env, next)
  end
end
