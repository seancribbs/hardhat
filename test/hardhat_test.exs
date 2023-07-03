defmodule HardhatTest do
  use ExUnit.Case
  doctest Hardhat

  test "greets the world" do
    assert Hardhat.hello() == :world
  end
end
