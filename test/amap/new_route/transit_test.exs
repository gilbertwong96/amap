defmodule Amap.NewRoute.TransitTest do
  use ExUnit.Case, async: true

  alias Amap.Direction.Path
  alias Amap.Direction.Step, as: V3Step
  alias Amap.Direction.Transit.Busline
  alias Amap.Direction.Transit.Railway
  alias Amap.Direction.Transit.Stop
  alias Amap.NewRoute
  alias Amap.NewRoute.Transit
  alias Amap.NewRoute.Transit.Cost, as: TransitCost
  alias Amap.NewRoute.Transit.Plan
  alias Amap.NewRoute.Transit.Segment
  alias Amap.NewRoute.Transit.Taxi
  alias Amap.TestServer

  @transit_path "/v5/direction/transit/integrated"

  # The whole answer: a plan that walks, rides a bus, hails a taxi and takes a train,
  # with both halves of the cost group — `taxi_fee` on the route, `transit_fee` under
  # each segment. `walking`, `bus` and `railway` arrive in v3's shape, 参考 v3 老接口.
  @planned """
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "route":{"origin":"116.481499,39.990475","destination":"116.465063,39.999538",
    "cost":{"duration":"3600","taxi_fee":"21"},
    "transits":[{"distance":"7000","nightflag":"0",
      "segments":[
        {"walking":{"origin":"116.481499,39.990475","destination":"116.482,39.991",
           "distance":"500","duration":"400",
           "steps":[{"instruction":"沿阜通东大街向西步行500米","road":"阜通东大街",
             "distance":"500","duration":"400",
             "polyline":"116.481247,39.990704;116.481270,39.990726",
             "action":"直行","assistant_action":"","walk_type":"0"}]}},
        {"bus":{"buslines":[
           {"departure_stop":{"name":"阜通东大街","id":"BV1001","location":"116.481,39.991"},
            "arrival_stop":{"name":"西直门","id":"BV1002","location":"116.355,39.941"},
            "name":"445路(南十里居--地铁望京西站)","id":"BK1001","type":"地铁线路",
            "distance":"6500","duration":"3200",
            "polyline":"116.481247,39.990704;116.481270,39.990726",
            "start_time":"0600","end_time":"2300",
            "station_start_time":"0630","station_end_time":"2200","via_num":"8",
            "via_stops":[{"name":"望京","id":"BV1003","location":"116.47,39.99"}]}]},
         "cost":{"transit_fee":"5.0"}},
        {"taxi":{"price":"21","drivetime":"1200","distance":"3200",
           "polyline":"116.465063,39.999538;116.481499,39.990475",
           "startpoint":"116.465063,39.999538","startname":"望京西站",
           "endpoint":"116.481499,39.990475","endname":"阜通东大街"},
         "cost":{"transit_fee":"21.0"}},
        {"railway":{"id":"R1001","time":"1800","name":"京沪线","trip":"G101",
           "distance":"1300000","type":"2011",
           "departure_stop":{"id":"BV2001","name":"北京南","location":"116.378,39.865",
             "adcode":"110106","time":"0800","start":"1"},
           "arrival_stop":{"id":"BV2002","name":"上海虹桥","location":"121.32,31.19",
             "adcode":"310112","time":"1230","end":"1"}}}]}]}}
  """

  # Base fields only: what arrives when show_fields was not asked for.
  @base """
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "route":{"origin":"116.481499,39.990475","destination":"116.465063,39.999538",
    "transits":[{"distance":"7000",
      "segments":[{"walking":{"distance":"500","duration":"400","steps":[]}}]}]}}
  """

  # A leg that starts on the bus: Amap leaves `walking` out, and the segment's field
  # type is `Path.t() | nil` there too.
  @bus_only """
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "route":{"transits":[{"distance":"3000",
     "segments":[{"bus":{"buslines":[{"name":"445路","type":"普通公交线路"}]}}]}]}}
  """

  # The envelope alone: Amap sends this when it found no plan at all.
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

  test "sends the two points and the required city, nothing else", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")

    assert_receive {:params, params}
    assert params["origin"] == "116.481499,39.990475"
    assert params["destination"] == "116.465063,39.999538"
    # city1 is required and positional — the page marks it 必填.
    assert params["city1"] == "010"
    refute Map.has_key?(params, "city2")
    refute Map.has_key?(params, "originpoi")
    refute Map.has_key?(params, "destinationpoi")
    refute Map.has_key?(params, "strategy")
    refute Map.has_key?(params, "nightflag")
    refute Map.has_key?(params, "date")
    refute Map.has_key?(params, "time")
    refute Map.has_key?(params, "show_fields")
  end

  test "sends city2 only when given", %{server: server, client: client} do
    parent = self()
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
               city2: "021"
             )

    assert_receive {:params, params}
    assert params["city2"] == "021"

    # Absence is asserted against a request of its own, not against the one that
    # just sent the value.
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")

    assert_receive {:params, params}
    refute Map.has_key?(params, "city2")
  end

  test "takes strategy 0–8, and mode 6 needs both station POIs", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
               strategy: 6,
               originpoi: "B000A7BD6C",
               destinationpoi: "B000A7BD6D"
             )

    assert_receive {:params, params}
    assert params["strategy"] == "6"
    assert params["originpoi"] == "B000A7BD6C"
    assert params["destinationpoi"] == "B000A7BD6D"

    # 9 is off this page's enum; its 6 means 地铁图模式, where driving's digits mean
    # other things entirely.
    for strategy <- [9, -1] do
      assert_raise ArgumentError, ~r/:strategy must be one of/, fn ->
        NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
          strategy: strategy
        )
      end
    end

    # Mode 6 names a station instead of a coordinate, so it has nothing to fall back
    # on when the pair is incomplete — and each message names the POI that is missing.
    assert_raise ArgumentError, ~r/地铁图模式 requires/, fn ->
      NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
        strategy: 6
      )
    end

    assert_raise ArgumentError, ~r/:originpoi is missing/, fn ->
      NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
        strategy: 6,
        destinationpoi: "B000A7BD6D"
      )
    end

    assert_raise ArgumentError, ~r/:destinationpoi is missing/, fn ->
      NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
        strategy: 6,
        originpoi: "B000A7BD6C"
      )
    end

    # A lone POI is a call-site mistake in any mode: the pair travels whole or not at
    # all, because the id overrides the coordinate it sits beside.
    for one <- [[originpoi: "B000A7BD6C"], [destinationpoi: "B000A7BD6D"]] do
      assert_raise ArgumentError, ~r/:originpoi and :destinationpoi must be given together/, fn ->
        NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010", one)
      end
    end
  end

  test "spells the alternative-route parameter AlternativeRoute, capital A", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
               alternative_route: 10
             )

    assert_receive {:params, params}
    # This page's own spelling: capital A, against every other v5 endpoint's lowercase
    # `alternative_route`, and 1–10 where theirs is 1–3. Lowercase would arrive as a
    # parameter Amap does not document and would answer it with one route.
    assert params["AlternativeRoute"] == "10"
    refute Map.has_key?(params, "alternative_route")

    for count <- [0, 11] do
      assert_raise ArgumentError, ~r/:alternative_route must be one of/, fn ->
        NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
          alternative_route: count
        )
      end
    end

    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")

    assert_receive {:params, params}
    refute Map.has_key?(params, "AlternativeRoute")
  end

  test "sends show_fields comma-joined and refuses a group this page does not list", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
               show_fields: [:cost, :navi, :walk_type, :polyline]
             )

    assert_receive {:params, params}
    # This page's four groups, all of them, in the order given.
    assert params["show_fields"] == "cost,navi,walk_type,polyline"

    assert_raise ArgumentError, ~r/:show_fields must be a subset of/, fn ->
      NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
        show_fields: [:tmcs]
      )
    end
  end

  test "sends nightflag as 1 and writes the departure as the page does", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @base, parent)

    assert {:ok, %Transit{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010",
               ad1: "110000",
               ad2: "310000",
               nightflag: true,
               date: ~D[2014-03-19],
               time: ~T[22:34:00]
             )

    assert_receive {:params, params}
    assert params["ad1"] == "110000"
    assert params["ad2"] == "310000"
    assert params["nightflag"] == "1"
    # Unpadded, the way the page's own examples write them.
    assert params["date"] == "2014-3-19"
    assert params["time"] == "22:34"
  end

  test "maps the plans, the v3 legs and v5's own taxi", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", @transit_path, fn _req -> {200, @planned} end)

    assert {:ok, transit} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")

    assert transit.origin == {116.481499, 39.990475}
    assert transit.destination == {116.465063, 39.999538}
    # The route-level half of the cost group: `taxi_fee` appears only here, and the
    # segment-level `transit_fee` stays nil rather than being copied up.
    assert %TransitCost{duration: "3600", taxi_fee: "21", transit_fee: nil} = transit.cost

    assert [%Plan{} = plan] = transit.transits
    assert plan.distance == "7000"
    assert plan.nightflag == "0"

    assert [%Segment{} = walk, %Segment{} = ride, %Segment{} = hail, %Segment{} = train] =
             plan.segments

    # v5 documents a segment's `walking` as 参考 v3 老接口, so it is v3's Path and v3's
    # step field names — `road`, `distance` — not the v5 renames.
    assert %Path{distance: "500", duration: "400"} = walk.walking
    assert [%V3Step{road: "阜通东大街", walk_type: "0"}] = walk.walking.steps

    assert walk.walking.steps |> hd() |> Map.fetch!(:polyline) ==
             [{116.481247, 39.990704}, {116.481270, 39.990726}]

    assert [%Busline{} = line] = ride.bus
    assert line.name == "445路(南十里居--地铁望京西站)"
    assert line.type == "地铁线路"
    assert line.via_num == "8"

    assert %Stop{name: "阜通东大街", id: "BV1001", location: {116.481, 39.991}} =
             line.departure_stop

    assert [%Stop{name: "望京", id: "BV1003"}] = line.via_stops
    assert line.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]

    # v5's own leg, which v3 has no struct for.
    assert %Taxi{
             price: "21",
             drivetime: "1200",
             distance: "3200",
             startpoint: "116.465063,39.999538",
             startname: "望京西站",
             endpoint: "116.481499,39.990475",
             endname: "阜通东大街"
           } = hail.taxi

    assert hail.taxi.polyline == [{116.465063, 39.999538}, {116.481499, 39.990475}]

    # The segment-level half: `transit_fee` appears only here, and the route-level
    # `taxi_fee` stays nil.
    assert %TransitCost{transit_fee: "5.0", taxi_fee: nil} = ride.cost
    assert %TransitCost{transit_fee: "21.0", taxi_fee: nil} = hail.cost

    assert %Railway{name: "京沪线", trip: "G101", type: "2011"} = train.railway
    assert %Stop{name: "北京南", adcode: "110106", start: "1"} = train.railway.departure_stop
    # `via_stop` and `alters` are only ever sent when a call asks for extensions, which
    # this page does not document.
    assert train.railway.via_stop == []
    assert train.railway.alters == []
  end

  test "leaves the groups empty when show_fields was not asked for", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", @transit_path, fn _req -> {200, @base} end)

    assert {:ok, transit} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")

    assert transit.cost == nil

    assert [%Plan{nightflag: nil, segments: [%Segment{} = segment]}] = transit.transits
    assert %Path{} = segment.walking
    assert segment.cost == nil
    assert segment.taxi == nil
    assert segment.railway == nil
    # A collection is empty; a single value is nil — the same split the rest of the
    # batch keeps.
    assert segment.bus == []
  end

  test "leaves a bus-only segment's walking leg nil", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", @transit_path, fn _req -> {200, @bus_only} end)

    assert {:ok, transit} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")

    assert [%Plan{segments: [%Segment{} = segment]}] = transit.transits
    # `walking` is `Path.t() | nil`: a leg Amap sent no walk for stays nil rather than
    # arriving as an all-nil struct a truthiness check would accept.
    assert segment.walking == nil
    assert [%Busline{name: "445路"}] = segment.bus
    assert segment.cost == nil
  end

  test "answers an empty Transit when Amap sends no route at all", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", @transit_path, fn _req -> {200, @no_route} end)

    assert {:ok, %Transit{origin: nil, destination: nil, cost: nil, transits: []}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    refusal = ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

    TestServer.expect_once(server, "GET", @transit_path, fn _req -> {200, refusal} end)

    assert {:error, %Amap.Error{}} =
             NewRoute.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")
  end

  defp expect_transit(server, body, parent) do
    TestServer.expect_once(server, "GET", @transit_path, fn req ->
      send(parent, {:params, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
