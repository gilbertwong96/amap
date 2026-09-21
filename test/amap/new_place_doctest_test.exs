defmodule Amap.NewPlaceDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # Base mode: a group that was not asked for leaves its fields nil.
  @base ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
          ~s("pois":[{"id":"B000A7BM4H","name":"北京大学",) <>
          ~s("type":"科教文化服务;学校;高等院校","address":"颐和园路5号",) <>
          ~s("location":"116.310791,39.992521"}]})

  @business ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
              ~s("pois":[{"id":"B000A7BM4H","name":"北京大学",) <>
              ~s("location":"116.310791,39.992521",) <>
              ~s("business":{"rating":"4.7","cost":"0","business_area":"中关村"}}]})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v5/place/text", fn request ->
      if URI.decode_query(request.query)["show_fields"] == "business" do
        {200, @business}
      else
        {200, @base}
      end
    end)

    :ok
  end

  doctest Amap.NewPlace
end
