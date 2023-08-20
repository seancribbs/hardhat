defmodule Hardhat.Middleware.DeadlinePropagation do
  @moduledoc """
  Propagates `Deadline` information across the request to the
  server being called.
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
