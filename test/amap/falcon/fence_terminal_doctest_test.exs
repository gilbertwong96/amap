defmodule Amap.Falcon.FenceTerminalDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @bound ~s({"errcode":10000,"errmsg":"OK","data":{"tids":[456,"457"]}})

  @status ~s({"errcode":10000,"errmsg":"OK",) <>
            ~s("data":{"count":1,"results":[{"gfid":77,"gfname":"仓库一","in":1, ) <>
            ~s("location":"114.158,22.279","time":1789703117430}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v1/track/geofence/terminal/bind", fn _request ->
      {200, @bound}
    end)

    TestServer.expect(server, "POST", "/v1/track/geofence/terminal/unbind", fn request ->
      case URI.decode_query(request.body)["tids"] do
        "#all" -> {200, ~s({"errcode":10000,"errmsg":"OK"})}
        _ids -> {200, ~s({"errcode":10000,"errmsg":"OK","data":{"tids":[456]}})}
      end
    end)

    TestServer.expect(server, "GET", "/v1/track/geofence/status/terminal", fn _request ->
      {200, @status}
    end)

    :ok
  end

  doctest Amap.Falcon.FenceTerminal
end
