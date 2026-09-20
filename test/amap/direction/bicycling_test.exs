defmodule Amap.Direction.BicyclingTest do
  use ExUnit.Case, async: true

  alias Amap.Direction
  alias Amap.Direction.Route
  alias Amap.Direction.Step
  alias Amap.TestServer

  @cycled ~s({"errcode":0,"errmsg":"OK",) <>
            ~s("data":{"origin":"116.466485,39.995197","destination":"116.46424,40.020642",) <>
            ~s("paths":[{"distance":"5432","duration":"1200","steps":[) <>
            ~s({"instruction":"骑行54米右转","road":"建国门北大街","distance":"54",) <>
            ~s("orientation":"南","duration":"20",) <>
            ~s("polyline":"116.481247,39.990704;116.481270,39.990726",) <>
            ~s("action":"右转","assistant_action":"到达目的地"}]}]}})

  # What the page documents for a 抓路 failure: too few points, or too sparse.
  @failed ~s({"errcode":30001,"errdetail":"抓路失败","errmsg":"FAILED"})

  # The same envelope carrying no `data` at all: Amap found nothing to report.
  @no_route ~s({"errcode":0,"errmsg":"OK"})

  setup do
    server = TestServer.start!()

    # The tsapi base URL points at a closed port on purpose: this endpoint answers
    # the Falcon envelope but lives on the Web service host, so a call that sent to
    # the tsapi host would fail in transport rather than passing quietly.
    client =
      Amap.new(
        key: "test-key",
        base_urls: %{restapi: "http://localhost:#{server.port}", tsapi: "http://localhost:1"}
      )

    {:ok, server: server, client: client}
  end

  test "goes to the Web service host, envelope notwithstanding", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_bicycling(server, @cycled, parent)

    # Reaching the server at all is the assertion: the track host is closed above.
    assert {:ok, %Route{}} =
             Direction.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert_receive {:query, query}
    assert query["origin"] == "116.466485,39.995197"
    assert query["destination"] == "116.46424,40.020642"
  end

  test "refuses a point that is not a {lon, lat} pair", %{client: client} do
    assert_raise ArgumentError, ~r/:origin must be a \{lon, lat\} pair of numbers/, fn ->
      Direction.bicycling(client, "116.466485,39.995197", {116.46424, 40.020642})
    end

    assert_raise ArgumentError, ~r/:destination must be a \{lon, lat\} pair of numbers/, fn ->
      Direction.bicycling(client, {116.466485, 39.995197}, nil)
    end
  end

  test "answers an empty Route when Amap sends no data at all", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v4/direction/bicycling", fn _req ->
      {200, @no_route}
    end)

    assert {:ok, %Route{origin: nil, destination: nil, paths: []}} =
             Direction.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})
  end

  test "is not signed, because this page documents no sig", %{server: server} do
    # A private key on purpose: signing follows the host and envelope, so a call
    # wired as `:restapi` without `envelope: :tsapi` — the mistake this test exists
    # to catch — would sign, and the refutation below would bite.
    client =
      Amap.new(
        key: "test-key",
        private_key: "test-secret",
        base_urls: %{restapi: "http://localhost:#{server.port}", tsapi: "http://localhost:1"}
      )

    parent = self()
    expect_bicycling(server, @cycled, parent)

    assert {:ok, %Route{}} =
             Direction.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert_receive {:query, query}
    assert query["key"] == "test-key"
    refute Map.has_key?(query, "sig")
  end

  test "maps the data payload as the v3 endpoints map their route", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v4/direction/bicycling", fn _req ->
      {200, @cycled}
    end)

    assert {:ok, route} =
             Direction.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert route.origin == {116.466485, 39.995197}
    assert route.destination == {116.46424, 40.020642}
    # Cycling answers no taxi_cost; driving is where that field is filled.
    assert route.taxi_cost == nil

    assert [path] = route.paths
    assert path.distance == "5432"
    assert path.duration == "1200"

    assert [%Step{} = step] = path.steps
    assert step.instruction == "骑行54米右转"
    assert step.road == "建国门北大街"
    assert step.distance == "54"
    assert step.orientation == "南"
    assert step.duration == "20"
    assert step.action == "右转"
    assert step.assistant_action == "到达目的地"
    # A step carries no polylines as parts here either: one flat list of points.
    assert step.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]
  end

  test "answers a track-family error for a 抓路 failure", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v4/direction/bicycling", fn _req ->
      {200, @failed}
    end)

    assert {:error, %Amap.Error{family: :tsapi, code: 30001} = error} =
             Direction.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert error.message == "FAILED"
    assert error.detail == "抓路失败"
  end

  defp expect_bicycling(server, body, parent) do
    TestServer.expect_once(server, "GET", "/v4/direction/bicycling", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
