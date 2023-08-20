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
      defdelegate should_melt(env), to: Hardhat.Defaults
      defdelegate deadline_propagation_opts(), to: Hardhat.Defaults

      @doc false
      def fuse_opts() do
        Hardhat.Defaults.fuse_opts(__MODULE__)
      end

      defoverridable pool_options: 1, should_melt: 1, fuse_opts: 0, deadline_propagation_opts: 0
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      plug(Hardhat.Middleware.DeadlinePropagation, __MODULE__.deadline_propagation_opts())
      plug(Tesla.Middleware.Fuse, __MODULE__.fuse_opts())
      plug(Tesla.Middleware.Telemetry)
      plug(Tesla.Middleware.OpenTelemetry)
      plug(Hardhat.Middleware.PathParams)
    end
  end
end
