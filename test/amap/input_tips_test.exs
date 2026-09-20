defmodule Amap.InputTipsTest do
  use ExUnit.Case, async: true

  alias Amap.InputTips
  alias Amap.InputTips.Result
  alias Amap.InputTips.Tip
  alias Amap.TestServer

  @tips ~S"""
  {"status":"1","info":"OK","infocode":"10000","count":"2",
   "tips":{"tip":[
    {"id":"B000A83M61","name":"招商银行(北京分行)","district":"北京市朝阳区",
     "adcode":"110105","location":"116.45,39.93","address":"朝阳区望京街9号"},
    {"id":"BV10002739","name":"招商银行站","district":"北京市朝阳区","adcode":"110105"}
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

  test "inputtips/3 sends the keyword and the options the page documents", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @tips}
    end)

    assert {:ok, %Result{}} =
             InputTips.inputtips(client, "招商银行",
               type: ["160100", "160300"],
               location: {116.45, 39.93},
               city: "010",
               city_limit: true,
               datatype: [:poi, :bus]
             )

    assert_receive {:query, query}
    assert query["keywords"] == "招商银行"
    assert query["type"] == "160100|160300"
    assert query["location"] == "116.45,39.93"
    assert query["city"] == "010"
    assert query["citylimit"] == "true"
    assert query["datatype"] == "poi|bus"

    assert Map.keys(query) -- ~w(key keywords type location city citylimit datatype) == []
  end

  test "inputtips/3 sends nothing else when only the keyword was given", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @tips}
    end)

    assert {:ok, %Result{}} = InputTips.inputtips(client, "招商银行")

    assert_receive {:query, query}
    assert query["keywords"] == "招商银行"
    assert Map.keys(query) -- ["key", "keywords"] == []
  end

  test "rejects an empty keyword and values the page does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:keywords must be a non-empty string/, fn ->
      InputTips.inputtips(client, "")
    end

    assert_raise ArgumentError, ~r/:type must be a non-empty list/, fn ->
      InputTips.inputtips(client, "招商银行", type: "160100")
    end

    assert_raise ArgumentError, ~r/:type must be a list of non-empty strings/, fn ->
      InputTips.inputtips(client, "招商银行", type: ["160100", ""])
    end

    assert_raise ArgumentError, ~r/:location must be a \{lon, lat\} pair of numbers/, fn ->
      InputTips.inputtips(client, "招商银行", location: "116.45,39.93")
    end

    assert_raise ArgumentError, ~r/:city must be a non-empty string/, fn ->
      InputTips.inputtips(client, "招商银行", city: "")
    end

    assert_raise ArgumentError, ~r/:city_limit must be a boolean, got: "true"/, fn ->
      InputTips.inputtips(client, "招商银行", city_limit: "true")
    end

    assert_raise ArgumentError,
                 ~r/:datatype must be a subset of \[:all, :poi, :bus, :busline\], got unknown: \[:typo\]/,
                 fn ->
                   InputTips.inputtips(client, "招商银行", datatype: [:poi, :typo])
                 end

    assert_raise ArgumentError, ~r/:datatype must be a non-empty list of/, fn ->
      InputTips.inputtips(client, "招商银行", datatype: [])
    end

    assert_raise ArgumentError, ~r/:datatype must be a non-empty list of/, fn ->
      InputTips.inputtips(client, "招商银行", datatype: :poi)
    end
  end

  test "maps the tips, and a busline tip's missing location as nil", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn _req -> {200, @tips} end)

    assert {:ok, result} = InputTips.inputtips(client, "招商银行")

    assert result.count == "2"

    assert [%Tip{} = first, %Tip{} = second] = result.tips
    assert first.id == "B000A83M61"
    assert first.name == "招商银行(北京分行)"
    assert first.district == "北京市朝阳区"
    assert first.adcode == "110105"
    assert first.location == {116.45, 39.93}
    assert first.address == "朝阳区望京街9号"

    assert second.id == "BV10002739"
    assert second.location == nil
    assert second.address == nil
  end

  test "answers with nothing when Amap sent no tips", %{server: server, client: client} do
    bare = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0"}>
    emptied = ~s<{"status":"1","info":"OK","infocode":"10000","count":"0","tips":{"tip":null}}>

    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn _req -> {200, bare} end)

    assert {:ok, %Result{count: "0", tips: []}} = InputTips.inputtips(client, "招商银行")

    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn _req -> {200, emptied} end)

    assert {:ok, %Result{tips: []}} = InputTips.inputtips(client, "招商银行")
  end

  test "reads a malformed location as nil rather than raising", %{
    server: server,
    client: client
  } do
    malformed = ~S"""
    {"status":"1","info":"OK","infocode":"10000","count":"1",
     "tips":{"tip":[{"id":"B1","name":"站","location":"not-a-coordinate","adcode":[]},
      "not-an-object"]}}
    """

    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn _req ->
      {200, malformed}
    end)

    assert {:ok, %Result{tips: [%Tip{} = tip]}} = InputTips.inputtips(client, "站")
    assert tip.location == nil
    assert tip.adcode == nil
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s<{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}>

    TestServer.expect_once(server, "GET", "/v3/assistant/inputtips", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} = InputTips.inputtips(client, "招商银行")
  end
end
