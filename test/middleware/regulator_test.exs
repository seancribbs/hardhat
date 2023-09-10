defmodule Hardhat.Middleware.RegulatorTest do
  use ExUnit.Case, async: false

  defmodule TestClient do
    use Hardhat, strategy: :regulator
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    Regulator.uninstall(TestClient.Regulator)
    {:ok, %{bypass: bypass, pool: pool}}
  end

  describe "failure detector strategy" do
    test "uses Hardhat.Middleware.Regulator instead of Fuse" do
      assert {Hardhat.Middleware.Regulator, :call, [opts]} =
               List.keyfind!(TestClient.__middleware__(), Hardhat.Middleware.Regulator, 0)

      assert (&TestClient.should_regulate/1) == Keyword.fetch!(opts, :should_regulate)
      assert 0.9 == Keyword.fetch!(opts, :backoff_ratio)
    end
  end

  test "installs a regulator for the client", %{bypass: bypass} do
    Bypass.expect_once(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert is_nil(Process.whereis(TestClient.Regulator))

    assert {:ok, _env} = TestClient.get("http://localhost:#{bypass.port}/")

    assert is_pid(Process.whereis(TestClient.Regulator))
  end

  def send_to_test(event, measurements, metadata, pid) do
    send(pid, {event, measurements, metadata})
  end

  test "invokes regulator for requests", %{bypass: bypass} do
    :telemetry.attach_many(
      "invokes regulator",
      [
        [:regulator, :ask, :start],
        [:regulator, :ask, :stop],
        [:regulator, :ask, :exception],
        [:regulator, :limit]
      ],
      &__MODULE__.send_to_test/4,
      self()
    )

    Bypass.stub(bypass, "GET", "/", fn conn ->
      Plug.Conn.resp(conn, 200, "Hello, world")
    end)

    assert {:ok, _env} = TestClient.get("http://localhost:#{bypass.port}/")

    assert_receive {[:regulator, :ask, :start], %{system_time: _, inflight: _},
                    %{regulator: TestClient.Regulator}}

    assert_receive {[:regulator, :ask, :stop], %{duration: _},
                    %{regulator: TestClient.Regulator, result: :ok}}

    # NOTE: We never call Regulator.ask/2 with a function, we are always taking the token to handle
    # ourselves, so we will never get :exception events
    refute_receive {[:regulator, :ask, :exception], _, %{regulator: TestClient.Regulator}}

    # NOTE: We sent only one request without any concurrency, so we should not trigger a limit change
    refute_receive {[:regulator, :limit], %{limit: _}, %{regulator: TestClient.Regulator}}

    :telemetry.detach("invokes regulator")
  end

  test "records errors based on should_regulate/1", %{bypass: bypass} do
    :telemetry.attach_many(
      "regulator errors",
      [
        [:regulator, :ask, :start],
        [:regulator, :ask, :stop],
        [:regulator, :ask, :exception],
        [:regulator, :limit]
      ],
      &__MODULE__.send_to_test/4,
      self()
    )

    Bypass.stub(bypass, "GET", "/", fn conn ->
      Plug.Conn.resp(conn, 503, "Bad upstream")
    end)

    assert {:ok, _env} = TestClient.get("http://localhost:#{bypass.port}/")

    assert_receive {[:regulator, :ask, :start], %{system_time: _, inflight: _},
                    %{regulator: TestClient.Regulator}}

    assert_receive {[:regulator, :ask, :stop], %{duration: _},
                    %{regulator: TestClient.Regulator, result: :error}}

    # NOTE: We never call Regulator.ask/2 with a function, we are always taking the token to handle
    # ourselves, so we will never get :exception events
    refute_receive {[:regulator, :ask, :exception], _, %{regulator: TestClient.Regulator}}

    # NOTE: We sent only one request without any concurrency, so we should not trigger a limit change
    refute_receive {[:regulator, :limit], %{limit: _}, %{regulator: TestClient.Regulator}}

    :telemetry.detach("regulator errors")
  end
end
