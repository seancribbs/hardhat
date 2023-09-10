defmodule Hardhat.Middleware.Regulator do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env = %Tesla.Env{}, next, opts) do
    # Ensure that the regulator is installed
    {should_regulate, opts} = Keyword.pop!(opts, :should_regulate)
    regname = Module.concat(env.__module__, Regulator)

    # [RACE] If the limiter isn't installed yet, `ask` will exit `noproc`
    # looking for the child "monitor" process. Unfortunately we have to call `Regulator.install`
    # on every invocation so that we are blocked by the supervisor's `start_child` call.
    #
    # If the limiter is already installed, this will return {:error, {:already_started, pid()}}.
    _ = Regulator.install(regname, {Regulator.Limit.AIMD, opts})

    case Regulator.ask(regname) do
      {:ok, token} ->
        result = Tesla.run(env, next)

        if should_regulate.(result) do
          Regulator.error(token)
        else
          Regulator.ok(token)
        end

        result

      :dropped ->
        {:error, :unavailable}
    end
  end
end
