defmodule Hardhat.Middleware.Regulator do
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
