defmodule Hardhat.Middleware.TimeoutTest do
  use ExUnit.Case, async: false
  require Record
  require OpenTelemetry.Tracer

  defmodule TestClient do
    use Hardhat

    plug(Hardhat.Middleware.Timeout, timeout: 100)
  end

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
    Record.defrecord(name, spec)
  end

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry_api/include/opentelemetry.hrl") do
    Record.defrecord(name, spec)
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    :application.stop(:opentelemetry)
    :application.set_env(:opentelemetry, :tracer, :otel_tracer_default)
    :application.set_env(:opentelemetry, :traces_exporter, {:otel_exporter_pid, self()})

    :application.set_env(:opentelemetry, :processors, [
      {:otel_batch_processor, %{scheduled_delay_ms: 1}}
    ])

    :application.start(:opentelemetry)

    {:ok, %{bypass: bypass, pool: pool}}
  end

  test "returns timeout error after the specified period", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Process.sleep(1_000)
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    Process.flag(:trap_exit, true)

    pid =
      spawn_link(fn ->
        # Deadlines will not affect this request because it unset
        assert nil == Deadline.get()
        assert {:error, :timeout} = TestClient.get("http://localhost:#{bypass.port}/")
      end)

    assert_receive {:EXIT, ^pid, :normal}, 500
    Bypass.pass(bypass)
  end

  test "propagates OpenTelemetry tracing context into the timeout", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    OpenTelemetry.Tracer.with_span "request" do
      assert {:ok, _} = TestClient.get("http://localhost:#{bypass.port}/")
    end

    assert_receive {:span, span(name: "request", span_id: span_id)}
    assert_receive {:span, span(name: "HTTP GET", parent_span_id: ^span_id)}
  end

  test "adds a span event to the current OpenTelemetry span when timeout is exceeded", %{
    bypass: bypass
  } do
    Bypass.expect_once(bypass, fn conn ->
      Process.sleep(1_000)
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    OpenTelemetry.Tracer.with_span "request" do
      assert {:error, :timeout} = TestClient.get("http://localhost:#{bypass.port}/")
    end

    assert_receive {:span,
                    span(
                      name: "request",
                      span_id: span_id,
                      events: {:events, _, _, _, _, [event]}
                    )}

    assert event(name: :timeout_exceeded, attributes: {:attributes, _, _, _, attrs}) = event
    assert %{module: TestClient, timeout: 100} = attrs

    refute_receive {:span, span(name: "HTTP GET", parent_span_id: ^span_id)}
    Bypass.pass(bypass)
  end

  test "uses the smaller of the set deadline or the configured timeout", %{bypass: bypass} do
    # Normal timeout is used when deadline is not set
    assert nil == Deadline.get()

    Bypass.expect_once(bypass, fn conn ->
      Process.sleep(40)
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _} = TestClient.get("http://localhost:#{bypass.port}/")

    # Set a deadline that is smaller than the configured timeout
    Bypass.expect_once(bypass, fn conn ->
      Process.sleep(75)
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    Deadline.set(25)
    assert {:error, :timeout} = TestClient.get("http://localhost:#{bypass.port}/")

    # Set a deadline that is larger than the configured timeout
    Bypass.expect_once(bypass, fn conn ->
      Process.sleep(120)
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    Deadline.set(200)
    assert {:error, :timeout} = TestClient.get("http://localhost:#{bypass.port}/")
    Bypass.pass(bypass)
  end
end
