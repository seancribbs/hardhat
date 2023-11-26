defmodule Hardhat.OpentelemetryTest do
  use ExUnit.Case, async: false
  require Record

  defmodule TestClient do
    use Hardhat
  end

  defmodule NoPropagationClient do
    use Hardhat

    def opentelemetry_opts do
      [propagator: :none]
    end
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
    start_supervised!(NoPropagationClient)
    :application.stop(:opentelemetry)
    :application.set_env(:opentelemetry, :tracer, :otel_tracer_default)
    :application.set_env(:opentelemetry, :traces_exporter, {:otel_exporter_pid, self()})

    :application.set_env(:opentelemetry, :processors, [
      {:otel_batch_processor, %{scheduled_delay_ms: 1}}
    ])

    :application.start(:opentelemetry)

    {:ok, %{bypass: bypass, pool: pool}}
  end

  test "records spans for simple requests", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} = TestClient.get("http://localhost:#{bypass.port}/")

    :otel_tracer_provider.force_flush()

    assert_receive {:span, span(name: "HTTP GET")}, 1000
  end

  test "records spans for parameterized requests", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} =
             TestClient.get("http://localhost:#{bypass.port}/user/:id",
               opts: [path_params: [id: "5"]]
             )

    assert_receive {:span, span(name: "/user/:id", attributes: _)}, 1000
  end

  test "does not propagate trace when disabled", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, fn conn ->
      send(parent, {:traceheader, Plug.Conn.get_req_header(conn, "traceparent")})
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} =
             NoPropagationClient.get("http://localhost:#{bypass.port}/")

    assert_receive {:traceheader, []}, 1000
  end
end
