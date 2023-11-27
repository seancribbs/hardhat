defmodule Hardhat.Middleware.PathParams do
  @moduledoc """
  Use templated URLs with separate params. Unlike `Tesla.Middleware.PathParams`,
  we ensure that all parameters are URL-safe. _This middleware is part of the
  default stack_.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _) do
    env =
      if path_params = env.opts[:path_params] do
        urlsafe =
          Enum.map(path_params, fn {key, value} ->
            {key, URI.encode(value, &URI.char_unreserved?/1)}
          end)

        Tesla.put_opt(env, :path_params, urlsafe)
      else
        env
      end

    Tesla.run(env, [{Tesla.Middleware.PathParams, :call, [[]]} | next])
  end
end
