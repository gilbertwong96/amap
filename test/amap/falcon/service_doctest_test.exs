defmodule Amap.Falcon.ServiceDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @added ~s({"errcode":10000,"errmsg":"OK",) <>
           ~s("data":{"sid":1000,"name":"车队A","desc":"夜间配送"}})

  # `update` answers the name as it was before the call, not the one just sent.
  @before_update ~s({"errcode":10000,"errmsg":"OK","data":{"sid":1000,"name":"车队A"}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v1/track/service/add", fn _request ->
      {200, @added}
    end)

    TestServer.expect(server, "POST", "/v1/track/service/update", fn _request ->
      {200, @before_update}
    end)

    :ok
  end

  doctest Amap.Falcon.Service
end
