defmodule Amap.NewRoute.BicyclingTest do
  use ExUnit.Case, async: true

  alias Amap.NewRoute
  alias Amap.NewRoute.Cost
  alias Amap.NewRoute.Navi
  alias Amap.NewRoute.Route
  alias Amap.TestServer

  @bicycling_path "/v5/direction/bicycling"
  @electrobike_path "/v5/direction/electrobike"

  # The v5 cycling answer: walking's skeleton, no `taxi_cost` and no `restriction`, and
  # `walk_type` inside each step's `navi` — the page prints it as a `show_fields` group
  # of its own. The one probe that saw where it arrives was `/v5/direction/walking`;
  # bicycling and electrobike share that page and mapper but were not probed.
  @ridden ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("route":{"origin":"116.466485,39.995197","destination":"116.46424,40.020642",) <>
            ~s("paths":[{"distance":"4300",) <>
            ~s("polyline":"116.466485,39.995197;116.46424,40.020642",) <>
            ~s("navi":{"action":"骑行54米右转","assistant_action":"到达目的地"},) <>
            ~s("cost":{"duration":"1500","tolls":"0","toll_distance":"0"},) <>
            ~s("steps":[{"instruction":"骑行54米右转","orientation":"北",) <>
            ~s("road_name":"阜通东大街","step_distance":"54",) <>
            ~s("navi":{"action":"骑行54米右转","assistant_action":"","walk_type":"1"},) <>
            ~s("polyline":"116.466485,39.995197;116.46424,40.020642"}]}]}})

  @base ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
          ~s("route":{"origin":"116.466485,39.995197","destination":"116.46424,40.020642",) <>
          ~s("paths":[{"distance":"4300",) <>
          ~s("steps":[{"instruction":"骑行54米右转","orientation":"北",) <>
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

  test "each function sends its own path, and nothing else", %{server: server, client: client} do
    parent = self()
    expect_ride(server, @bicycling_path, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert_receive {:params, params}
    assert params["origin"] == "116.466485,39.995197"
    assert params["destination"] == "116.46424,40.020642"
    refute Map.has_key?(params, "alternative_route")
    refute Map.has_key?(params, "show_fields")
    # Neither page has strategy or indoor routing.
    refute Map.has_key?(params, "strategy")
    refute Map.has_key?(params, "isindoor")

    expect_ride(server, @electrobike_path, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.electrobike(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert_receive {:params, params}
    refute Map.has_key?(params, "alternative_route")
    refute Map.has_key?(params, "show_fields")
  end

  # The one parameter the two share, asserted on the *other* function from the one the
  # path test uses, so neither can pass by being wired to the other's path.
  test "electrobike takes alternative_route as 1, 2 or 3", %{server: server, client: client} do
    parent = self()
    expect_ride(server, @electrobike_path, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.electrobike(client, {116.466485, 39.995197}, {116.46424, 40.020642},
               alternative_route: 2
             )

    assert_receive {:params, params}
    assert params["alternative_route"] == "2"

    for count <- [0, 4] do
      assert_raise ArgumentError, ~r/:alternative_route must be one of/, fn ->
        NewRoute.electrobike(client, {116.466485, 39.995197}, {116.46424, 40.020642},
          alternative_route: count
        )
      end
    end
  end

  test "bicycling sends show_fields comma-joined and refuses a group these pages lack", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_ride(server, @bicycling_path, @ridden, parent)

    assert {:ok, %Route{}} =
             NewRoute.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642},
               show_fields: [:cost, :navi]
             )

    assert_receive {:params, params}
    # The same four groups walking has — no `tmcs`, `cities` or `district`.
    assert params["show_fields"] == "cost,navi"

    for refused <- [[:tmcs], [:cost, :cities]] do
      assert_raise ArgumentError, ~r/:show_fields must be a subset of/, fn ->
        NewRoute.electrobike(client, {116.466485, 39.995197}, {116.46424, 40.020642},
          show_fields: refused
        )
      end
    end
  end

  test "maps the answer to the same Route walking returns", %{server: server, client: client} do
    expect_ride(server, @bicycling_path, @ridden, self())

    assert {:ok, route} =
             NewRoute.bicycling(client, {116.466485, 39.995197}, {116.46424, 40.020642})

    assert route.origin == {116.466485, 39.995197}
    assert route.destination == {116.46424, 40.020642}
    assert route.taxi_cost == nil

    assert [path] = route.paths
    assert path.distance == "4300"
    assert path.restriction == nil
    assert path.polyline == [{116.466485, 39.995197}, {116.46424, 40.020642}]
    assert %Navi{action: "骑行54米右转"} = path.navi
    assert %Cost{duration: "1500"} = path.cost

    assert [step] = path.steps
    assert step.instruction == "骑行54米右转"
    assert step.road_name == "阜通东大街"
    # `walk_type` arrives inside a step's `navi` rather than flat on the step, even
    # though the page lists it as a `show_fields` group of its own — the live run saw
    # this on `/v5/direction/walking`, and this fixture stands in for the same shape.
    assert %Navi{action: "骑行54米右转", walk_type: "1"} = step.navi
    assert step.step_distance == "54"
    assert step.polyline == [{116.466485, 39.995197}, {116.46424, 40.020642}]
    # `tmcs` was not asked for, so the reader leaves it empty.
    assert step.tmcs == []
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    expect_ride(server, @electrobike_path, refusal, self())

    assert {:error, %Amap.Error{}} =
             NewRoute.electrobike(client, {116.466485, 39.995197}, {116.46424, 40.020642})
  end

  defp expect_ride(server, path, body, parent) do
    TestServer.expect_once(server, "GET", path, fn req ->
      send(parent, {:params, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
