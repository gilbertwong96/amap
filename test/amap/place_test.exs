defmodule Amap.PlaceTest do
  use ExUnit.Case, async: true

  alias Amap.Place
  alias Amap.Place.BizExt
  alias Amap.Place.IndoorData
  alias Amap.Place.Photo
  alias Amap.Place.Poi
  alias Amap.Place.Result
  alias Amap.Place.Suggestion
  alias Amap.TestServer

  @text ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "suggestion":{"keywords":["北京大学"],"cities":[
     {"name":"北京市","num":"1","citycode":"010","adcode":"110000"}]},
   "pois":{"poi":[
    {"id":"B000A7BM4H","parent":"","name":"北京大学","type":"科教文化服务;学校;高等院校",
     "typecode":"141201","biz_type":"education","address":"颐和园路5号",
     "location":"116.310791,39.992521","distance":"0","tel":"010-62751201",
     "postcode":"100871","website":"http://www.pku.edu.cn","email":"pku@pku.edu.cn",
     "pcode":"110000","pname":"北京市","citycode":"010","cityname":"北京市",
     "adcode":"110108","adname":"海淀区","entr_location":"116.3105,39.9921",
     "exit_location":"116.3106,39.9922","navi_poiid":"B000A7BM4H","gridcode":"8888",
     "alias":"北大","parking_type":"地面","tag":"烤鱼,麻辣香锅","indoor_map":"1",
     "indoor_data":{"cpid":"B0FFHTVW8K","floor":"1","truefloor":"F1"},
     "groupbuy_num":"0","business_area":"中关村","atag":"985大学/粤菜","discount_num":"0",
     "biz_ext":{"rating":"4.7","cost":"0","meal_ordering":"0","seat_ordering":"0",
      "ticket_ordering":"0","hotel_ordering":"0"},
     "photos":[{"title":"北京大学","url":"https://example.com/pku.jpg"}]}
   ]}}
  """

  @around ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "pois":{"poi":[
    {"id":"B0FFH6M7M0","name":"肯德基(望京店)","type":"餐饮服务;快餐厅;肯德基",
     "typecode":"050301","address":"望京街9号","location":"116.475,39.993",
     "distance":"320","pname":"北京市","cityname":"北京市","adname":"朝阳区"}
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

  test "text/2 sends the keyword search parameters", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/place/text", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @text}
    end)

    assert {:ok, %Result{}} =
             Place.text(client,
               keywords: "北京大学",
               city: "北京",
               city_limit: true,
               children: 1,
               offset: 25,
               page: 2,
               extensions: :all,
               lang_code: :en
             )

    assert_receive {:query, query}
    assert query["keywords"] == "北京大学"
    assert query["city"] == "北京"
    assert query["citylimit"] == "true"
    assert query["children"] == "1"
    assert query["offset"] == "25"
    assert query["page"] == "2"
    assert query["extensions"] == "all"
    assert query["langCode"] == "en"

    assert Map.keys(query) --
             ~w(key keywords city citylimit children offset page extensions langCode) == []
  end

  test "text/2 accepts types alone, which the page allows without keywords", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/place/text", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @text}
    end)

    assert {:ok, %Result{}} = Place.text(client, types: ["141201", "科教文化服务"])

    assert_receive {:query, query}
    assert query["types"] == "141201|科教文化服务"
    refute Map.has_key?(query, "keywords")
    refute Map.has_key?(query, "city")
    refute Map.has_key?(query, "offset")
    refute Map.has_key?(query, "page")
    refute Map.has_key?(query, "extensions")
  end

  test "text/2 refuses when neither keywords nor types was given", %{client: client} do
    assert_raise ArgumentError, ~r/one of :keywords or :types is required/, fn ->
      Place.text(client, city: "北京")
    end
  end

  test "around/3 sends the centre longitude first and the page's own options", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/place/around", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @around}
    end)

    assert {:ok, %Result{}} =
             Place.around(client, {116.473168, 39.993015},
               keywords: "肯德基",
               radius: 10_000,
               sortrule: :weight,
               city: "010",
               city_limit: false,
               offset: 20,
               page: 1,
               extensions: :base
             )

    assert_receive {:query, query}
    assert query["location"] == "116.473168,39.993015"
    assert query["keywords"] == "肯德基"
    assert query["radius"] == "10000"
    assert query["sortrule"] == "weight"
    assert query["city"] == "010"
    assert query["citylimit"] == "false"
    assert query["offset"] == "20"
    assert query["page"] == "1"
    assert query["extensions"] == "base"
  end

  test "around/3 needs no keyword at all: both are optional there", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/place/around", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @around}
    end)

    assert {:ok, %Result{}} = Place.around(client, {116.473168, 39.993015})

    assert_receive {:query, query}
    assert query["location"] == "116.473168,39.993015"
    refute Map.has_key?(query, "keywords")
    refute Map.has_key?(query, "types")
  end

  test "polygon/3 joins the ring with |, longitude first", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/place/polygon", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @text}
    end)

    rectangle = [{116.460988, 40.006919}, {116.48231, 40.007381}]

    assert {:ok, %Result{}} = Place.polygon(client, rectangle, keywords: "kfc", page: 1)

    assert_receive {:query, query}
    assert query["polygon"] == "116.460988,40.006919|116.48231,40.007381"
    assert query["keywords"] == "kfc"
    refute Map.has_key?(query, "city")
    refute Map.has_key?(query, "radius")
  end

  test "detail/3 sends the single id and nothing the page does not document", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/place/detail", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @text}
    end)

    assert {:ok, %Result{}} = Place.detail(client, "B0FFFAB6J2")

    assert_receive {:query, query}
    assert query["id"] == "B0FFFAB6J2"
    refute Map.has_key?(query, "extensions")
    assert Map.keys(query) -- ["key", "id"] == []
  end

  test "rejects values the pages do not document", %{client: client} do
    assert_raise ArgumentError, ~r/:offset must be between 1 and 25, got: 26/, fn ->
      Place.text(client, keywords: "北京大学", offset: 26)
    end

    assert_raise ArgumentError, ~r/:offset must be between 1 and 25, got: 0/, fn ->
      Place.text(client, keywords: "北京大学", offset: 0)
    end

    assert_raise ArgumentError, ~r/:page must be between 1 and 200, got: 201/, fn ->
      Place.text(client, keywords: "北京大学", page: 201)
    end

    assert_raise ArgumentError, ~r/:children must be one of \[0, 1\], got: 2/, fn ->
      Place.text(client, keywords: "北京大学", children: 2)
    end

    assert_raise ArgumentError, ~r/:radius must be between 0 and 50000, got: 50001/, fn ->
      Place.around(client, {116.47, 39.99}, radius: 50_001)
    end

    assert_raise ArgumentError,
                 ~r/:sortrule must be one of \[:distance, :weight\], got: :fast/,
                 fn ->
                   Place.around(client, {116.47, 39.99}, sortrule: :fast)
                 end

    assert_raise ArgumentError, ~r/:extensions must be one of \[:base, :all\], got: :full/, fn ->
      Place.text(client, keywords: "北京大学", extensions: :full)
    end

    assert_raise ArgumentError, ~r/:lang_code must be one of \[:zh, :en\], got: :fr/, fn ->
      Place.text(client, keywords: "北京大学", lang_code: :fr)
    end

    assert_raise ArgumentError, ~r/:city_limit must be a boolean, got: 1/, fn ->
      Place.text(client, keywords: "北京大学", city_limit: 1)
    end
  end

  test "rejects empty required arguments and malformed coordinates", %{client: client} do
    assert_raise ArgumentError, ~r/:keywords must be a non-empty string/, fn ->
      Place.text(client, keywords: "", types: ["141201"])
    end

    assert_raise ArgumentError, ~r/:id must be a non-empty string/, fn ->
      Place.detail(client, "")
    end

    assert_raise ArgumentError, ~r/:city must be a non-empty string/, fn ->
      Place.text(client, keywords: "北京大学", city: "")
    end

    assert_raise ArgumentError, ~r/:location must be a \{lon, lat\} pair of numbers/, fn ->
      Place.around(client, {"116.47", 39.99})
    end

    assert_raise ArgumentError, ~r/:polygon must be a non-empty list of \{lon, lat\} pairs/, fn ->
      Place.polygon(client, [])
    end

    assert_raise ArgumentError, ~r/:types must be a non-empty list/, fn ->
      Place.text(client, types: "141201")
    end
  end

  test "maps a poi and Amap's suggestion", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/place/text", fn _req -> {200, @text} end)

    assert {:ok, result} = Place.text(client, keywords: "北京大学")

    assert result.count == "1"

    assert %Suggestion{keywords: ["北京大学"], cities: [%Suggestion.City{} = city]} =
             result.suggestion

    assert city.name == "北京市"
    assert city.num == "1"
    assert city.citycode == "010"
    assert city.adcode == "110000"

    assert [%Poi{} = poi] = result.pois
    assert poi.id == "B000A7BM4H"
    assert poi.parent == ""
    assert poi.name == "北京大学"
    assert poi.type == "科教文化服务;学校;高等院校"
    assert poi.typecode == "141201"
    assert poi.biz_type == "education"
    assert poi.address == "颐和园路5号"
    assert poi.location == {116.310791, 39.992521}
    assert poi.distance == "0"
    assert poi.tel == "010-62751201"
    assert poi.postcode == "100871"
    assert poi.website == "http://www.pku.edu.cn"
    assert poi.email == "pku@pku.edu.cn"
    assert poi.pcode == "110000"
    assert poi.pname == "北京市"
    assert poi.citycode == "010"
    assert poi.cityname == "北京市"
    assert poi.adcode == "110108"
    assert poi.adname == "海淀区"
    assert poi.entr_location == {116.3105, 39.9921}
    assert poi.exit_location == {116.3106, 39.9922}
    assert poi.navi_poiid == "B000A7BM4H"
    assert poi.gridcode == "8888"
    assert poi.alias == "北大"
    assert poi.parking_type == "地面"
    assert poi.tag == "烤鱼,麻辣香锅"
    assert poi.indoor_map == "1"
    assert poi.groupbuy_num == "0"
    assert poi.business_area == "中关村"
    assert poi.atag == "985大学/粤菜"
    assert poi.discount_num == "0"

    assert poi.indoor_data == %IndoorData{cpid: "B0FFHTVW8K", floor: "1", truefloor: "F1"}

    assert poi.biz_ext == %BizExt{
             rating: "4.7",
             cost: "0",
             meal_ordering: "0",
             seat_ordering: "0",
             ticket_ordering: "0",
             hotel_ordering: "0"
           }

    assert [%Photo{title: "北京大学", url: "https://example.com/pku.jpg"}] = poi.photos
  end

  test "maps the distance only a around search sends", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/place/around", fn _req -> {200, @around} end)

    assert {:ok, %Result{suggestion: nil, pois: [%Poi{} = poi]}} =
             Place.around(client, {116.473168, 39.993015}, keywords: "肯德基")

    assert poi.name == "肯德基(望京店)"
    assert poi.location == {116.475, 39.993}
    assert poi.distance == "320"
    assert poi.biz_ext == nil
    assert poi.indoor_data == nil
    assert poi.photos == []
  end

  test "answers with nothing when Amap sent no pois", %{server: server, client: client} do
    bare = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0"}>
    emptied = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0","pois":{"poi":null}}>

    TestServer.expect_once(server, "GET", "/v3/place/text", fn _req -> {200, bare} end)

    assert {:ok, %Result{count: "0", suggestion: nil, pois: []}} =
             Place.text(client, keywords: "北京大学")

    TestServer.expect_once(server, "GET", "/v3/place/text", fn _req -> {200, emptied} end)

    assert {:ok, %Result{pois: []}} = Place.text(client, keywords: "北京大学")
  end

  test "reads a malformed field as nil rather than raising", %{server: server, client: client} do
    malformed = ~S"""
    {"status":"1","info":"OK","infocode":"10000","count":"1",
     "suggestion":{"keywords":null,"cities":[{"name":"北京市"},"junk"]},
     "pois":{"poi":[{"id":"1","location":"not-a-coordinate","entr_location":42,
      "indoor_data":"junk","biz_ext":"junk","photos":[{"title":"ok","url":"u"},"junk"]},
      "not-an-object"]}}
    """

    TestServer.expect_once(server, "GET", "/v3/place/text", fn _req -> {200, malformed} end)

    assert {:ok, %Result{suggestion: %Suggestion{} = suggestion, pois: [%Poi{} = poi]}} =
             Place.text(client, keywords: "x")

    assert suggestion.keywords == []
    assert [%Suggestion.City{name: "北京市", num: nil}] = suggestion.cities

    assert poi.id == "1"
    assert poi.location == nil
    assert poi.entr_location == nil
    assert poi.indoor_data == nil
    assert poi.biz_ext == nil
    assert [%Photo{title: "ok", url: "u"}] = poi.photos
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

    TestServer.expect_once(server, "GET", "/v3/place/detail", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = Place.detail(client, "B0FFFAB6J2")
  end
end
