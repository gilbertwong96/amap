defmodule Amap.Falcon.FenceStatusDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # 仓库二 is a monitored terminal with no position at all, so Amap leaves
  # `location` and `time` out entirely rather than sending them empty.
  @statuses ~s({"errcode":10000,"errmsg":"OK",) <>
              ~s("data":{"count":2,"results":[) <>
              ~s({"gfid":77,"gfname":"仓库一","in":1,) <>
              ~s("location":"114.158,22.279","time":1789703117430},) <>
              ~s({"gfid":78,"gfname":"仓库二","in":0}]}})

  @narrowed ~s({"errcode":10000,"errmsg":"OK",) <>
              ~s("data":{"count":1,"results":[{"gfid":77,"gfname":"仓库一","in":1, ) <>
              ~s("location":"114.158,22.279","time":1789703117430}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v1/track/geofence/status/terminal", fn _request ->
      {200, @statuses}
    end)

    TestServer.expect(server, "GET", "/v1/track/geofence/status/location", fn _request ->
      {200, @narrowed}
    end)

    :ok
  end

  doctest Amap.Falcon.FenceStatus
end
