defmodule Amap.Direction.DrivingTest do
  use ExUnit.Case, async: true

  alias Amap.Direction
  alias Amap.Direction.City
  alias Amap.Direction.District
  alias Amap.Direction.Road
  alias Amap.Direction.Route
  alias Amap.Direction.Tmc
  alias Amap.TestServer

  @driven ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("route":{"origin":"116.481028,39.989643","destination":"116.465302,40.004717",) <>
            ~s("taxi_cost":"21","paths":[{"distance":"12345","duration":"1200",) <>
            ~s("strategy":"速度优先","tolls":"5.0","restriction":"0","traffic_lights":"7",) <>
            ~s("toll_distance":"3000",) <>
            ~s("steps":[{"instruction":"沿阜通东大街向西行驶500米","orientation":"西",) <>
            ~s("road":"阜通东大街","distance":"500","tolls":"0","toll_distance":"0",) <>
            ~s("toll_road":"","polyline":"116.481247,39.990704;116.481270,39.990726",) <>
            ~s("action":"直行","assistant_action":"",) <>
            ~s("tmcs":[{"distance":"100","status":"畅通",) <>
            ~s("polyline":"116.481247,39.990704;116.481270,39.990726"}]}],) <>
            ~s("cities":[{"name":"北京市","citycode":"010","adcode":"110000",) <>
            ~s("districts":[{"name":"朝阳区","adcode":"110105"}]}],) <>
            ~s("districts":[{"name":"朝阳区","adcode":"110105"}]}]}})

  # The envelope alone: Amap sends this when it found no route at all.
  @no_route ~s({"status":"1","info":"OK","infocode":"10000","count":"0"})

  # `roadaggregation: true` replaces `steps` with `roads` on the wire, so this is the
  # shape a caller who asks for aggregation really gets: no `steps` key at all. The
  # entries carry the four keys the second live run printed — `road_distance`,
  # `road_name`, `steps`, `traffic_lights` — while the values under them stand in for
  # what Amap sends: that run printed the keys and no values, which is why
  # `Amap.Direction.Road`'s fields stay wide.
  @aggregated ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
                ~s("route":{"origin":"116.481028,39.989643","destination":"116.465302,40.004717",) <>
                ~s("paths":[{"distance":"12345","duration":"1200","strategy":"速度优先",) <>
                ~s("tolls":"5.0","restriction":"0","traffic_lights":"7","toll_distance":"3000",) <>
                ~s("roads":[{"road_distance":"1500","road_name":"示例路",) <>
                ~s("steps":[{"instruction":"沿示例路行驶","road":"示例路"}],) <>
                ~s("traffic_lights":"3"},) <>
                ~s({"road_distance":"2200","road_name":"示例二路",) <>
                ~s("steps":[{"instruction":"沿示例二路行驶","road":"示例二路"}],) <>
                ~s("traffic_lights":"2"}]}]}})

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
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717})

    assert_receive {:query, query}
    assert query["origin"] == "116.481028,39.989643"
    assert query["destination"] == "116.465302,40.004717"
    refute Map.has_key?(query, "strategy")
    # The page's 必填 column marks extensions required while its own sample table
    # says optional with default base; the parameter stays out of the request.
    refute Map.has_key?(query, "extensions")
  end

  test "accepts up to three origin pairs for 定位飘点 and refuses four", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(
               client,
               [{116.4, 39.9}, {116.5, 39.8}, {116.6, 39.7}],
               {116.465302, 40.004717}
             )

    assert_receive {:query, query}
    assert query["origin"] == "116.4,39.9|116.5,39.8|116.6,39.7"

    assert_raise ArgumentError, ~r/:origin must be at most 3 coordinate pairs/, fn ->
      Direction.driving(
        client,
        [{116.4, 39.9}, {116.5, 39.8}, {116.6, 39.7}, {116.7, 39.6}],
        {116.465302, 40.004717}
      )
    end

    assert_raise ArgumentError, ~r/:origin must be a \{lon, lat\} pair of numbers/, fn ->
      Direction.driving(client, [116.4, 39.9], {116.465302, 40.004717})
    end
  end

  test "sends the POI ids under the names driving documents", %{server: server, client: client} do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               origin_id: "B000A7BD6C",
               destination_id: "B000A7BD6D",
               destination_type: "190100"
             )

    assert_receive {:query, query}
    # Driving's page spells these without underscores, unlike walking's and v5's.
    assert query["originid"] == "B000A7BD6C"
    assert query["destinationid"] == "B000A7BD6D"
    assert query["destinationtype"] == "190100"
    refute Map.has_key?(query, "origin_id")
  end

  test "validates the strategy against this endpoint's own range", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               strategy: 20
             )

    assert_receive {:query, query}
    assert query["strategy"] == "20"

    assert_raise ArgumentError, ~r/:strategy must be between 0 and 20/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717}, strategy: 21)
    end
  end

  test "encodes waypoints as one semicolon-separated list and caps them at 16", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               waypoints: [{116.4, 39.9}, {116.5, 39.8}]
             )

    assert_receive {:query, query}
    assert query["waypoints"] == "116.4,39.9;116.5,39.8"

    seventeen = for n <- 1..17, do: {116.0 + n, 39.0 + n}

    assert_raise ArgumentError, ~r/:waypoints must be at most 16 coordinate pairs/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
        waypoints: seventeen
      )
    end
  end

  test "encodes an avoid-region longitude first, semicolons inside and pipes between", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    ring = [{116.4, 39.9}, {116.5, 39.9}, {116.5, 39.8}, {116.4, 39.8}]

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               avoidpolygons: [ring]
             )

    assert_receive {:query, query}
    # 经度在前，纬度在后 — longitude first, which is `Param.location/1`'s order and
    # *not* `Param.polygon/1`'s (that one is Falcon's latitude-first form).
    assert query["avoidpolygons"] == "116.4,39.9;116.5,39.9;116.5,39.8;116.4,39.8"

    other = [{116.6, 39.6}, {116.7, 39.6}, {116.7, 39.5}, {116.6, 39.5}]
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               avoidpolygons: [ring, other]
             )

    assert_receive {:query, query}

    assert query["avoidpolygons"] ==
             "116.4,39.9;116.5,39.9;116.5,39.8;116.4,39.8|116.6,39.6;116.7,39.6;116.7,39.5;116.6,39.5"
  end

  test "takes a single avoid-region on its own, not only a list of regions", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    ring = [{116.4, 39.9}, {116.5, 39.9}, {116.5, 39.8}, {116.4, 39.8}]

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               avoidpolygons: ring
             )

    assert_receive {:query, query}
    # A ring of points and a list of rings cannot be confused, so both are accepted —
    # the same reading `Amap.Param.polygon/1` does.
    assert query["avoidpolygons"] == "116.4,39.9;116.5,39.9;116.5,39.8;116.4,39.8"
  end

  test "caps an avoid region at 16 vertices and the whole set at 32 regions", %{
    client: client
  } do
    ring_of_17 = for n <- 1..17, do: {116.0 + n / 100, 39.0 + n / 100}

    assert_raise ArgumentError, ~r/:avoidpolygons ring must be at most 16 vertices/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
        avoidpolygons: [ring_of_17]
      )
    end

    thirty_three = for n <- 1..33, do: [{116.0 + n, 39.0}, {116.1 + n, 39.0}, {116.1 + n, 39.1}]

    assert_raise ArgumentError, ~r/:avoidpolygons must be at most 32 regions/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
        avoidpolygons: thirty_three
      )
    end
  end

  test "sends a licence plate split the way this endpoint documents it", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               province: "京",
               number: "NH1N11"
             )

    assert_receive {:query, query}
    assert query["province"] == "京"
    assert query["number"] == "NH1N11"
  end

  test "maps this endpoint's enums and its booleans as text", %{server: server, client: client} do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               cartype: :electric,
               ferry: :avoid,
               roadaggregation: true,
               nosteps: true,
               extensions: :all
             )

    assert_receive {:query, query}
    assert query["cartype"] == "1"
    assert query["ferry"] == "1"
    # Amap takes this one as the text `true`, not as `1`.
    assert query["roadaggregation"] == "true"
    assert query["nosteps"] == "1"
    assert query["extensions"] == "all"

    assert_raise ArgumentError, ~r/:cartype must be one of/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717}, cartype: :steam)
    end

    assert_raise ArgumentError, ~r/:ferry must be one of/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717}, ferry: :maybe)
    end

    assert_raise ArgumentError, ~r/:extensions must be one of/, fn ->
      Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
        extensions: :everything
      )
    end
  end

  test "sends ferry: :use as the wire's 0, which is what the default does", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               ferry: :use
             )

    assert_receive {:query, query}
    assert query["ferry"] == "0"
  end

  test "maps the route, its paths and their steps", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn _req -> {200, @driven} end)

    assert {:ok, route} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717})

    assert route.origin == {116.481028, 39.989643}
    assert route.destination == {116.465302, 40.004717}
    assert route.taxi_cost == "21"

    assert [path] = route.paths
    assert path.distance == "12345"
    assert path.duration == "1200"
    # Scalars keep the wire's form — every one of these is a string.
    assert path.strategy == "速度优先"
    assert path.tolls == "5.0"
    assert path.restriction == "0"
    assert path.traffic_lights == "7"
    assert path.toll_distance == "3000"
    # Nothing asked for aggregation, and no `roads` key came back.
    assert path.roads == []

    assert [step] = path.steps
    assert step.road == "阜通东大街"
    assert step.orientation == "西"
    assert step.tolls == "0"
    assert step.toll_distance == "0"
    assert step.toll_road == ""
  end

  test "decodes a step's polyline and its tmcs", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn _req -> {200, @driven} end)

    assert {:ok, %Route{paths: [%{steps: [step]}]}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717})

    assert step.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]

    assert [%Tmc{} = tmc] = step.tmcs
    assert tmc.distance == "100"
    # The traffic status arrives in Chinese and stays there.
    assert tmc.status == "畅通"
    assert tmc.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]
  end

  test "maps the cities and districts a path passes through", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn _req -> {200, @driven} end)

    assert {:ok, %Route{paths: [path]}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717})

    assert [%City{} = city] = path.cities
    assert city.name == "北京市"
    assert city.citycode == "010"
    assert city.adcode == "110000"
    assert [%District{name: "朝阳区", adcode: "110105"}] = city.districts

    assert [%District{name: "朝阳区", adcode: "110105"}] = path.districts
  end

  test "maps the roads `roadaggregation` returns in place of steps", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn _req ->
      {200, @aggregated}
    end)

    assert {:ok, %Route{paths: [path]}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717},
               roadaggregation: true,
               extensions: :all
             )

    # The wire sent no `steps` key, because the flag replaces `steps` with `roads`
    # rather than adding a grouping above them. Mapping only `steps` would answer `[]`
    # and lose the whole route, which is the defect this test pins.
    assert path.steps == []

    assert [%Road{} = first, %Road{} = second] = path.roads
    assert first.road_name == "示例路"
    assert first.road_distance == "1500"
    assert first.traffic_lights == "3"

    # Whatever sits under a road's `steps` is carried verbatim: no source has said
    # what shape this key holds, so it is not mapped into `Amap.Direction.Step`.
    assert first.steps == [%{"instruction" => "沿示例路行驶", "road" => "示例路"}]
    assert second.steps == [%{"instruction" => "沿示例二路行驶", "road" => "示例二路"}]
  end

  test "answers an empty Route when Amap sends no route at all", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn _req ->
      {200, @no_route}
    end)

    assert {:ok, %Route{origin: nil, destination: nil, paths: []}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717})
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} =
             Direction.driving(client, {116.481028, 39.989643}, {116.465302, 40.004717})
  end

  defp expect_driving(server, body, parent) do
    TestServer.expect_once(server, "GET", "/v3/direction/driving", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
