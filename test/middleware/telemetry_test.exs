defmodule Hardhat.TelemetryTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use Hardhat
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    {:ok, %{bypass: bypass, pool: pool}}
  end

  def test_handler(event, measures, metadata, test_pid) do
    send(test_pid, {event, measures, metadata})
  end

  test "emits telemetry hooks for requests", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    :telemetry.attach(
      "telemetry test",
      [:tesla, :request, :stop],
      &__MODULE__.test_handler/4,
      self()
    )

    assert {:ok, _conn} =
             TestClient.get("http://localhost:#{bypass.port}/user/:id",
               opts: [path_params: [id: "5"]]
             )

    assert_receive {[:tesla, :request, :stop], %{duration: _}, %{env: _}}, 1000
  end
end
