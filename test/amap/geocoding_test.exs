defmodule Amap.GeocodingTest do
  use ExUnit.Case, async: true

  alias Amap.Geocoding
  alias Amap.Geocoding.Geo
  alias Amap.TestServer

  @futon ~s({"status":"1","info":"OK","infocode":"10000","count":"1","geocodes":[) <>
           ~s({"country":"中国","province":"北京市","city":"北京市","citycode":"010",) <>
           ~s("district":"朝阳区","street":"阜通东大街","number":"6号","adcode":"110105",) <>
           ~s("location":"116.480881,39.989410","level":"门牌号"}]})

  setup do
    server = TestServer.start!()

    client =
      Amap.new(
        key: "test-key",
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    {:ok, server: server, client: client}
  end

  describe "geo/3" do
    test "sends the address and the city", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn req ->
        send(parent, {:query, URI.decode_query(req.query)})
        {200, @futon}
      end)

      assert {:ok, [%Geo{}]} = Geocoding.geo(client, "北京市朝阳区阜通东大街6号", city: "北京")

      assert_receive {:query, query}
      assert query["key"] == "test-key"
      assert query["address"] == "北京市朝阳区阜通东大街6号"
      assert query["city"] == "北京"
    end

    test "leaves city out when it was not given", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn req ->
        send(parent, {:query, URI.decode_query(req.query)})
        {200, @futon}
      end)

      Geocoding.geo(client, "天安门")

      assert_receive {:query, query}
      refute Map.has_key?(query, "city")
    end

    test "maps the result, keeping Amap's field names", %{server: server, client: client} do
      TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn _req -> {200, @futon} end)

      assert {:ok, [geo]} = Geocoding.geo(client, "北京市朝阳区阜通东大街6号")
      assert geo.country == "中国"
      assert geo.province == "北京市"
      assert geo.city == "北京市"
      assert geo.citycode == "010"
      assert geo.district == "朝阳区"
      assert geo.street == "阜通东大街"
      assert geo.number == "6号"
      assert geo.adcode == "110105"
      assert geo.location == {116.480881, 39.989410}
      assert geo.level == "门牌号"
    end

    test "maps several results in the order Amap sent them", %{server: server, client: client} do
      two =
        ~s({"status":"1","info":"OK","infocode":"10000","count":"2","geocodes":[) <>
          ~s({"province":"北京市","adcode":"110101","level":"区县"},) <>
          ~s({"province":"北京市","adcode":"110105","level":"门牌号"}]})

      TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn _req -> {200, two} end)

      assert {:ok, [first, second]} = Geocoding.geo(client, "朝阳")
      assert first.adcode == "110101"
      assert second.adcode == "110105"
    end

    test "answers with an empty list when Amap found nothing", %{server: server, client: client} do
      empty = ~s({"status":"1","info":"OK","infocode":"10000","count":"0","geocodes":[]})

      TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn _req -> {200, empty} end)

      assert Geocoding.geo(client, "没有这个地方") == {:ok, []}
    end

    test "rejects an empty address at the call site", %{client: client} do
      assert_raise ArgumentError, ~r/:address must be a non-empty string/, fn ->
        Geocoding.geo(client, "")
      end

      assert_raise ArgumentError, ~r/:city must be a non-empty string/, fn ->
        Geocoding.geo(client, "天安门", city: "")
      end
    end

    test "returns an error rather than raising for a refusal", %{server: server, client: client} do
      refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

      TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn _req -> {200, refusal} end)

      assert {:error, %Amap.Error{}} = Geocoding.geo(client, "天安门")
    end
  end
end
