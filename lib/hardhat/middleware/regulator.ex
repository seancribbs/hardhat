defmodule Hardhat.Middleware.Regulator do
  @moduledoc """
  Limits concurrent requests to the server based on a [loss based dynamic limit algorithm](`Regulator.Limit.AIMD`).
  Additively increases the concurrency limit when there are no errors and multiplicatively
  decrements the limit when there are errors.

  _This middleware is part of the default stack when giving the `strategy: :regulator` option to `use Hardhat`._

  See also:
  - Configuration options: `Hardhat.Defaults.regulator_opts/1`
  - Determining what amounts to an error: `Hardhat.Defaults.should_regulate/1`
  """
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env = %Tesla.Env{}, next, opts) do
    should_regulate = Keyword.fetch!(opts, :should_regulate)
    regname = Module.concat(env.__module__, Regulator)

    with true <- is_pid(Process.whereis(regname)),
         {:ok, token} <- Regulator.ask(regname) do
      result = Tesla.run(env, next)

      if should_regulate.(result) do
        Regulator.error(token)
      else
        Regulator.ok(token)
      end

      result
    else
      false ->
        {:error, {:regulator_not_installed, regname}}

      :dropped ->
        {:error, :unavailable}
    end
  end
end
