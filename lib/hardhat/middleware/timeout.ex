defmodule Hardhat.Middleware.Timeout do
  @moduledoc """
  Abort HTTP requests after the given timeout or the current `Deadline`,
  and emit `OpenTelemetry` trace events on timeouts.

  Options:
  - `:timeout` - (required) timeout in milliseconds

  ## OpenTelemetry

  Implementing a timeout necessitates moving the request into a new process,
  and then waiting on that new process's completion (or aborting after the timeout).
  Since `OpenTelemetry` tracing context is stored in the process dictionary, that
  context must be explicitly propagated to the new process. This middleware uses
  `OpentelemetryProcessPropagator` for this purpose.

  In the event of a timeout result in this middleware, a new `timeout_exceeded` event
  will be added to the trace. The event will include these attributes:

  - `module` - the client module that includes this middleware
  - `timeout` - the duration that was exceeded

  ## Deadline

  When the caller has set a `Deadline` for the current process, that limit will be
  respected by this middleware. The effective timeout chosen will be the **lesser** of the time
  remaining on the current deadline and the duration given in the `:timeout` option.
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
