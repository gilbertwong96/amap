defmodule Amap.NewPlaceTest do
  use ExUnit.Case, async: true

  alias Amap.NewPlace
  alias Amap.NewPlace.Business
  alias Amap.NewPlace.Child
  alias Amap.NewPlace.Indoor
  alias Amap.NewPlace.Navi
  alias Amap.NewPlace.Photo
  alias Amap.NewPlace.Poi
  alias Amap.NewPlace.Result
  alias Amap.TestServer

  @text ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "pois":{"poi":[
    {"name":"北京大学","id":"B000A7BM4H","parent":"","distance":"0",
     "location":"116.310791,39.992521","type":"科教文化服务;学校;高等院校",
     "typecode":"141201","pname":"北京市","cityname":"北京市","adname":"海淀区",
     "address":"颐和园路5号","pcode":"110000","adcode":"110108","citycode":"010",
     "children":[{"id":"B0FFHTVW8K","name":"北京大学-西大门",
      "location":"116.3105,39.9921","address":"颐和园路","subtype":"出入口",
      "typecode":"141201","sname":"西大门"}],
     "business":{"business_area":"中关村","opentime_today":"08:30-17:30",
      "opentime_week":"周一至周五:08:30-17:30","tel":"010-62751201","tag":"烤鱼",
      "rating":"4.7","cost":"0","parking_type":"地面","alias":"北大",
      "keytag":"university","rectag":"985"},
     "indoor":{"indoor_map":"1","cpid":"B0FFHTVW8K","floor":"1","truefloor":"F1"},
     "navi":{"navi_poiid":"B0FFHTVW8K","entr_location":"116.3105,39.9921",
      "exit_location":"116.3106,39.9922","gridcode":"8888"},
     "photos":[{"title":"北京大学","url":"https://example.com/pku.jpg"},
      {"title":"未名湖","url":"https://example.com/wmh.jpg"}]}
   ]}}
  """

  @base ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "pois":{"poi":[
    {"name":"北京大学","id":"B000A7BM4H","parent":"","location":"116.310791,39.992521",
     "type":"科教文化服务;学校;高等院校","typecode":"141201","pname":"北京市",
     "cityname":"北京市","adname":"海淀区","address":"颐和园路5号","pcode":"110000",
     "adcode":"110108","citycode":"010"}
   ]}}
  """

  @detail ~S"""
  {"status":"1","info":"OK","infocode":"10000",
   "pois":{"poi":[
    {"name":"北京大学","id":"B000A7BM4H","parent":"","location":"116.310791,39.992521",
     "type":"科教文化服务;学校;高等院校","typecode":"141201","pname":"北京市",
     "cityname":"北京市","adname":"海淀区","address":"颐和园路5号","pcode":"110000",
     "adcode":"110108","citycode":"010","atag":"985大学/粤菜"}
   ]}}
  """

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

  test "text/2 sends the v5 keyword search parameters", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v5/place/text", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @text}
    end)

    assert {:ok, %Result{}} =
             NewPlace.text(client,
               keywords: "北京大学",
               types: ["141201"],
               region: "北京市",
               city_limit: true,
               show_fields: [:business, :navi],
               page_size: 25,
               page_num: 2,
               lang_code: :en
             )

    assert_receive {:query, query}
    assert query["keywords"] == "北京大学"
    assert query["types"] == "141201"
    assert query["region"] == "北京市"
    assert query["city_limit"] == "true"
    assert query["show_fields"] == "business,navi"
    assert query["page_size"] == "25"
    assert query["page_num"] == "2"
    assert query["langCode"] == "en"

    assert Map.keys(query) --
             ~w(key keywords types region city_limit show_fields page_size page_num langCode) ==
             []

    refute Map.has_key?(query, "children")
    refute Map.has_key?(query, "offset")
    refute Map.has_key?(query, "page")
  end

  test "text/2 accepts types alone and refuses neither-of-the-two", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v5/place/text", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @text}
    end)

    assert {:ok, %Result{}} = NewPlace.text(client, types: ["050301"])

    assert_receive {:query, query}
    assert query["types"] == "050301"
    refute Map.has_key?(query, "keywords")

    assert_raise ArgumentError, ~r/one of :keywords or :types is required/, fn ->
      NewPlace.text(client, region: "北京市")
    end
  end

  test "text/2 holds the v5 page's 80-character keyword limit", %{client: client} do
    eighty = String.duplicate("北", 80)

    assert_raise ArgumentError, ~r/:keywords must be at most 80 characters, got: 81/, fn ->
      NewPlace.text(client, keywords: eighty <> "大")
    end

    assert_raise ArgumentError, ~r/:keywords must be at most 80 characters, got: 81/, fn ->
      NewPlace.around(client, {116.47, 39.99}, keywords: eighty <> "大")
    end
  end

  test "around/3 sends the centre longitude first and the v5 options", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v5/place/around", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @base}
    end)

    assert {:ok, %Result{}} =
             NewPlace.around(client, {116.473168, 39.993015},
               keywords: "肯德基",
               radius: 10_000,
               sortrule: :distance,
               region: "110000",
               city_limit: false,
               show_fields: [:children, :indoor],
               page_size: 10,
               page_num: 1
             )

    assert_receive {:query, query}
    assert query["location"] == "116.473168,39.993015"
    assert query["keywords"] == "肯德基"
    assert query["radius"] == "10000"
    assert query["sortrule"] == "distance"
    assert query["region"] == "110000"
    assert query["city_limit"] == "false"
    assert query["show_fields"] == "children,indoor"
    assert query["page_size"] == "10"
    assert query["page_num"] == "1"
  end

  test "polygon/3 joins the ring with | and takes no region", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v5/place/polygon", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @base}
    end)

    polygon = [{116.460988, 40.006919}, {116.48231, 40.007381}]

    assert {:ok, %Result{}} =
             NewPlace.polygon(client, polygon, keywords: "肯德基", page_size: 25, page_num: 8)

    assert_receive {:query, query}
    assert query["polygon"] == "116.460988,40.006919|116.48231,40.007381"
    assert query["keywords"] == "肯德基"
    assert query["page_size"] == "25"
    assert query["page_num"] == "8"
    refute Map.has_key?(query, "region")
    refute Map.has_key?(query, "city_limit")
    refute Map.has_key?(query, "radius")
  end

  test "detail/3 takes one id or up to ten, | between them", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v5/place/detail", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @detail}
    end)

    assert {:ok, %Result{}} =
             NewPlace.detail(client, "B000A7BM4H", show_fields: [:business], lang_code: :zh)

    assert_receive {:query, query}
    assert query["id"] == "B000A7BM4H"
    assert query["show_fields"] == "business"
    assert query["langCode"] == "zh"

    TestServer.expect_once(server, "GET", "/v5/place/detail", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @detail}
    end)

    assert {:ok, %Result{}} = NewPlace.detail(client, ["B000A7BM4H", "B0FFKEPXS2"])

    assert_receive {:query, query}
    assert query["id"] == "B000A7BM4H|B0FFKEPXS2"
    refute Map.has_key?(query, "show_fields")
  end

  test "rejects ids and values the page does not document", %{client: client} do
    eleven = Enum.map(1..11, &"B#{&1}")

    assert_raise ArgumentError, ~r/:id must be at most 10 ids, got: 11/, fn ->
      NewPlace.detail(client, eleven)
    end

    assert_raise ArgumentError, ~r/:id must be a non-empty string or a list/, fn ->
      NewPlace.detail(client, [])
    end

    assert_raise ArgumentError, ~r/:id must be a non-empty string or a list/, fn ->
      NewPlace.detail(client, 42)
    end

    assert_raise ArgumentError, ~r/:id must be a non-empty string/, fn ->
      NewPlace.detail(client, "")
    end

    assert_raise ArgumentError, ~r/:page_size must be between 1 and 25, got: 26/, fn ->
      NewPlace.text(client, keywords: "北京大学", page_size: 26)
    end

    assert_raise ArgumentError, ~r/:page_size must be between 1 and 25, got: 0/, fn ->
      NewPlace.text(client, keywords: "北京大学", page_size: 0)
    end

    assert_raise ArgumentError, ~r/:page_num must be between 1 and 200, got: 201/, fn ->
      NewPlace.text(client, keywords: "北京大学", page_num: 201)
    end

    assert_raise ArgumentError, ~r/:radius must be between 0 and 50000, got: 50001/, fn ->
      NewPlace.around(client, {116.47, 39.99}, radius: 50_001)
    end

    assert_raise ArgumentError,
                 ~r/:sortrule must be one of \[:distance, :weight\], got: :fast/,
                 fn ->
                   NewPlace.around(client, {116.47, 39.99}, sortrule: :fast)
                 end

    assert_raise ArgumentError, ~r/:region must be a non-empty string/, fn ->
      NewPlace.text(client, keywords: "北京大学", region: "")
    end

    assert_raise ArgumentError, ~r/:city_limit must be a boolean, got: "true"/, fn ->
      NewPlace.text(client, keywords: "北京大学", city_limit: "true")
    end

    assert_raise ArgumentError, ~r/:lang_code must be one of \[:zh, :en\], got: :fr/, fn ->
      NewPlace.text(client, keywords: "北京大学", lang_code: :fr)
    end
  end

  test "validates show_fields against the groups the v5 pages list", %{client: client} do
    assert_raise ArgumentError, ~r/:show_fields must be a non-empty list of/, fn ->
      NewPlace.text(client, keywords: "北京大学", show_fields: [])
    end

    assert_raise ArgumentError, ~r/:show_fields must be a subset of \[:children/, fn ->
      NewPlace.text(client, keywords: "北京大学", show_fields: [:children, :typo])
    end

    assert_raise ArgumentError, ~r/:show_fields must be a non-empty list of/, fn ->
      NewPlace.polygon(client, [{116.46, 40.0}, {116.48, 40.0}], show_fields: :business)
    end
  end

  test "maps a poi and every show_fields group", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, @text} end)

    assert {:ok, result} =
             NewPlace.text(client,
               keywords: "北京大学",
               show_fields: [:children, :business, :indoor, :navi, :photos]
             )

    assert result.count == "1"
    assert [%Poi{} = poi] = result.pois

    assert poi.name == "北京大学"
    assert poi.id == "B000A7BM4H"
    assert poi.parent == ""
    assert poi.distance == "0"
    assert poi.location == {116.310791, 39.992521}
    assert poi.type == "科教文化服务;学校;高等院校"
    assert poi.typecode == "141201"
    assert poi.pname == "北京市"
    assert poi.cityname == "北京市"
    assert poi.adname == "海淀区"
    assert poi.address == "颐和园路5号"
    assert poi.pcode == "110000"
    assert poi.adcode == "110108"
    assert poi.citycode == "010"
    assert poi.atag == nil

    assert [%Child{} = child] = poi.children
    assert child.id == "B0FFHTVW8K"
    assert child.name == "北京大学-西大门"
    assert child.location == {116.3105, 39.9921}
    assert child.address == "颐和园路"
    assert child.subtype == "出入口"
    assert child.typecode == "141201"
    assert child.sname == "西大门"

    assert %Business{} = business = poi.business
    assert business.business_area == "中关村"
    assert business.opentime_today == "08:30-17:30"
    assert business.opentime_week == "周一至周五:08:30-17:30"
    assert business.tel == "010-62751201"
    assert business.tag == "烤鱼"
    assert business.rating == "4.7"
    assert business.cost == "0"
    assert business.parking_type == "地面"
    assert business.alias == "北大"
    assert business.keytag == "university"
    assert business.rectag == "985"

    assert poi.indoor == %Indoor{
             indoor_map: "1",
             cpid: "B0FFHTVW8K",
             floor: "1",
             truefloor: "F1"
           }

    assert poi.navi == %Navi{
             navi_poiid: "B0FFHTVW8K",
             entr_location: {116.3105, 39.9921},
             exit_location: {116.3106, 39.9922},
             gridcode: "8888"
           }

    assert [%Photo{} = first, %Photo{} = second] = poi.photos
    assert first.title == "北京大学"
    assert first.url == "https://example.com/pku.jpg"
    assert second.title == "未名湖"
  end

  test "reads the groups as absent when show_fields was not asked for", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, @base} end)

    assert {:ok, %Result{pois: [%Poi{} = poi]}} = NewPlace.text(client, keywords: "北京大学")

    assert poi.children == nil
    assert poi.business == nil
    assert poi.indoor == nil
    assert poi.navi == nil
    assert poi.photos == nil
  end

  test "keeps a group's shape when the wire did not send a list", %{
    server: server,
    client: client
  } do
    single = ~S"""
    {"status":"1","info":"OK","infocode":"10000","count":"1",
     "pois":{"poi":[{"id":"B1","name":"一个","children":{"id":"B2","name":"子"},
      "photos":{"title":"图","url":"u"}}]}}
    """

    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, single} end)

    assert {:ok, %Result{pois: [%Poi{} = poi]}} = NewPlace.text(client, keywords: "x")
    assert %Child{id: "B2", name: "子"} = poi.children
    assert %Photo{title: "图", url: "u"} = poi.photos
  end

  test "maps the detail-only atag, and leaves count nil when the fixture omits it", %{
    server: server,
    client: client
  } do
    # The fixture is written from the page, which lists no `count`; the service sends one anyway
    # (a two-id call answered `count "2"`), which the integration file checks instead.
    TestServer.expect_once(server, "GET", "/v5/place/detail", fn _req -> {200, @detail} end)

    assert {:ok, %Result{count: nil, pois: [%Poi{atag: "985大学/粤菜"}]}} =
             NewPlace.detail(client, "B000A7BM4H")
  end

  test "answers with nothing when Amap sent no pois", %{server: server, client: client} do
    bare = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0"}>
    emptied = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0","pois":{"poi":null}}>

    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, bare} end)

    assert {:ok, %Result{count: "0", pois: []}} = NewPlace.text(client, keywords: "北京大学")

    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, emptied} end)

    assert {:ok, %Result{pois: []}} = NewPlace.text(client, keywords: "北京大学")
  end

  test "reads a malformed field as nil rather than raising", %{server: server, client: client} do
    malformed = ~S"""
    {"status":"1","info":"OK","infocode":"10000","count":"1",
     "pois":{"poi":[{"id":"1","location":"not-a-coordinate","children":"junk",
      "business":"junk","indoor":42,"navi":[],
      "photos":[{"title":"ok","url":"u"},"junk"]},"not-an-object"]}}
    """

    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, malformed} end)

    assert {:ok, %Result{pois: [%Poi{} = poi]}} = NewPlace.text(client, keywords: "x")

    assert poi.id == "1"
    assert poi.location == nil
    assert poi.children == nil
    assert poi.business == nil
    assert poi.indoor == nil
    assert poi.navi == nil
    assert [%Photo{title: "ok", url: "u"}] = poi.photos
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

    TestServer.expect_once(server, "GET", "/v5/place/text", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = NewPlace.text(client, keywords: "北京大学")
  end
end
