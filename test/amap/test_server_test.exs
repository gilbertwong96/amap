defmodule Amap.TestServerTest do
  use ExUnit.Case, async: true

  alias Amap.TestServer

  test "start!/1 fails on a bound port rather than quietly choosing another" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)

    on_exit(fn -> :gen_tcp.close(listener) end)

    assert_raise RuntimeError, ~r/cannot bind port #{port}: :eaddrinuse/, fn ->
      TestServer.start!(port: port)
    end
  end
end
