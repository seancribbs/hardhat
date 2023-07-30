defmodule Hardhat.Builder do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    quote do
      @before_compile Hardhat.Builder
      # docs: false
      use Tesla.Builder, unquote(opts)

      adapter(Tesla.Adapter.Finch, name: __MODULE__)

      @doc false
      def child_spec(opts \\ []) do
        Supervisor.child_spec({Finch, name: __MODULE__, pools: pool_options(opts)},
          id: __MODULE__
        )
      end

      defdelegate pool_options(overrides), to: Hardhat.Defaults

      defoverridable pool_options: 1
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      plug(Tesla.Middleware.Telemetry)
      plug(Tesla.Middleware.OpenTelemetry)
      plug(Hardhat.Middleware.PathParams)
    end
  end
end
