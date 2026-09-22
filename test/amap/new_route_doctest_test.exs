defmodule Amap.NewRouteDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # The v5 answer skeleton: a route whose path carries its distance.
  @walked ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("route":{"origin":"116.466485,39.995197",) <>
            ~s("destination":"116.46424,40.020642",) <>
            ~s("paths":[{"distance":"3200","duration":"2400",) <>
            ~s("steps":[{"instruction":"步行54米右转","road_name":"阜通东大街",) <>
            ~s("step_distance":"54"}]}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v5/direction/walking", fn _request -> {200, @walked} end)

    :ok
  end

  doctest Amap.NewRoute
  doctest Amap.NewRoute.Route
end
