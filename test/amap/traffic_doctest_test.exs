defmodule Amap.TrafficDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @evaluation ~s("evaluation":{"expedite":"90.18","congested":"3.42",) <>
                ~s("blocked":"0","unknown":"6.4"})

  # Base mode answers the summary and no roads; `extensions=all` adds the roads.
  @base ~s({"status":"1","info":"OK","infocode":"10000","trafficinfo":{) <>
          ~s("description":"中关村大街: 畅通",) <>
          @evaluation <>
          ~s(,"roads":[]}})

  @detailed ~s({"status":"1","info":"OK","infocode":"10000","trafficinfo":{) <>
              ~s("description":"中关村大街: 畅通",) <>
              @evaluation <>
              ~s(,"roads":[) <>
              ~s({"name":"中关村大街","status":"1","direction":"南向北",) <>
              ~s("speed":"45","polyline":"116.31,39.99;116.32,39.995"},) <>
              ~s({"name":"北四环西路","status":"2","direction":"东向西",) <>
              ~s("speed":"20","polyline":"116.35,39.98"}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/traffic/status/circle", fn request ->
      if URI.decode_query(request.query)["extensions"] == "all" do
        {200, @detailed}
      else
        {200, @base}
      end
    end)

    :ok
  end

  doctest Amap.Traffic
end
