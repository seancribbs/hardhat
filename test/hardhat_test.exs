defmodule HardhatTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use Hardhat
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    {:ok, %{bypass: bypass, pool: pool}}
  end

  test "default connection pool starts and makes requests", %{bypass: bypass, pool: pool} do
    assert Process.alive?(pool)

    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} = TestClient.get("http://localhost:#{bypass.port}/")
  end
end
