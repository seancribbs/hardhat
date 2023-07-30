defmodule Hardhat.Middleware.PathParams do
  @moduledoc """
  Use templated URLs with separate params. Unlike `Tesla.Middleware.PathParams`,
  we ensure that all parameters are URL-safe.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _) do
    env =
      if env.opts[:path_params] do
        urlsafe =
          env.opts[:path_params]
          |> Enum.map(fn {key, value} -> {key, URI.encode(value, &URI.char_unreserved?/1)} end)
          |> Enum.to_list()

        Tesla.put_opt(env, :path_params, urlsafe)
      else
        env
      end

    Tesla.run(env, [{Tesla.Middleware.PathParams, :call, [[]]} | next])
  end
end
