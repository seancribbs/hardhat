defmodule Hardhat.Middleware.Timeout do
  @doc """
  Timeout HTTP request after X milliseconds.

  Includes:
  - automatic propagation of OpenTelemetry tracing context
  - addition of OpenTelemetry span events when the timeout is exceeded

  Options:
  - `:timeout` - (required) timeout in milliseconds
  """

  alias OpentelemetryProcessPropagator.Task

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env = %Tesla.Env{}, next, opts) do
    opts = opts || []
    configured_timeout = Keyword.fetch!(opts, :timeout)

    {timeout, is_deadline} =
      case Deadline.time_remaining() do
        :infinity -> {configured_timeout, false}
        value -> {min(value, configured_timeout), true}
      end

    task =
      safe_async(fn ->
        if is_deadline, do: Deadline.set(timeout)
        Tesla.run(env, next)
      end)

    try do
      task
      |> Task.await(timeout)
      |> repass_error
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, 0)

        OpenTelemetry.Tracer.add_event(:timeout_exceeded,
          module: env.__module__,
          timeout: timeout
        )

        {:error, :timeout}
    end
  end

  defp safe_async(func) do
    Task.async(fn ->
      try do
        {:ok, func.()}
      rescue
        e in _ ->
          {:exception, e, __STACKTRACE__}
      catch
        type, value ->
          {type, value}
      end
    end)
  end

  defp repass_error({:exception, error, stacktrace}), do: reraise(error, stacktrace)

  defp repass_error({:throw, value}), do: throw(value)

  defp repass_error({:exit, value}), do: exit(value)

  defp repass_error({:ok, result}), do: result
end
