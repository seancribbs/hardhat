defmodule HardhatTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use Hardhat
  end

  defmodule NoCircuitBreaker do
    use Hardhat, strategy: :none

    def fuse_opts() do
      [opts: {{:standard, 3, 100}, {:reset, 1000}}]
    end
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    start_supervised!(NoCircuitBreaker)
    {:ok, %{bypass: bypass, pool: pool}}
  end

  test "default connection pool starts and makes requests", %{bypass: bypass, pool: pool} do
    assert Process.alive?(pool)

    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _conn} = TestClient.get("http://localhost:#{bypass.port}/")
  end

  test "does not limit requests when the circuit breaker strategy is :none", %{bypass: bypass} do
    status = 503

    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(conn, status, "Failed")
    end)

    for _ <- 0..3 do
      assert {:ok, %Tesla.Env{status: ^status}} =
               NoCircuitBreaker.get("http://localhost:#{bypass.port}/")
    end

    assert {:ok, %Tesla.Env{status: ^status}} =
             NoCircuitBreaker.get("http://localhost:#{bypass.port}/")
  end
end
