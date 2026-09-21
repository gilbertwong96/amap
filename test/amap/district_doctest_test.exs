defmodule Amap.DistrictDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # One keyword can land in more than one city: 朝阳区 here is 北京's and 长春's.
  # The first entry keeps a two-piece boundary, the `|` the page splits on.
  @two_cities ~s({"status":"1","info":"OK","infocode":"10000",) <>
                ~s("suggestion":{"keywords":[],"cities":[]},"districts":[) <>
                ~s({"citycode":"010","adcode":"110105","name":"朝阳区","level":"district",) <>
                ~s("center":"116.486409,39.921489",) <>
                ~s("polyline":"116.4,39.9;116.5,39.95|116.6,40.0"},) <>
                ~s({"citycode":"0431","adcode":"220104","name":"朝阳区","level":"district",) <>
                ~s("center":"125.288,43.833"}]})

  # A keyword that matched nothing still carries Amap's reading of what was meant.
  @nothing ~s({"status":"1","info":"OK","infocode":"10000",) <>
             ~s("suggestion":{"keywords":["北京"],"cities":["北京市"]},"districts":[]})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/config/district", fn request ->
      case URI.decode_query(request.query)["keywords"] do
        "朝阳区" -> {200, @two_cities}
        "北金" -> {200, @nothing}
      end
    end)

    :ok
  end

  doctest Amap.District
end
