defmodule Hardhat.PathParamsTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use Hardhat
  end

  setup do
    bypass = Bypass.open()
    pool = start_supervised!(TestClient)
    {:ok, %{bypass: bypass, pool: pool}}
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
