defmodule Hardhat.RetryTest do
  use ExUnit.Case, async: false

  defmodule TestClient do
    use Hardhat
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    :fuse.circuit_enable(TestClient)
    :fuse.reset(TestClient)
    {:ok, %{bypass: bypass, pool: pool}}
  end

  describe "retry options" do
    test "get injected into the middleware stack for Tesla.Middleware.Retry" do
      assert {Tesla.Middleware.Retry, :call, [opts]} =
               List.keyfind!(TestClient.__middleware__(), Tesla.Middleware.Retry, 0)

      assert 50 = Keyword.fetch!(opts, :delay)
    end
  end

  describe "default should_retry" do
    test "does not retry when the fuse is blown", %{bypass: bypass} do
      parent = self()

      Bypass.stub(bypass, "GET", "/", fn conn ->
        send(parent, :request)
        Plug.Conn.resp(conn, 200, "Hello, world")
      end)

      assert {:ok, _} = TestClient.get("http://localhost:#{bypass.port}/")
      assert_receive :request

      :fuse.circuit_disable(TestClient)

      assert {:error, :unavailable} = TestClient.get("http://localhost:#{bypass.port}/")

      refute_receive :request
    end

    test "retries when there is a TCP-level error", %{bypass: bypass} do
      parent = self()

      adapter = fn _ ->
        send(parent, :request)
        {:error, :econnrefused}
      end

      client = Tesla.client([], adapter)

      assert {:error, :econnrefused} = TestClient.get(client, "http://localhost:#{bypass.port}/")

      for _ <- 0..3 do
        assert_receive :request
      end
    end

    test "retries HTTP 429", %{bypass: bypass} do
      assert_retries_status_code(bypass, 429)
    end

    test "retries HTTP 500", %{bypass: bypass} do
      assert_retries_status_code(bypass, 500)
    end

    test "retries HTTP 501", %{bypass: bypass} do
      assert_retries_status_code(bypass, 501)
    end

    test "retries HTTP 502", %{bypass: bypass} do
      assert_retries_status_code(bypass, 502)
    end

    test "retries HTTP 503", %{bypass: bypass} do
      assert_retries_status_code(bypass, 503)
    end

    defp assert_retries_status_code(bypass, status) do
      parent = self()

      Bypass.stub(bypass, "GET", "/", fn conn ->
        send(parent, :request)
        Plug.Conn.resp(conn, status, "Hello, world")
      end)

      assert {:ok, env} = TestClient.get("http://localhost:#{bypass.port}/")
      assert env.status == status

      for _ <- 0..3 do
        assert_receive :request
      end
    end
  end
end
