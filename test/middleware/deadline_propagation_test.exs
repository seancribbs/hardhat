defmodule Hardhat.Middleware.DeadlinePropagationTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use Hardhat
  end

  defmodule TestClientWithTimeout do
    use Hardhat

    plug(Hardhat.Middleware.Timeout, timeout: 1000)
  end

  defmodule TestClientWithOptions do
    use Hardhat

    def deadline_propagation_opts() do
      [header: "countdown"]
    end
  end

  setup do
    bypass = Bypass.open()
    start_supervised!(TestClient)
    start_supervised!(TestClientWithTimeout)
    start_supervised!(TestClientWithOptions)

    {:ok, %{bypass: bypass}}
  end

  test "deadline header is not added when there is no deadline set", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, fn conn ->
      send(parent, {:deadline, Plug.Conn.get_req_header(conn, "deadline")})
      Plug.Conn.resp(conn, 200, "hello world")
    end)

    assert nil == Deadline.get()
    assert {:ok, _} = TestClient.get("http://localhost:#{bypass.port}/")
    assert_receive {:deadline, []}, 500
  end

  test "deadline header is added when there is a deadline set", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, fn conn ->
      send(parent, {:deadline, Plug.Conn.get_req_header(conn, "deadline")})
      Plug.Conn.resp(conn, 200, "hello world")
    end)

    Deadline.set(50)
    assert {:ok, _} = TestClient.get("http://localhost:#{bypass.port}/")
    assert_receive {:deadline, [deadline]}, 500
    assert String.to_integer(deadline) <= 50
  end

  test "deadline header is propagated through timeouts", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, fn conn ->
      send(parent, {:deadline, Plug.Conn.get_req_header(conn, "deadline")})
      Plug.Conn.resp(conn, 200, "hello world")
    end)

    Deadline.set(500)
    assert {:ok, _} = TestClient.get("http://localhost:#{bypass.port}/")
    assert_receive {:deadline, [deadline]}, 100
    assert String.to_integer(deadline) <= 500
  end

  test "deadline header name is configurable", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, fn conn ->
      send(parent, {:deadline, Plug.Conn.get_req_header(conn, "countdown")})
      Plug.Conn.resp(conn, 200, "hello world")
    end)

    Deadline.set(50)
    assert {:ok, _} = TestClientWithOptions.get("http://localhost:#{bypass.port}/")
    assert_receive {:deadline, [deadline]}, 500
    assert String.to_integer(deadline) <= 50
  end
end
