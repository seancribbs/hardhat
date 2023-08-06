defmodule Hardhat.Builder do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    quote do
      @before_compile Hardhat.Builder
      # docs: false
      use Tesla.Builder, unquote(opts)

      adapter(Tesla.Adapter.Finch, name: __MODULE__)

      @fuse_thresholds {{:standard, 50, 1_000}, {:reset, 2_000}}

      @doc false
      def child_spec(opts \\ []) do
        Supervisor.child_spec({Finch, name: __MODULE__, pools: pool_options(opts)},
          id: __MODULE__
        )
      end

      defdelegate pool_options(overrides), to: Hardhat.Defaults
      defdelegate should_melt(env), to: Hardhat.Defaults

      defoverridable pool_options: 1, should_melt: 1
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      plug(Tesla.Middleware.Fuse,
        opts: @fuse_thresholds,
        keep_original_error: true,
        should_melt: &__MODULE__.should_melt/1,
        mode: :async_dirty
      )

      plug(Tesla.Middleware.Telemetry)
      plug(Tesla.Middleware.OpenTelemetry)
      plug(Hardhat.Middleware.PathParams)
    end
  end
end
