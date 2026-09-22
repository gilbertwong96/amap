defmodule Amap.DirectionDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # One origin measured, one carrying its own failure code — the call is still ok.
  @measured ~s({"status":"1","info":"OK","infocode":"10000","count":"2",) <>
              ~s("results":[{"origin_id":"1","dest_id":"1","distance":"12345",) <>
              ~s("duration":"1200"},) <>
              ~s({"origin_id":"2","dest_id":"1","distance":"6789",) <>
              ~s("duration":"900","info":"未知错误","code":"2"}]})

  # Amap leaves `route` out entirely when it found no plan.
  @no_route ~s({"status":"1","info":"OK","infocode":"10000","count":"0"})

  # A Falcon envelope on the Web service host: `data` is the route.
  @cycled ~s({"errcode":0,"errmsg":"OK",) <>
            ~s("data":{"origin":"116.466485,39.995197",) <>
            ~s("destination":"116.46424,40.020642",) <>
            ~s("paths":[{"distance":"5432","duration":"1200","steps":[) <>
            ~s({"instruction":"骑行54米右转","road":"建国门北大街",) <>
            ~s("polyline":"116.481247,39.990704;116.481270,39.990726"}]}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/distance", fn _request -> {200, @measured} end)
    TestServer.expect(server, "GET", "/v3/direction/walking", fn _request -> {200, @no_route} end)
    TestServer.expect(server, "GET", "/v4/direction/bicycling", fn _request -> {200, @cycled} end)

    :ok
  end

  doctest Amap.Direction
  doctest Amap.Direction.Route
end
