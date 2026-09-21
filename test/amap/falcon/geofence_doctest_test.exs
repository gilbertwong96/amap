defmodule Amap.Falcon.GeofenceDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @created ~s({"errcode":10000,"errmsg":"OK","data":{"gfid":77,"name":"仓库一"}})

  @listed ~s({"errcode":10000,"errmsg":"OK",) <>
            ~s("data":{"count":1,"results":[{"gfid":77,"name":"仓库一",) <>
            ~s("shape":{"center":"114.158,22.279","radius":500}}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v1/track/geofence/add/circle", fn _request ->
      {200, @created}
    end)

    TestServer.expect(server, "POST", "/v1/track/geofence/delete", fn request ->
      case URI.decode_query(request.body)["gfids"] do
        "#all" -> {200, ~s({"errcode":10000,"errmsg":"OK"})}
        _ids -> {200, ~s({"errcode":10000,"errmsg":"OK","data":{"gfids":[77]}})}
      end
    end)

    TestServer.expect(server, "GET", "/v1/track/geofence/list", fn _request ->
      {200, @listed}
    end)

    :ok
  end

  doctest Amap.Falcon.Geofence
end
