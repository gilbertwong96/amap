defmodule Amap.NewRoute.WalkingTest do
  use ExUnit.Case, async: true

  alias Amap.NewRoute
  alias Amap.NewRoute.Cost
  alias Amap.NewRoute.Navi
  alias Amap.NewRoute.Route
  alias Amap.NewRoute.Tmc
  alias Amap.TestServer

  # The whole answer, with every group this endpoint has — plus a step-level `cost` and
  # `tmcs`. `tmcs` is not a group a *walking* call may ask for, but the reader is shared
  # with `driving/4` and reads a group wherever Amap puts it, so this payload is the only
  # one that feeds the step-level branch (Task 7's carried item 4).
  @walked ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("route":{"origin":"116.466485,39.995197","destination":"116.46424,40.020642",) <>
            ~s("paths":[{"distance":"3200",) <>
            ~s("polyline":"116.466485,39.995197;116.46424,40.020642",) <>
            ~s("navi":{"action":"直行","assistant_action":""},) <>
            ~s("cost":{"duration":"2400","tolls":"0","toll_distance":"0"},) <>
            ~s("steps":[{"instruction":"步行54米右转","orientation":"北",) <>
            ~s("road_name":"阜通东大街","step_distance":"54",) <>
            ~s("navi":{"action":"直行","assistant_action":"","walk_type":"1"},) <>
            ~s("cost":{"duration":"54","tolls":"0","toll_distance":"0"},) <>
            ~s("tmcs":{"tmc_status":"畅通","tmc_distance":"54",) <>
            ~s("tmc_polyline":"116.466485,39.995197;116.46424,40.020642"},) <>
            ~s("polyline":"116.466485,39.995197;116.46424,40.020642"}]}]}})

  # Base fields only: what arrives when show_fields was not asked for.
  @base ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
          ~s("route":{"origin":"116.466485,39.995197","destination":"116.46424,40.020642",) <>
          ~s("paths":[{"distance":"3200",) <>
          ~s("steps":[{"instruction":"步行54米右转","orientation":"北",) <>
          ~s("road_name":"阜通东大街","step_distance":"54"}]}]}})

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
    expect_walking(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert_receive {:params, params}
    assert params["origin"] == "116.466485,39.995197"
    assert params["destination"] == "116.46424,40.020642"
    refute Map.has_key?(params, "isindoor")
    refute Map.has_key?(params, "alternative_route")
    refute Map.has_key?(params, "show_fields")
    refute Map.has_key?(params, "strategy")
  end

  test "sends isindoor as 1 or 0", %{server: server, client: client} do
    parent = self()
    expect_walking(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642},
               isindoor: true
             )

    assert_receive {:params, params}
    assert params["isindoor"] == "1"

    TestServer.expect_once(server, "GET", "/v5/direction/walking", fn req ->
      send(parent, {:params, URI.decode_query(req.query)})
      {200, @base}
    end)

    assert {:ok, %Route{}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642},
               isindoor: false
             )

    assert_receive {:params, params}
    assert params["isindoor"] == "0"

    assert_raise ArgumentError, ~r/:isindoor must be a boolean/, fn ->
      NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642}, isindoor: 1)
    end
  end

  test "takes alternative_route as 1, 2 or 3", %{server: server, client: client} do
    parent = self()
    expect_walking(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642},
               alternative_route: 3
             )

    assert_receive {:params, params}
    assert params["alternative_route"] == "3"

    for count <- [0, 4] do
      assert_raise ArgumentError, ~r/:alternative_route must be one of/, fn ->
        NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642},
          alternative_route: count
        )
      end
    end
  end

  test "sends show_fields comma-joined and refuses a group this page does not list", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_walking(server, @walked, parent)

    assert {:ok, %Route{}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642},
               show_fields: [:cost, :walk_type]
             )

    assert_receive {:params, params}
    # Walking's own set: no `tmcs`, no `cities`, no `district`, unlike driving's.
    assert params["show_fields"] == "cost,walk_type"

    for refused <- [[:tmcs], [:cost, :cities]] do
      assert_raise ArgumentError, ~r/:show_fields must be a subset of/, fn ->
        NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642},
          show_fields: refused
        )
      end
    end
  end

  test "maps the walking answer, whose route has no taxi_cost and no restriction", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v5/direction/walking", fn _req -> {200, @walked} end)

    assert {:ok, route} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert route.origin == {116.466485, 39.995197}
    assert route.destination == {116.46424, 40.020642}
    assert route.taxi_cost == nil

    assert [path] = route.paths
    assert path.distance == "3200"
    # This endpoint's page documents neither field, so both stay nil.
    assert path.restriction == nil
    assert path.cities == nil
    assert path.district == nil
    assert path.polyline == [{116.466485, 39.995197}, {116.46424, 40.020642}]

    assert %Navi{action: "直行"} = path.navi
    assert %Cost{duration: "2400"} = path.cost

    assert [step] = path.steps
    assert step.instruction == "步行54米右转"
    assert step.road_name == "阜通东大街"
    assert step.step_distance == "54"
    # The wire puts `walk_type` inside a step's `navi`, even though the page lists it
    # as a `show_fields` group of its own.
    assert %Navi{action: "直行", walk_type: "1"} = step.navi
    assert step.polyline == [{116.466485, 39.995197}, {116.46424, 40.020642}]

    # The step-level reading of the groups, which no other payload feeds.
    assert %Cost{duration: "54", tolls: "0"} = step.cost
    assert [%Tmc{tmc_status: "畅通", tmc_distance: "54"}] = step.tmcs

    # The page says `taxi` is not returned inside a step here, so there is no field for it.
    refute Map.has_key?(step, :taxi)
  end

  test "leaves the optional groups empty when show_fields was not asked for", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v5/direction/walking", fn _req -> {200, @base} end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert path.cost == nil
    assert path.navi == nil
    assert path.polyline == nil
    assert path.tmcs == []

    assert [step] = path.steps
    assert step.cost == nil
    assert step.navi == nil
    assert step.tmcs == []
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v5/direction/walking", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} =
             NewRoute.walking(client, {116.466485, 39.995197}, {116.46424, 40.020642})
  end

  defp expect_walking(server, body, parent) do
    TestServer.expect_once(server, "GET", "/v5/direction/walking", fn req ->
      send(parent, {:params, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
