defmodule Amap.PlaceDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # A generic keyword without a city is answered with the cities it could mean, not
  # with POIs; the suggestion is where that list arrives.
  @suggested ~s({"status":"1","info":"OK","infocode":"10000","count":"0",) <>
               ~s("suggestion":{"keywords":["美食"],"cities":[) <>
               ~s({"name":"北京市","num":"0","citycode":"010","adcode":"110000"},) <>
               ~s({"name":"上海市","num":"0","citycode":"021","adcode":"310000"}]}})

  @scoped ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("pois":{"poi":[{"id":"B0FFH6M7M0","name":"烤鸭店",) <>
            ~s("type":"餐饮服务;中餐厅","address":"前门大街1号",) <>
            ~s("location":"116.397,39.899","pname":"北京市","cityname":"北京市"}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/place/text", fn request ->
      if Map.has_key?(URI.decode_query(request.query), "city") do
        {200, @scoped}
      else
        {200, @suggested}
      end
    end)

    :ok
  end

  doctest Amap.Place
end
