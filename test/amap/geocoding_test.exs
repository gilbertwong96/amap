defmodule Amap.GeocodingTest do
  use ExUnit.Case, async: true

  alias Amap.Geocoding
  alias Amap.Geocoding.AddressComponent
  alias Amap.Geocoding.Aoi
  alias Amap.Geocoding.Geo
  alias Amap.Geocoding.Poi
  alias Amap.Geocoding.Regeo
  alias Amap.Geocoding.Road
  alias Amap.Geocoding.RoadInter
  alias Amap.Geocoding.StreetNumber
  alias Amap.TestServer

  @futon ~s({"status":"1","info":"OK","infocode":"10000","count":"1","geocodes":[) <>
           ~s({"country":"中国","province":"北京市","city":"北京市","citycode":"010",) <>
           ~s("district":"朝阳区","street":"阜通东大街","number":"6号","adcode":"110105",) <>
           ~s("location":"116.480881,39.989410","level":"门牌号"}]})

  @base ~s({"status":"1","info":"OK","infocode":"10000","regeocode":{"addressComponent":{) <>
          ~s("country":"中国","province":"北京市","city":"北京市","citycode":"010",) <>
          ~s("district":"海淀区","adcode":"110108","township":"燕园街道",) <>
          ~s("towncode":"110108015000",) <>
          ~s("neighborhood":{"name":"北京大学","type":"科教文化服务;学校;高等院校"},) <>
          ~s("building":{"name":"万达广场","type":"科教文化服务;商场"},) <>
          ~s("streetNumber":{"street":"中关村北二条","number":"3号",) <>
          ~s("location":"116.310005,39.991957","direction":"北","distance":"0"},) <>
          ~s("seaArea":[],) <>
          ~s("businessAreas":[{"location":"116.310000,39.990000","name":"颐和园",) <>
          ~s("id":"110108"}]},) <>
          ~s("roads":[],"roadinters":[],"pois":[],"aois":[]}})

  @detail ~s({"status":"1","info":"OK","infocode":"10000","regeocode":{"addressComponent":{) <>
            ~s("province":"北京市","city":[],"adcode":"110108"},) <>
            ~s("roads":[{"id":"0100001","name":"中关村大街","distance":"25.5",) <>
            ~s("direction":"南","location":"116.310,39.992"}],) <>
            ~s("roadinters":[{"distance":"40","direction":"东",) <>
            ~s("location":"116.311,39.993","first_id":"1","first_name":"中关村大街",) <>
            ~s("second_id":"2","second_name":"北四环西路"}],) <>
            ~s("pois":[{"id":"B000A7","name":"北京大学",) <>
            ~s("type":"科教文化服务;学校","tel":"010-62751201","distance":"12",) <>
            ~s("direction":"北","address":"颐和园路5号","location":"116.310,39.991",) <>
            ~s("businessarea":"中关村"}],) <>
            ~s("aois":[{"id":"B000A8","name":"北京大学","adcode":"110108",) <>
            ~s("location":"116.310,39.991","area":"1000000","distance":"0",) <>
            ~s("type":"科教文化服务;学校"}]}})

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

  describe "regeo/3" do
    test "sends the coordinate and the mode", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "GET", "/v3/geocode/regeo", fn req ->
        send(parent, {:query, URI.decode_query(req.query)})
        {200, @base}
      end)

      assert {:ok, %Regeo{}} = Geocoding.regeo(client, {116.310003, 39.991957}, extensions: :all)

      assert_receive {:query, query}
      assert query["location"] == "116.310003,39.991957"
      assert query["extensions"] == "all"
    end

    test "leaves extensions out when it was not given", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "GET", "/v3/geocode/regeo", fn req ->
        send(parent, {:query, URI.decode_query(req.query)})
        {200, @base}
      end)

      Geocoding.regeo(client, {116.31, 39.99})

      assert_receive {:query, query}
      refute Map.has_key?(query, "extensions")
      assert query["location"] == "116.31,39.99"
    end

    test "sends the four options that need extensions: :all", %{
      server: server,
      client: client
    } do
      parent = self()

      TestServer.expect_once(server, "GET", "/v3/geocode/regeo", fn req ->
        send(parent, {:query, URI.decode_query(req.query)})
        {200, @detail}
      end)

      Geocoding.regeo(client, {116.31, 39.99},
        extensions: :all,
        radius: 2000,
        poitype: ["050000", "060100"],
        roadlevel: 1,
        homeorcorp: 1
      )

      assert_receive {:query, query}
      assert query["radius"] == "2000"
      assert query["poitype"] == "050000|060100"
      assert query["roadlevel"] == "1"
      assert query["homeorcorp"] == "1"
    end

    test "refuses the detail options without extensions: :all", %{client: client} do
      assert_raise ArgumentError, ~r/\[:radius\] only take effect with extensions: :all/, fn ->
        Geocoding.regeo(client, {116.31, 39.99}, radius: 2000)
      end

      assert_raise ArgumentError, ~r/only take effect with extensions: :all/, fn ->
        Geocoding.regeo(client, {116.31, 39.99}, extensions: :base, roadlevel: 1)
      end
    end

    test "rejects a value Amap does not document", %{client: client} do
      assert_raise ArgumentError, ~r/:extensions must be :base or :all, got: :full/, fn ->
        Geocoding.regeo(client, {116.31, 39.99}, extensions: :full)
      end

      assert_raise ArgumentError, ~r/:radius must be between 0 and 3000, got: 3001/, fn ->
        Geocoding.regeo(client, {116.31, 39.99}, extensions: :all, radius: 3001)
      end

      assert_raise ArgumentError, fn ->
        Geocoding.regeo(client, {116.31, 39.99}, extensions: :all, roadlevel: 2)
      end

      assert_raise ArgumentError, fn ->
        Geocoding.regeo(client, {116.31, 39.99}, extensions: :all, homeorcorp: 3)
      end
    end

    test "maps the address component, with its nested objects", %{
      server: server,
      client: client
    } do
      TestServer.expect_once(server, "GET", "/v3/geocode/regeo", fn _req -> {200, @base} end)

      assert {:ok, %Regeo{address_component: %AddressComponent{} = component} = regeo} =
               Geocoding.regeo(client, {116.310003, 39.991957})

      assert component.country == "中国"
      assert component.province == "北京市"
      assert component.city == "北京市"
      assert component.district == "海淀区"
      assert component.adcode == "110108"
      assert component.township == "燕园街道"
      assert component.towncode == "110108015000"
      assert component.neighborhood.name == "北京大学"
      assert component.building.name == "万达广场"
      assert %StreetNumber{street: "中关村北二条", distance: "0"} = component.street_number
      assert component.street_number.location == {116.310005, 39.991957}

      # Amap wrote the sea area as an empty array, which is "no value".
      assert component.sea_area == nil
      assert [%{name: "颐和园", id: "110108"}] = component.business_areas

      # Without extensions: :all, Amap omits these rather than sending them empty.
      assert regeo.roads == []
      assert regeo.roadinters == []
      assert regeo.pois == []
      assert regeo.aois == []
    end

    test "maps the roads, intersections, POIs and AOIs of a detail answer", %{
      server: server,
      client: client
    } do
      TestServer.expect_once(server, "GET", "/v3/geocode/regeo", fn _req -> {200, @detail} end)

      assert {:ok, regeo} = Geocoding.regeo(client, {116.31, 39.99}, extensions: :all)

      assert [%Road{name: "中关村大街", distance: "25.5", location: {116.31, 39.992}}] =
               regeo.roads

      assert [%RoadInter{first_name: "中关村大街", second_name: "北四环西路"}] =
               regeo.roadinters

      assert [%Poi{name: "北京大学", tel: "010-62751201", location: {116.31, 39.991}}] =
               regeo.pois

      assert [%Aoi{name: "北京大学", area: "1000000", location: {116.31, 39.991}}] =
               regeo.aois

      # The four municipalities send no city at all.
      assert regeo.address_component.city == nil
    end

    test "returns an error rather than raising for a refusal", %{server: server, client: client} do
      refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

      TestServer.expect_once(server, "GET", "/v3/geocode/regeo", fn _req -> {200, refusal} end)

      assert {:error, %Amap.Error{}} = Geocoding.regeo(client, {116.31, 39.99})
    end
  end
end
