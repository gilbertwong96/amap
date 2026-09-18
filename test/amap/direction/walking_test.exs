defmodule Amap.Direction.WalkingTest do
  use ExUnit.Case, async: true

  alias Amap.Direction
  alias Amap.Direction.Route
  alias Amap.Direction.Step
  alias Amap.TestServer

  @walked ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("route":{"origin":"116.434307,39.90909","destination":"116.434446,39.90816",) <>
            ~s("paths":[{"distance":"1234","duration":"900","steps":[) <>
            ~s({"instruction":"沿当前道路向前步行100米","road":"阜通东大街","distance":"100",) <>
            ~s("orientation":"北","duration":"80",) <>
            ~s("polyline":"116.481247,39.990704;116.481270,39.990726",) <>
            ~s("action":"直行","assistant_action":"","walk_type":"1"}]}]}})

  # The envelope alone: Amap sends this when it found no route at all.
  @no_route ~s({"status":"1","info":"OK","infocode":"10000","count":"0"})

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

  test "sends the two points and nothing else", %{server: server, client: client} do
    parent = self()
    expect_walking(server, @walked, parent)

    assert {:ok, %Route{}} =
             Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert_receive {:query, query}
    assert query["key"] == "test-key"
    assert query["origin"] == "116.434307,39.90909"
    assert query["destination"] == "116.434446,39.90816"
    refute Map.has_key?(query, "origin_id")
    refute Map.has_key?(query, "destination_id")
  end

  test "sends the POI ids under the names this endpoint documents", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_walking(server, @walked, parent)

    assert {:ok, %Route{}} =
             Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               origin_id: "B000A7BD6C",
               destination_id: "B000A7BD6D"
             )

    assert_receive {:query, query}
    assert query["origin_id"] == "B000A7BD6C"
    assert query["destination_id"] == "B000A7BD6D"
    # The driving endpoint on the same page spells these without the underscore.
    refute Map.has_key?(query, "originid")
    refute Map.has_key?(query, "destinationid")
  end

  test "rejects an end that is not a coordinate pair", %{client: client} do
    assert_raise ArgumentError, ~r/:origin must be a \{lon, lat\} pair of numbers/, fn ->
      Direction.walking(client, "116.434307,39.90909", {116.434446, 39.90816})
    end

    assert_raise ArgumentError, ~r/:destination must be a \{lon, lat\} pair of numbers/, fn ->
      Direction.walking(client, {116.434307, 39.90909}, {116.434446, "39.90816"})
    end
  end

  test "rejects an empty POI id rather than sending one", %{client: client} do
    assert_raise ArgumentError, ~r/:origin_id must be a non-empty string/, fn ->
      Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816}, origin_id: "")
    end
  end

  test "maps the route, its paths and their steps", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/walking", fn _req -> {200, @walked} end)

    assert {:ok, route} =
             Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert route.origin == {116.434307, 39.90909}
    assert route.destination == {116.434446, 39.90816}
    # Walking answers no taxi_cost; driving is where that field is filled.
    assert route.taxi_cost == nil

    assert [path] = route.paths
    assert path.distance == "1234"
    assert path.duration == "900"

    assert [step] = path.steps
    assert step.instruction == "沿当前道路向前步行100米"
    assert step.road == "阜通东大街"
    assert step.distance == "100"
    assert step.orientation == "北"
    assert step.duration == "80"
    assert step.action == "直行"
    assert step.assistant_action == ""
    # Scalar values keep the wire's form: this is a string, not an integer.
    assert step.walk_type == "1"
  end

  test "decodes a step's polyline into one flat list of points", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/walking", fn _req -> {200, @walked} end)

    assert {:ok, %Route{paths: [%{steps: [%Step{} = step]}]}} =
             Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert step.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]
  end

  test "answers an empty Route when Amap sends no route at all", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/walking", fn _req ->
      {200, @no_route}
    end)

    assert {:ok, %Route{origin: nil, destination: nil, paths: []}} =
             Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816})
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/direction/walking", fn _req ->
      {200, refusal}
    end)

    assert {:error, %Amap.Error{}} =
             Direction.walking(client, {116.434307, 39.90909}, {116.434446, 39.90816})
  end

  defp expect_walking(server, body, parent) do
    TestServer.expect_once(server, "GET", "/v3/direction/walking", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
