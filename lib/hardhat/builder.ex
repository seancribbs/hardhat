defmodule Hardhat.Builder do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    quote do
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
end

defmodule Hardhat.Tester do
  use Hardhat
end
