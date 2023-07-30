defmodule HardhatTest do
  use ExUnit.Case, async: false
  require Record

  defmodule TestClient do
    use Hardhat
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

    :application.set_env(:opentelemetry, :processors, [
      {:otel_batch_processor, %{scheduled_delay_ms: 1, exporter: {:otel_exporter_pid, self()}}}
    ])

    :application.start(:opentelemetry)

    {:ok, %{bypass: bypass, pool: pool}}
  end

  test "default connection pool starts and makes requests", %{bypass: bypass, pool: pool} do
    assert Process.alive?(pool)

    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} = TestClient.get("http://localhost:#{bypass.port}/")
  end

  @tag skip: "OpenTelemetry PID exporter is brittle?"
  test "records spans for simple requests", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} = TestClient.get("http://localhost:#{bypass.port}/")

    assert_receive {:span, span(name: "HTTP GET")}, 1000
  end

  @tag skip: "OpenTelemetry PID exporter is brittle?"
  test "records spans for parameterized requests", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} =
             TestClient.get("http://localhost:#{bypass.port}/user/:id",
               opts: [path_params: [id: 5]]
             )

    assert_receive {:span, span(name: "/user/:id", attributes: _)}, 1000
  end

  test "emits telemetry hooks for requests", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    test_pid = self()

    handler = fn event, measures, metadata, _ ->
      send(test_pid, {event, measures, metadata})
    end

    :telemetry.attach("telemetry test", [:tesla, :request, :stop], handler, nil)

    assert {:ok, _conn} =
             TestClient.get("http://localhost:#{bypass.port}/user/:id",
               opts: [path_params: [id: "5"]]
             )

    assert_receive {[:tesla, :request, :stop], %{duration: _}, %{env: _}}, 1000
  end

  test "encodes non-URL-safe characters in path params", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, env} =
             TestClient.get("http://localhost:#{bypass.port}/user/:id",
               opts: [path_params: [id: "%^&*foo"]]
             )

    refute env.url == "http://localhost:#{bypass.port}/user/%^&*foo"
  end
end
