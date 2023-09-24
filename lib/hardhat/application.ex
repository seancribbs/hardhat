defmodule Hardhat.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_start_type, _start_args) do
    children =
      if Application.get_env(:hardhat, :start_default_client, false) do
        [Hardhat]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Hardhat.Supervisor)
  end
end
