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

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

    TestServer.expect_once(server, "GET", "/v3/bus/stopid", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = Bus.stopid(client, "BV10006672")
  end
end
