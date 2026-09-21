defmodule Amap.ClientDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @located ~s({"status":"1","info":"OK","infocode":"10000","province":"北京市","city":"北京市"})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/ip", fn _request -> {200, @located} end)

    :ok
  end

  doctest Amap.Client
end
