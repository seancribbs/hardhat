defmodule Hardhat.FuseTest do
  use ExUnit.Case, async: false

  defmodule TestClient do
    use Hardhat

    @fuse_thresholds {{:standard, 3, 100}, {:reset, 1000}}

    def fuse_opts do
      __MODULE__
      |> Hardhat.Defaults.fuse_opts()
      |> Keyword.put(:opts, @fuse_thresholds)
    end

    # NOTE: retries can interact badly with fuse, so let's not retry in test
    def retry_opts do
      [
        max_retries: 0
      ]
    end
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    :fuse.reset(TestClient)
    {:ok, %{bypass: bypass, pool: pool}}
  end

  describe "fuse options" do
    test "get injected into the middleware stack for Tesla.Middleware.Fuse" do
      assert {Tesla.Middleware.Fuse, :call, [opts]} =
               List.keyfind!(TestClient.__middleware__(), Tesla.Middleware.Fuse, 0)

      assert {{:standard, 3, 100}, {:reset, 1000}} = Keyword.fetch!(opts, :opts)
    end
  end

  describe "default should_melt" do
    test "TCP-level errors blow the fuse", %{bypass: bypass} do
      Bypass.down(bypass)

      for _ <- 0..3 do
        assert {:error, "connection refused"} = TestClient.get("http://localhost:#{bypass.port}/")
      end

      assert {:error, :unavailable} = TestClient.get("http://localhost:#{bypass.port}/")
    end

    test "HTTP 429 blows the fuse", %{bypass: bypass} do
      assert_should_melt_status(bypass, 429)
    end

    test "HTTP 500 blows the fuse", %{bypass: bypass} do
      assert_should_melt_status(bypass, 500)
    end

    test "HTTP 501 blows the fuse", %{bypass: bypass} do
      assert_should_melt_status(bypass, 501)
    end

    test "HTTP 502 blows the fuse", %{bypass: bypass} do
      assert_should_melt_status(bypass, 502)
    end

    test "HTTP 503 blows the fuse", %{bypass: bypass} do
      assert_should_melt_status(bypass, 503)
    end

    defp assert_should_melt_status(bypass, status) do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, status, "Failed")
      end)

      for _ <- 0..3 do
        assert {:ok, %Tesla.Env{status: ^status}} =
                 TestClient.get("http://localhost:#{bypass.port}/")
      end

      assert {:error, :unavailable} = TestClient.get("http://localhost:#{bypass.port}/")
    end
  end
end
