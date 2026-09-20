defmodule Amap.NewRoute.DrivingTest do
  use ExUnit.Case, async: true

  alias Amap.NewRoute
  alias Amap.NewRoute.City
  alias Amap.NewRoute.Cost
  alias Amap.NewRoute.District
  alias Amap.NewRoute.Navi
  alias Amap.NewRoute.Route
  alias Amap.NewRoute.Tmc
  alias Amap.TestServer

  # The whole answer, with every `show_fields` group **this endpoint's page lists** — v5
  # driving excludes `walk_type`, which only walking and riding document.
  @driven ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
            ~s("route":{"origin":"116.434307,39.90909","destination":"116.434446,39.90816",) <>
            ~s("taxi_cost":"21","paths":[{"distance":"12345","restriction":"0",) <>
            ~s("cost":{"duration":"1200","tolls":"5.0","toll_distance":"3000"},) <>
            ~s("tmcs":{"tmc_status":"畅通","tmc_distance":"100",) <>
            ~s("tmc_polyline":"116.481247,39.990704;116.481270,39.990726"},) <>
            ~s("cities":{"adcode":"110000","citycode":"010","city":"北京市"},) <>
            ~s("district":{"name":"朝阳区","adcode":"110105"},) <>
            ~s("polyline":"116.481247,39.990704;116.481270,39.990726",) <>
            ~s("steps":[{"instruction":"沿阜通东大街向西行驶500米","orientation":"西",) <>
            ~s("road_name":"阜通东大街","step_distance":"500",) <>
            ~s("navi":{"action":"直行","assistant_action":"","walk_type":"0"},) <>
            ~s("cities":[{"adcode":"110000","city":"北京市",) <>
            ~s("citycode":"010","districts":[{"name":"东城区","adcode":"110101"}]}],) <>
            ~s("polyline":"116.481247,39.990704;116.481270,39.990726"}]}]}})

  # What arrives when show_fields was not asked for: base fields only.
  @base ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
          ~s("route":{"origin":"116.434307,39.90909","destination":"116.434446,39.90816",) <>
          ~s("paths":[{"distance":"12345","restriction":"0",) <>
          ~s("steps":[{"instruction":"行驶500米","orientation":"西",) <>
          ~s("road_name":"阜通东大街","step_distance":"500"}]}]}})

  # The envelope alone: Amap sends this when it found no route at all.
  @no_route ~s({"status":"1","info":"OK","infocode":"10000","count":"0"})

  # `tmcs` in the two shapes the tolerant reader promises to read besides the bare object
  # the page prints: a one-element list of `tmc`-wrapped objects, and the wrapper alone.
  @tmcs_list ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
               ~s("route":{"paths":[{"distance":"3200",) <>
               ~s("tmcs":[{"tmc":{"tmc_status":"缓行","tmc_distance":"80",) <>
               ~s("tmc_polyline":"116.481247,39.990704;116.481270,39.990726"}}]}]}})

  @tmcs_wrapped ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
                  ~s("route":{"paths":[{"distance":"3200",) <>
                  ~s("tmcs":{"tmc":{"tmc_status":"拥堵","tmc_distance":"90",) <>
                  ~s("tmc_polyline":"116.481247,39.990704;116.481270,39.990726"}}}]}})

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
    expect_driving(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert_receive {:params, params}
    assert params["origin"] == "116.434307,39.90909"
    assert params["destination"] == "116.434446,39.90816"
    refute Map.has_key?(params, "strategy")
    refute Map.has_key?(params, "show_fields")
    refute Map.has_key?(params, "plate")
  end

  test "sends the POI ids under the names this page documents", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               origin_id: "B000A7BD6C",
               destination_id: "B000A7BD6D",
               destination_type: "190100"
             )

    assert_receive {:params, params}
    # Underscored here, as on v3's walking endpoint — unlike v3's driving, which
    # spells the same two parameters `originid`/`destinationid`.
    assert params["origin_id"] == "B000A7BD6C"
    assert params["destination_id"] == "B000A7BD6D"
    assert params["destination_type"] == "190100"
    refute Map.has_key?(params, "originid")
  end

  test "validates the strategy against this page's enum, which is not v3's", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               strategy: 32
             )

    assert_receive {:params, params}
    assert params["strategy"] == "32"

    # 31 and 10 are unassigned here, and 10 is v3's own value — the two enums only
    # look alike.
    for strategy <- [31, 10, 46] do
      assert_raise ArgumentError, ~r/:strategy must be one of/, fn ->
        NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
          strategy: strategy
        )
      end
    end
  end

  test "sends show_fields comma-joined and refuses a group this page does not list", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @driven, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               show_fields: [:cost, :navi]
             )

    assert_receive {:params, params}
    assert params["show_fields"] == "cost,navi"

    assert_raise ArgumentError, ~r/:show_fields must be a subset of/, fn ->
      NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
        show_fields: [:cost, :typo]
      )
    end
  end

  test "sends the plate whole, as one parameter", %{server: server, client: client} do
    parent = self()
    expect_driving(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               plate: "京AHA322"
             )

    assert_receive {:params, params}
    assert params["plate"] == "京AHA322"
    refute Map.has_key?(params, "province")
    refute Map.has_key?(params, "number")
  end

  test "maps the cartype and names the ferry after the intent", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               cartype: :hybrid,
               ferry: :avoid
             )

    assert_receive {:params, params}
    assert params["cartype"] == "2"
    # The wire's 0 means *take* the ferry, so the option says which way it means.
    assert params["ferry"] == "1"

    assert_raise ArgumentError, ~r/:cartype must be one of/, fn ->
      NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816}, cartype: :steam)
    end
  end

  test "encodes waypoints as one semicolon-separated list and caps them at 16", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @base, parent)

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               waypoints: [{116.4, 39.9}, {116.5, 39.8}]
             )

    assert_receive {:params, params}
    assert params["waypoints"] == "116.4,39.9;116.5,39.8"

    seventeen = for n <- 1..17, do: {116.0 + n, 39.0 + n}

    assert_raise ArgumentError, ~r/:waypoints must be at most 16 coordinate pairs/, fn ->
      NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
        waypoints: seventeen
      )
    end
  end

  test "encodes an avoid-region longitude first, and caps it like v3's page does", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_driving(server, @base, parent)

    ring = [{116.4, 39.9}, {116.5, 39.9}, {116.5, 39.8}, {116.4, 39.8}]

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               avoidpolygons: [ring]
             )

    assert_receive {:params, params}

    # 经度在前，纬度在后 — `Amap.Param.polygon_lon_first/1`, never `Amap.Param.polygon/1`.
    assert params["avoidpolygons"] == "116.4,39.9;116.5,39.9;116.5,39.8;116.4,39.8"

    ring_of_17 = for n <- 1..17, do: {116.0 + n / 100, 39.0 + n / 100}

    assert_raise ArgumentError, ~r/:avoidpolygons ring must be at most 16 vertices/, fn ->
      NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
        avoidpolygons: [ring_of_17]
      )
    end
  end

  test "sends the parameters in a form body on POST, and still signs them", %{server: server} do
    parent = self()

    # A private key, so the `sig` assertion below can fail: without one no call is
    # signed, and the assertion would pass under either wiring.
    client =
      Amap.new(
        key: "test-key",
        private_key: "secret",
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    expect_driving(server, @base, parent, "POST")

    assert {:ok, %Route{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816},
               method: :post
             )

    assert_receive {:params, body_params}
    assert body_params["origin"] == "116.434307,39.90909"
    # Signing follows the family, not the verb.
    assert Map.has_key?(body_params, "sig")

    assert_receive {:query, query}
    # The parameters travel in the body; the query string carries none of them.
    refute query =~ "origin="

    assert_raise ArgumentError, ~r/:method must be one of/, fn ->
      NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816}, method: :put)
    end
  end

  test "maps the route, its paths and the show_fields groups", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req -> {200, @driven} end)

    assert {:ok, route} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert route.origin == {116.434307, 39.90909}
    assert route.destination == {116.434446, 39.90816}
    assert route.taxi_cost == "21"

    assert [path] = route.paths
    assert path.distance == "12345"
    assert path.restriction == "0"

    assert %Cost{} = path.cost
    assert path.cost.duration == "1200"
    assert path.cost.tolls == "5.0"
    assert path.cost.toll_distance == "3000"

    assert [%Tmc{} = tmc] = path.tmcs
    assert tmc.tmc_status == "畅通"
    assert tmc.tmc_distance == "100"
    assert tmc.tmc_polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]

    assert %City{adcode: "110000", citycode: "010", city: "北京市"} = path.cities
    assert %District{name: "朝阳区", adcode: "110105"} = path.district

    assert path.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]

    assert [step] = path.steps
    assert step.instruction == "沿阜通东大街向西行驶500米"
    assert step.orientation == "西"
    # The v5 rename: v3 calls these `road` and `distance`.
    assert step.road_name == "阜通东大街"
    assert step.step_distance == "500"

    # `walk_type` arrives inside `navi` on the endpoints that return it — the live
    # run saw that on `/v5/direction/walking`. Driving's own answer carries none, so
    # this payload stands in for the shape the mapper reads.
    assert %Navi{action: "直行", assistant_action: "", walk_type: "0"} = step.navi
    assert step.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]

    # The key's home is wire evidence — the live run's step keys were `["cost", "tmcs",
    # "navi", "cities", "polyline"]` while the path carried `cost` alone — and the third
    # run printed what it holds there: a list, not the single object v3's `cities` is.
    assert [%City{adcode: "110000", citycode: "010", city: "北京市"} = city] = step.cities
    assert [%District{name: "东城区", adcode: "110101"}] = city.districts
  end

  test "reads a step's cities as the list the wire sends, and nil for any other shape", %{
    server: server,
    client: client
  } do
    steps =
      ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
        ~s("route":{"origin":"116.434307,39.90909","destination":"116.434446,39.90816",) <>
        ~s("paths":[{"distance":"12345","steps":[) <>
        ~s({"instruction":"list",) <>
        ~s("cities":[{"adcode":"110000","city":"北京市",) <>
        ~s("districts":[{"name":"东城区","adcode":"110101"}]},) <>
        ~s({"adcode":"110100"}]},) <>
        ~s({"instruction":"object","cities":{"adcode":"110000","city":"北京市"}},) <>
        ~s({"instruction":"string","cities":"北京市"},) <>
        ~s({"instruction":"absent"}]}]}})

    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req ->
      {200, steps}
    end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert [list, object, other, absent] = path.steps

    assert [
             %City{adcode: "110000", city: "北京市"} = city,
             %City{adcode: "110100", city: nil}
           ] = list.cities

    assert [%District{name: "东城区", adcode: "110101"}] = city.districts
    # The object the v3 page documents is not what this endpoint sends, and reading it
    # would guess which of the two shapes Amap meant, so it answers `nil`.
    assert object.cities == nil
    assert other.cities == nil
    assert absent.cities == nil
  end

  test "drops the districts it cannot read instead of raising", %{server: server, client: client} do
    steps =
      ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
        ~s("route":{"origin":"116.434307,39.90909","destination":"116.434446,39.90816",) <>
        ~s("paths":[{"distance":"12345","steps":[) <>
        ~s({"instruction":"mixed",) <>
        ~s("cities":[{"adcode":"110000","city":"北京市",) <>
        ~s("districts":[{"name":"东城区","adcode":"110101"},"东城区"]}]},) <>
        ~s({"instruction":"not-a-list",) <>
        ~s("cities":[{"adcode":"110100","city":"北京城区","districts":"东城区"}]}]}]}})

    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req ->
      {200, steps}
    end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert [mixed, not_a_list] = path.steps

    # A district the mapper cannot read loses itself and the city around it survives,
    # which is the totality `to_city/1` promises for every shape no source has shown.
    assert [%City{adcode: "110000"} = city] = mixed.cities
    assert [%District{name: "东城区", adcode: "110101"}] = city.districts

    assert [%City{adcode: "110100", districts: []}] = not_a_list.cities
  end

  test "leaves the optional groups empty when show_fields was not asked for", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req -> {200, @base} end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    # One value is nil; a collection is empty — the same split the rest of the batch
    # keeps.
    assert path.cost == nil
    assert path.tmcs == []
    assert path.navi == nil
    assert path.cities == nil
    assert path.district == nil
    assert path.polyline == nil

    assert [step] = path.steps
    assert step.navi == nil
    assert step.tmcs == []
    assert step.cities == nil
    assert step.polyline == nil
  end

  test "drops a path the wire sent as a literal null", %{server: server, client: client} do
    with_null =
      ~s({"status":"1","info":"OK","infocode":"10000","count":"1",) <>
        ~s("route":{"origin":"116.434307,39.90909","destination":"116.434446,39.90816",) <>
        ~s("paths":[null,{"distance":"12345","restriction":"0"}]}})

    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req ->
      {200, with_null}
    end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    # `Route.paths` is a list of paths: a null entry is dropped rather than built into
    # an all-nil `%Amap.NewRoute.Path{}`, which is what the mapper would have made of it.
    assert path.distance == "12345"
  end

  test "answers an empty Route when Amap sends no route at all", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req ->
      {200, @no_route}
    end)

    assert {:ok, %Route{origin: nil, destination: nil, paths: []}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})
  end

  # The page prints `tmcs` as a bare object, but its own rules do not promise that, so
  # the reader takes the two wrapped shapes as well. Only the bare one was exercised,
  # which is how the list branch came to call `to_tmc/1` where it needed `to_tmcs/1`.
  test "reads a tmcs group wrapped in a one-element list", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req ->
      {200, @tmcs_list}
    end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert [%Tmc{} = tmc] = path.tmcs
    assert tmc.tmc_status == "缓行"
    assert tmc.tmc_distance == "80"
    assert tmc.tmc_polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]
  end

  test "reads a tmcs group wrapped in tmc alone", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v5/direction/driving", fn _req ->
      {200, @tmcs_wrapped}
    end)

    assert {:ok, %Route{paths: [path]}} =
             NewRoute.driving(client, {116.434307, 39.90909}, {116.434446, 39.90816})

    assert [%Tmc{} = tmc] = path.tmcs
    assert tmc.tmc_status == "拥堵"
    assert tmc.tmc_distance == "90"
    assert tmc.tmc_polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]
  end

  defp expect_driving(server, body, parent, method \\ "GET") do
    TestServer.expect_once(server, method, "/v5/direction/driving", fn req ->
      params =
        case method do
          "POST" -> URI.decode_query(req.body)
          "GET" -> URI.decode_query(req.query)
        end

      send(parent, {:params, params})
      send(parent, {:query, req.query})
      {200, body}
    end)
  end
end
