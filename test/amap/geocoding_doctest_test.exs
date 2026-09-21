defmodule Amap.GeocodingDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # Base mode: the four detail lists the regeo page omits unless extensions=all.
  @base ~s({"status":"1","info":"OK","infocode":"10000","regeocode":{"addressComponent":{) <>
          ~s("province":"北京市","city":"北京市","adcode":"110108"},) <>
          ~s("roads":[],"roadinters":[],"pois":[],"aois":[]}})

  @detail ~s({"status":"1","info":"OK","infocode":"10000","regeocode":{"addressComponent":{) <>
            ~s("province":"北京市","city":[],"adcode":"110108"},) <>
            ~s("roads":[],"roadinters":[],) <>
            ~s("pois":[{"id":"B000A7","name":"北京大学",) <>
            ~s("type":"科教文化服务;学校","address":"颐和园路5号",) <>
            ~s("location":"116.310,39.991"}],) <>
            ~s("aois":[]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v3/geocode/regeo", fn request ->
      if URI.decode_query(request.query)["extensions"] == "all" do
        {200, @detail}
      else
        {200, @base}
      end
    end)

    :ok
  end

  doctest Amap.Geocoding
end
