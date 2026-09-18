defmodule Amap.TrafficTest do
  use ExUnit.Case, async: true

  alias Amap.TestServer
  alias Amap.Traffic
  alias Amap.Traffic.Evaluation
  alias Amap.Traffic.Road

  @traffic ~s({"status":"1","info":"OK","infocode":"10000","trafficinfo":{) <>
             ~s("description":"中关村大街: 畅通",) <>
             ~s("evaluation":{"expedite":"90.18","congested":"3.42","blocked":"0",) <>
             ~s("unknown":"6.4"},) <>
             ~s("roads":[) <>
             ~s({"name":"中关村大街","status":"1","direction":"南向北","angle":"180",) <>
             ~s("lcodes":"0100001","speed":"45","polyline":"116.31,39.99;116.32,39.995"},) <>
             ~s({"name":"北四环西路","status":"2","direction":"东向西","angle":"90",) <>
             ~s("lcodes":"-0100002","speed":"20","polyline":"116.35,39.98"}]}})

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

  test "road/4 sends the level, the name and the adcode", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/traffic/status/road", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @traffic}
    end)

    assert {:ok, %Traffic{}} =
             Traffic.road(client, 4, "中关村大街", adcode: "110108", extensions: :all)

    assert_receive {:query, query}
    assert query["level"] == "4"
    assert query["name"] == "中关村大街"
    assert query["adcode"] == "110108"
    assert query["extensions"] == "all"
    refute Map.has_key?(query, "city")
  end

  test "road/4 needs one of city and adcode", %{client: client} do
    assert_raise ArgumentError, ~r/:city or :adcode is required/, fn ->
      Traffic.road(client, 4, "中关村大街")
    end

    assert_raise ArgumentError, ~r/:name must be a non-empty string/, fn ->
      Traffic.road(client, 4, "", adcode: "110108")
    end
  end

  test "circle/4 sends the centre and the radius", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/traffic/status/circle", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @traffic}
    end)

    Traffic.circle(client, 5, {116.3057764, 39.98641364}, radius: 1500)

    assert_receive {:query, query}
    assert query["level"] == "5"
    assert query["location"] == "116.305776,39.986414"
    assert query["radius"] == "1500"
    refute Map.has_key?(query, "extensions")
  end

  test "circle/4 leaves the radius out when it was not given", %{server: server, client: client} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/traffic/status/circle", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @traffic}
    end)

    Traffic.circle(client, 5, {116.3057764, 39.98641364})

    assert_receive {:query, query}
    refute Map.has_key?(query, "radius")
  end

  test "rejects a radius or level Amap does not document", %{client: client} do
    assert_raise ArgumentError, ~r/:radius must be between 1 and 4999, got: 5000/, fn ->
      Traffic.circle(client, 5, {116.3, 39.9}, radius: 5000)
    end

    assert_raise ArgumentError, ~r/:radius must be an integer, got: 1500.0/, fn ->
      Traffic.circle(client, 5, {116.3, 39.9}, radius: 1500.0)
    end

    assert_raise ArgumentError, ~r/:level must be between 1 and 6, got: 7/, fn ->
      Traffic.circle(client, 7, {116.3, 39.9})
    end

    assert_raise ArgumentError, ~r/:level must be between 1 and 6, got: 0/, fn ->
      Traffic.road(client, 0, "中关村大街", adcode: "110108")
    end

    assert_raise ArgumentError, ~r/:extensions must be one of \[:base, :all\], got: :full/, fn ->
      Traffic.circle(client, 5, {116.3, 39.9}, extensions: :full)
    end
  end

  test "rectangle/4 sends the two corners semicolon-separated", %{
    server: server,
    client: client
  } do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/traffic/status/rectangle", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, @traffic}
    end)

    Traffic.rectangle(client, 5, {{116.351147, 39.966309}, {116.357134, 39.968727}})

    assert_receive {:query, query}
    assert query["rectangle"] == "116.351147,39.966309;116.357134,39.968727"
  end

  test "rectangle/4 rejects corners that are not coordinates", %{client: client} do
    assert_raise ArgumentError, ~r/:rectangle must be two \{lon, lat\} corners/, fn ->
      Traffic.rectangle(client, 5, {116.35, 39.96})
    end

    assert_raise ArgumentError, ~r/:rectangle must be two \{lon, lat\} corners/, fn ->
      Traffic.rectangle(client, 5, {{116.35, 39.96}, [116.36, 39.97]})
    end

    assert_raise ArgumentError, ~r/:rectangle must be a \{lon, lat\} pair of numbers/, fn ->
      Traffic.rectangle(client, 5, {{"116.35", "39.96"}, {116.36, 39.97}})
    end
  end

  test "maps the evaluation, the description and every road", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/traffic/status/circle", fn _req ->
      {200, @traffic}
    end)

    assert {:ok, traffic} = Traffic.circle(client, 5, {116.31, 39.99})
    assert traffic.description == "中关村大街: 畅通"

    assert traffic.evaluation == %Evaluation{
             expedite: "90.18",
             congested: "3.42",
             blocked: "0",
             unknown: "6.4"
           }

    assert [%Road{} = first, %Road{} = second] = traffic.roads
    assert first.name == "中关村大街"
    assert first.status == "1"
    assert first.direction == "南向北"
    assert first.angle == "180"
    assert first.speed == "45"
    assert first.polyline == [{116.31, 39.99}, {116.32, 39.995}]

    assert second.lcodes == "-0100002"
    assert second.polyline == [{116.35, 39.98}]
  end

  test "answers with no roads when Amap sent none", %{server: server, client: client} do
    flat =
      ~s({"status":"1","info":"OK","infocode":"10000","trafficinfo":{) <>
        ~s("description":"中关村大街: 畅通",) <>
        ~s("evaluation":{"expedite":"90.18","congested":"3.42","blocked":"0",) <>
        ~s("unknown":"6.4"},"roads":[]}})

    TestServer.expect_once(server, "GET", "/v3/traffic/status/circle", fn _req -> {200, flat} end)

    assert {:ok, %Traffic{roads: [], evaluation: %Evaluation{}}} =
             Traffic.circle(client, 5, {116.31, 39.99})
  end

  test "returns an error rather than raising when the key lacks 高级服务", %{
    server: server,
    client: client
  } do
    refusal =
      ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/traffic/status/circle", fn _req ->
      {200, refusal}
    end)

    assert {:error, %Amap.Error{}} = Traffic.circle(client, 5, {116.31, 39.99})
  end
end
