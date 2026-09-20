defmodule Amap.BusTest do
  use ExUnit.Case, async: true

  alias Amap.Bus
  alias Amap.Bus.Stop
  alias Amap.Bus.Stops
  alias Amap.Bus.Suggestion
  alias Amap.TestServer

  @stopid ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "busstops":[{"id":"BV10006672","name":"阜通东大街(公交站)",
    "adcode":"110105","citycode":"010","location":"116.476437,39.987010",
    "buslines":[{"id":"110100014478","location":"116.476437,39.987010",
     "name":"854路(望京西枢纽站--孙河公交场站)","start_stop":"望京西枢纽站",
     "end_stop":"孙河公交场站"}]}]}
  """

  @stopname ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"3",
   "suggestion":{"keywords":[],"cities":[]},
   "busstops":[{"id":"BV10002739","name":"来广营路口西(公交站)",
    "adcode":"110105","citycode":"010","location":"116.463212,40.020541",
    "buslines":[{"id":"110100014478","location":"116.463212,40.020541",
     "name":"854路(望京西枢纽站--孙河公交场站)","start_stop":"望京西枢纽站",
     "end_stop":"孙河公交场站"}]}]}
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

  test "stopid/3 sends the id and nothing else", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/stopid", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @stopid}
    end)

    assert {:ok, %Stops{}} = Bus.stopid(client, "BV10006672")

    assert_receive {:query, query}
    assert query["id"] == "BV10006672"
    assert Map.keys(query) -- ["key", "id"] == []
    refute Map.has_key?(query, "extensions")
  end

  test "stopid/3 sends extensions when the caller asks for it", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/stopid", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @stopid}
    end)

    Bus.stopid(client, "BV10006672", extensions: :base)

    assert_receive {:query, query}
    assert query["extensions"] == "base"
  end

  test "stopname/3 leaves city out when it was not given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/stopname", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @stopname}
    end)

    assert {:ok, %Stops{}} = Bus.stopname(client, "来广营路口西")

    assert_receive {:query, query}
    assert query["keywords"] == "来广营路口西"
    refute Map.has_key?(query, "city")
  end

  test "stopname/3 sends city, offset and page when they were given", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/stopname", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @stopname}
    end)

    Bus.stopname(client, "来广营路口西", city: "110000", offset: 20, page: 2)

    assert_receive {:query, query}
    assert query["city"] == "110000"
    assert query["offset"] == "20"
    assert query["page"] == "2"
  end

  test "rejects a value Amap does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:offset must be between 1 and 100, got: 101/, fn ->
      Bus.stopname(client, "来广营路口西", offset: 101)
    end

    assert_raise ArgumentError, ~r/:page must be between 1 and 100, got: 101/, fn ->
      Bus.stopname(client, "来广营路口西", page: 101)
    end

    assert_raise ArgumentError, ~r/:page must be between 1 and 100, got: 0/, fn ->
      Bus.stopname(client, "来广营路口西", page: 0)
    end

    assert_raise ArgumentError, ~r/:extensions must be one of \[:base\], got: :all/, fn ->
      Bus.stopname(client, "来广营路口西", extensions: :all)
    end

    assert_raise ArgumentError, ~r/:extensions must be one of \[:base\], got: :all/, fn ->
      Bus.stopid(client, "BV10006672", extensions: :all)
    end
  end

  test "rejects an empty required argument", %{client: client} do
    assert_raise ArgumentError, ~r/:id must be a non-empty string/, fn ->
      Bus.stopid(client, "")
    end

    assert_raise ArgumentError, ~r/:keywords must be a non-empty string/, fn ->
      Bus.stopname(client, "")
    end

    assert_raise ArgumentError, ~r/:city must be a non-empty string/, fn ->
      Bus.stopname(client, "来广营路口西", city: "")
    end
  end

  test "maps a stop and the lines that serve it", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/bus/stopid", fn _req -> {200, @stopid} end)

    assert {:ok, stops} = Bus.stopid(client, "BV10006672")

    assert stops.count == "1"
    assert stops.suggestion == nil

    assert [%Stop{} = stop] = stops.busstops
    assert stop.id == "BV10006672"
    assert stop.name == "阜通东大街(公交站)"
    assert stop.adcode == "110105"
    assert stop.citycode == "010"
    assert stop.location == {116.476437, 39.98701}

    assert [%Stop.Busline{} = line] = stop.buslines
    assert line.id == "110100014478"
    assert line.location == {116.476437, 39.98701}
    assert line.name == "854路(望京西枢纽站--孙河公交场站)"
    assert line.start_stop == "望京西枢纽站"
    assert line.end_stop == "孙河公交场站"
  end

  test "carries Amap's suggestion on a keyword search", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/bus/stopname", fn _req -> {200, @stopname} end)

    assert {:ok, stops} = Bus.stopname(client, "来广营路口西")

    assert stops.count == "3"
    assert stops.suggestion == %Suggestion{keywords: [], cities: []}
    assert [%Stop{} = stop] = stops.busstops
    assert stop.name == "来广营路口西(公交站)"
  end

  test "keeps a non-empty suggestion's keywords and cities in their own fields", %{
    server: server,
    client: client
  } do
    payload = ~S"""
    {"status":"1","info":"OK","infocode":"10000","count":"0",
     "suggestion":{"keywords":["来广营","望京"],"cities":["北京市","广州市"]},
     "busstops":[]}
    """

    TestServer.expect_once(server, "GET", "/v3/bus/stopname", fn _req -> {200, payload} end)

    assert {:ok, %Stops{suggestion: %Suggestion{} = suggestion}} =
             Bus.stopname(client, "来广营")

    assert suggestion.keywords == ["来广营", "望京"]
    assert suggestion.cities == ["北京市", "广州市"]
  end

  test "answers with nothing when Amap sent no entries", %{server: server, client: client} do
    bare = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0"}>

    TestServer.expect_once(server, "GET", "/v3/bus/stopname", fn _req -> {200, bare} end)

    assert {:ok, %Stops{count: "0", suggestion: nil, busstops: []}} =
             Bus.stopname(client, "来广营路口西")
  end

  test "reads a malformed location as nil rather than raising", %{server: server, client: client} do
    malformed = ~S"""
    {"status":"1","info":"OK","infocode":"10000","count":"1",
     "busstops":[{"id":"BV1","name":"站","location":"not-a-coordinate",
      "adcode":[],"citycode":[],"buslines":[{"id":"1","location":42}]}]}
    """

    TestServer.expect_once(server, "GET", "/v3/bus/stopid", fn _req -> {200, malformed} end)

    assert {:ok, %Stops{busstops: [%Stop{} = stop]}} = Bus.stopid(client, "BV1")
    assert stop.location == nil
    assert stop.adcode == nil
    assert stop.citycode == nil
    assert [%Stop.Busline{location: nil}] = stop.buslines
  end

  @lineid ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "buslines":[{"id":"131000010042","type":"普通公交",
    "name":"450路(青年路小区--望京西枢纽站)",
    "polyline":"116.476437,39.987010;116.463212,40.020541;116.455,40.033",
    "citycode":"010","start_stop":"青年路小区","end_stop":"望京西枢纽站",
    "start_time":"05:30","end_time":"22:30","uicolor":"#0000ff",
    "timedesc":"{\"01\":[\"05:30\",\"22:30\"]}","distance":"12.5","loop":"0",
    "status":"1","direc":"131000010043","company":"北京公交集团",
    "basic_price":"2","total_price":"5","bounds":"116.455,39.987;116.476,40.033",
    "busstops":[{"id":"BV10006672","name":"阜通东大街(公交站)",
     "location":"116.476437,39.987010","sequence":"1"},
     {"id":"BV10002739","name":"来广营路口西(公交站)",
     "location":"116.463212,40.020541","sequence":"2"}]}]}
  """

  @linename ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"6",
   "suggestion":{"keywords":[],"cities":[]},
   "buslines":[{"id":"900000211579","type":"地铁",
    "name":"地铁1号线支线(青龙湖东--八角游乐园)",
    "polyline":"116.094016,39.808319;116.095791,39.80833;116.098,39.81",
    "citycode":"010","start_stop":"青龙湖东","end_stop":"八角游乐园",
    "start_time":"05:00","end_time":"23:00","distance":"31.2","loop":"0",
    "status":"1"}]}
  """

  test "lineid/3 sends the id, and takes extensions the line pages document", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/lineid", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @lineid}
    end)

    assert {:ok, %Amap.Bus.Lines{}} = Bus.lineid(client, "131000010042", extensions: :all)

    assert_receive {:query, query}
    assert query["id"] == "131000010042"
    assert query["extensions"] == "all"
  end

  test "linename/3 leaves city out when it was not given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @linename}
    end)

    assert {:ok, %Amap.Bus.Lines{}} = Bus.linename(client, "地铁1号线")

    assert_receive {:query, query}
    assert query["keywords"] == "地铁1号线"
    refute Map.has_key?(query, "city")
  end

  test "linename/3 sends city, offset and page when they were given", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @linename}
    end)

    Bus.linename(client, "地铁1号线", city: "北京", offset: 20, page: 1)

    assert_receive {:query, query}
    assert query["city"] == "北京"
    assert query["offset"] == "20"
    assert query["page"] == "1"
  end

  test "linename/3 follows its own page ceiling, not stopname's", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @linename}
    end)

    Bus.linename(client, "地铁1号线", page: 10)

    assert_receive {:query, query}
    assert query["page"] == "10"

    assert_raise ArgumentError, ~r/:page must be between 1 and 10, got: 11/, fn ->
      Bus.linename(client, "地铁1号线", page: 11)
    end

    assert_raise ArgumentError, ~r/:offset must be between 1 and 100, got: 101/, fn ->
      Bus.linename(client, "地铁1号线", offset: 101)
    end

    assert_raise ArgumentError, ~r/:extensions must be one of \[:base, :all\], got: :full/, fn ->
      Bus.lineid(client, "131000010042", extensions: :full)
    end
  end

  test "maps a line and the stops it serves", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/bus/lineid", fn _req -> {200, @lineid} end)

    assert {:ok, lines} = Bus.lineid(client, "131000010042")

    assert lines.count == "1"
    assert lines.suggestion == nil

    assert [%Amap.Bus.Line{} = line] = lines.buslines
    assert line.id == "131000010042"
    assert line.type == "普通公交"
    assert line.name == "450路(青年路小区--望京西枢纽站)"
    assert line.citycode == "010"
    assert line.start_stop == "青年路小区"
    assert line.end_stop == "望京西枢纽站"
    assert line.start_time == "05:30"
    assert line.end_time == "22:30"
    assert line.uicolor == "#0000ff"
    assert line.timedesc == ~s({"01":["05:30","22:30"]})
    assert line.distance == "12.5"
    assert line.loop == "0"
    assert line.status == "1"
    assert line.direc == "131000010043"
    assert line.company == "北京公交集团"
    assert line.basic_price == "2"
    assert line.total_price == "5"

    assert line.polyline == [
             [{116.476437, 39.98701}, {116.463212, 40.020541}, {116.455, 40.033}]
           ]

    assert line.bounds == [{116.455, 39.987}, {116.476, 40.033}]

    assert [%Amap.Bus.Line.Stop{} = first, %Amap.Bus.Line.Stop{} = second] = line.busstops
    assert first.id == "BV10006672"
    assert first.name == "阜通东大街(公交站)"
    assert first.location == {116.476437, 39.98701}
    assert first.sequence == "1"
    assert second.sequence == "2"
  end

  test "maps a line keyword search's suggestion and Chinese type", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn _req -> {200, @linename} end)

    assert {:ok, lines} = Bus.linename(client, "地铁1号线")

    assert lines.count == "6"
    assert lines.suggestion == %Suggestion{keywords: [], cities: []}

    assert [%Amap.Bus.Line{} = line] = lines.buslines
    assert line.type == "地铁"
    assert line.name == "地铁1号线支线(青龙湖东--八角游乐园)"
    assert line.busstops == []
  end

  test "answers with no lines when Amap sent none or sent an empty list", %{
    server: server,
    client: client
  } do
    bare = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0"}>
    empty = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0","buslines":[]}>

    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn _req -> {200, bare} end)

    assert {:ok, %Amap.Bus.Lines{count: "0", suggestion: nil, buslines: []}} =
             Bus.linename(client, "地铁1号线")

    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn _req -> {200, empty} end)

    assert {:ok, %Amap.Bus.Lines{buslines: []}} = Bus.linename(client, "地铁1号线")
  end

  test "reads a malformed polyline or position as nil rather than raising", %{
    server: server,
    client: client
  } do
    malformed =
      ~S"""
      {"status":"1","info":"OK","infocode":"10000","count":"1",
       "buslines":[{"id":"1","type":"地铁","polyline":"nonsense;also-nonsense",
        "bounds":"1,2;three",
        "busstops":[{"id":"BV1","name":"站","location":42,"sequence":"1"}]}]}
      """

    TestServer.expect_once(server, "GET", "/v3/bus/lineid", fn _req -> {200, malformed} end)

    assert {:ok, %Amap.Bus.Lines{buslines: [line]}} = Bus.lineid(client, "1")
    assert line.polyline == nil
    assert line.bounds == nil
    assert [%Amap.Bus.Line.Stop{location: nil, sequence: "1"}] = line.busstops
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

    TestServer.expect_once(server, "GET", "/v3/bus/stopid", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = Bus.stopid(client, "BV10006672")
  end

  test "returns an error rather than raising for a line refusal", %{
    server: server,
    client: client
  } do
    refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

    TestServer.expect_once(server, "GET", "/v3/bus/linename", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = Bus.linename(client, "地铁1号线")
  end
end
