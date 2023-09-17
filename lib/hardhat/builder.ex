defmodule Hardhat.Builder do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    strategy =
      case Keyword.get(opts, :strategy, :fuse) do
        v when v in [:fuse, :regulator] -> v
        invalid -> raise "Invalid strategy #{inspect(invalid)}"
      end

    client_mod = __CALLER__.module
    regulator_name = Module.concat(client_mod, Regulator)

    install_regulator =
      if strategy == :regulator do
        quote location: :keep do
          unquote(client_mod).install_regulator()
        end
      end

    quote location: :keep do
      @before_compile Hardhat.Builder
      # docs: false
      use Tesla.Builder, unquote(opts)

      @strategy unquote(strategy)

      adapter(Tesla.Adapter.Finch, name: __MODULE__)

      defmodule Sup do
        use Supervisor

        def start_link(init_arg) do
          Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        def init(opts) do
          unquote(install_regulator)

          children = [
            {Finch, name: unquote(client_mod), pools: unquote(client_mod).pool_options(opts)}
          ]

          Supervisor.init(children, strategy: :one_for_one)
        end
      end

      def child_spec(opts) do
        Supervisor.child_spec(__MODULE__.Sup, opts)
      end

      defdelegate pool_options(overrides), to: Hardhat.Defaults
      defdelegate should_melt(env), to: Hardhat.Defaults
      defdelegate deadline_propagation_opts(), to: Hardhat.Defaults
      defdelegate should_retry(result), to: Hardhat.Defaults
      defdelegate should_regulate(result), to: Hardhat.Defaults

      @doc false
      def retry_opts() do
        Hardhat.Defaults.retry_opts(__MODULE__)
      end

      @doc false
      def fuse_opts() do
        Hardhat.Defaults.fuse_opts(__MODULE__)
      end

      @doc false
      def regulator_opts() do
        Hardhat.Defaults.regulator_opts(__MODULE__)
      end

      @doc false
      def install_regulator() do
        Regulator.install(
          unquote(regulator_name),
          {Regulator.Limit.AIMD, Keyword.delete(regulator_opts(), :should_regulate)}
        )
      end

      @doc false
      def uninstall_regulator() do
        Regulator.uninstall(unquote(regulator_name))
      end

      defoverridable pool_options: 1,
                     should_melt: 1,
                     fuse_opts: 0,
                     deadline_propagation_opts: 0,
                     retry_opts: 0,
                     should_retry: 1,
                     regulator_opts: 0,
                     should_regulate: 1
    end
  end

  defmacro __before_compile__(env) do
    circuit_breaker =
      case Module.get_attribute(env.module, :strategy) do
        :fuse ->
          quote do
            plug(Tesla.Middleware.Fuse, __MODULE__.fuse_opts())
          end

        :regulator ->
          quote do
            plug(Hardhat.Middleware.Regulator, __MODULE__.regulator_opts())
          end
      end

    quote location: :keep do
      plug(Hardhat.Middleware.DeadlinePropagation, __MODULE__.deadline_propagation_opts())
      plug(Tesla.Middleware.Retry, __MODULE__.retry_opts())
      unquote(circuit_breaker)
      plug(Tesla.Middleware.Telemetry)
      plug(Tesla.Middleware.OpenTelemetry)
      plug(Hardhat.Middleware.PathParams)
    end
  end
end
