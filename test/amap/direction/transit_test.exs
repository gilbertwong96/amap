defmodule Amap.Direction.TransitTest do
  use ExUnit.Case, async: true

  alias Amap.Direction
  alias Amap.Direction.Transit
  alias Amap.Direction.Transit.Alter
  alias Amap.Direction.Transit.Busline
  alias Amap.Direction.Transit.Plan
  alias Amap.Direction.Transit.Railway
  alias Amap.Direction.Transit.Segment
  alias Amap.Direction.Transit.Space
  alias Amap.Direction.Transit.Stop
  alias Amap.Direction.Transit.Walking
  alias Amap.TestServer

  @planned """
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "route":{"origin":"116.481499,39.990475","destination":"116.465063,39.999538",
    "distance":"7000","taxi_cost":"21",
    "transits":[{"cost":"5.0","duration":"3600","nightflag":"0",
      "walking_distance":"1200",
      "segments":[
        {"walking":{"origin":"116.481499,39.990475","destination":"116.482,39.991",
           "distance":"500","duration":"400",
           "steps":[{"instruction":"沿阜通东大街向西步行500米","road":"阜通东大街",
             "distance":"500","duration":"400",
             "polyline":"116.481247,39.990704;116.481270,39.990726",
             "action":"直行","assistant_action":"","walk_type":"0"}]},
         "bus":{"buslines":[
           {"departure_stop":{"name":"阜通东大街","id":"BV1001","location":"116.481,39.991"},
            "arrival_stop":{"name":"西直门","id":"BV1002","location":"116.355,39.941"},
            "name":"445路(南十里居--地铁望京西站)","id":"BK1001","type":"地铁线路",
            "distance":"6500","duration":"3200",
            "polyline":"116.481247,39.990704;116.481270,39.990726",
            "start_time":"0600","end_time":"2300",
            "station_start_time":"0630","station_end_time":"2200","via_num":"8",
            "via_stops":[{"name":"望京","id":"BV1003","location":"116.47,39.99"},
                         {"name":"三元桥","id":"BV1004","location":"116.45,39.96"}]}]},
         "entrance":{"name":"阜通站A口","location":"116.482,39.991"},
         "exit":{"name":"西直门站B口","location":"116.355,39.941"},
         "railway":{"id":"R1001","time":"1800","name":"京沪线","trip":"G101",
           "distance":"1300000","type":"2011",
           "departure_stop":{"id":"BV2001","name":"北京南","location":"116.378,39.865",
             "adcode":"110106","time":"0800","start":"1"},
           "arrival_stop":{"id":"BV2002","name":"上海虹桥","location":"121.32,31.19",
             "adcode":"310112","time":"1230","end":"1"},
           "via_stop":[{"name":"济南西","id":"BV2003","location":"116.89,36.65",
             "time":"0930","wait":"5"}],
           "alters":[{"id":"A1","name":"备选方案一",
             "spaces":[{"code":"9","cost":"553"},{"code":"10","cost":"553.0"}]}]}}]}]}}
  """

  # The envelope alone: Amap sends this when it found no plan at all.
  @no_route ~s({"status":"1","info":"OK","infocode":"10000","count":"0"})

  @walking_only """
  {"status":"1","info":"OK","infocode":"10000",
   "route":{"transits":[{"duration":"600",
     "segments":[{"walking":{"distance":"800","duration":"600","steps":[]}}]}]}}
  """

  # A leg that starts on the bus: Amap leaves `walking` out entirely, and the segment's
  # field type is `Path.t() | nil`. An all-nil `%Path{}` here would answer the wrong
  # branch of a caller's truthiness check with no error.
  @bus_only """
  {"status":"1","info":"OK","infocode":"10000","count":"1",
   "route":{"transits":[{"distance":"3000",
     "segments":[{"bus":{"buslines":[{"name":"445路","type":"普通公交线路"}]}}]}]}}
  """

  @empty ~s({"status":"1","info":"OK","infocode":"10000","count":"0",) <>
           ~s("route":{"origin":"116.481499,39.990475",) <>
           ~s("destination":"116.465063,39.999538","distance":"0","transits":[]}})

  @refusal ~s({"status":"0","info":"INVALID_USER_KEY","infocode":"10001"})

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

  test "sends the two points and the required city", %{server: server, client: client} do
    parent = self()
    expect_transit(server, @planned, parent)

    assert {:ok, %Transit{}} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010"
             )

    assert_receive {:query, query}
    assert query["origin"] == "116.481499,39.990475"
    assert query["destination"] == "116.465063,39.999538"
    # `city` is the endpoint's one required extra, and it goes in positionally.
    assert query["city"] == "010"
    refute Map.has_key?(query, "cityd")
    refute Map.has_key?(query, "strategy")
    refute Map.has_key?(query, "extensions")
    refute Map.has_key?(query, "nightflag")
  end

  test "sends cityd only for a cross-city plan", %{server: server, client: client} do
    parent = self()
    expect_transit(server, @planned, parent)

    assert {:ok, %Transit{}} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010",
               cityd: "021"
             )

    assert_receive {:query, query}
    assert query["cityd"] == "021"
  end

  test "validates the strategy against this endpoint's own values, which skip 4", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @planned, parent)

    assert {:ok, %Transit{}} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010",
               strategy: 5
             )

    assert_receive {:query, query}
    assert query["strategy"] == "5"

    # Amap documents 0/1/2/3/5 here — there is no 4, unlike driving's range.
    assert_raise ArgumentError, ~r/:strategy must be one of \[0, 1, 2, 3, 5\]/, fn ->
      Direction.transit(
        client,
        {116.481499, 39.990475},
        {116.465063, 39.999538},
        "010",
        strategy: 4
      )
    end
  end

  test "encodes date and time the way the page writes them, and omits both otherwise", %{
    server: server,
    client: client
  } do
    parent = self()
    expect_transit(server, @planned, parent)

    assert {:ok, %Transit{}} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010",
               date: ~D[2014-03-19],
               time: ~T[22:34:00]
             )

    assert_receive {:query, query}
    # The page's examples are unpadded: 2014-3-19 and 22:34, not 2014-03-19.
    assert query["date"] == "2014-3-19"
    assert query["time"] == "22:34"

    # The page says twice: do not send these unless a scheduled departure is wanted.
    expect_transit(server, @planned, parent)

    assert {:ok, %Transit{}} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010"
             )

    assert_receive {:query, query}
    refute Map.has_key?(query, "date")
    refute Map.has_key?(query, "time")
  end

  test "maps this endpoint's remaining options onto the wire", %{server: server, client: client} do
    parent = self()
    expect_transit(server, @planned, parent)

    assert {:ok, %Transit{}} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010",
               extensions: :all,
               nightflag: true
             )

    assert_receive {:query, query}
    assert query["extensions"] == "all"
    assert query["nightflag"] == "1"

    assert_raise ArgumentError, ~r/:extensions must be one of/, fn ->
      Direction.transit(
        client,
        {116.481499, 39.990475},
        {116.465063, 39.999538},
        "010",
        extensions: :everything
      )
    end

    assert_raise ArgumentError, ~r/:nightflag must be a boolean/, fn ->
      Direction.transit(
        client,
        {116.481499, 39.990475},
        {116.465063, 39.999538},
        "010",
        nightflag: 1
      )
    end
  end

  test "refuses an empty city and values that are not the types they claim", %{client: client} do
    assert_raise ArgumentError, ~r/:city must be a non-empty string/, fn ->
      Direction.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "")
    end

    assert_raise ArgumentError, ~r/:date must be a Date/, fn ->
      Direction.transit(
        client,
        {116.481499, 39.990475},
        {116.465063, 39.999538},
        "010",
        date: "2014-03-19"
      )
    end

    assert_raise ArgumentError, ~r/:time must be a Time/, fn ->
      Direction.transit(
        client,
        {116.481499, 39.990475},
        {116.465063, 39.999538},
        "010",
        time: "22:34"
      )
    end
  end

  test "maps the route and its plan", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @planned}
    end)

    assert {:ok, transit} =
             Direction.transit(
               client,
               {116.481499, 39.990475},
               {116.465063, 39.999538},
               "010"
             )

    assert transit.origin == {116.481499, 39.990475}
    assert transit.destination == {116.465063, 39.999538}
    # Scalars keep the wire's form, including the ones that look numeric.
    assert transit.distance == "7000"
    assert transit.taxi_cost == "21"

    assert [%Plan{} = plan] = transit.transits
    assert plan.cost == "5.0"
    assert plan.duration == "3600"
    assert plan.nightflag == "0"
    assert plan.walking_distance == "1200"
  end

  test "maps a segment's walking leg, including its own endpoints", %{
    server: server,
    client: client
  } do
    expect_once_planned(server)

    assert {:ok, %Transit{transits: [%Plan{segments: [segment]}]}} = call_transit(client)

    assert %Segment{} = segment
    assert %Walking{} = walking = segment.walking
    # The leg's own endpoints, which an `Amap.Direction.Path` has no slots for: a walk
    # is between two points on the plan rather than between the route's two ends.
    assert walking.origin == {116.481499, 39.990475}
    assert walking.destination == {116.482, 39.991}
    assert walking.distance == "500"
    assert walking.duration == "400"
    # The leg's steps are the v3 step shape, mapped by the same function a path uses.
    assert [%Amap.Direction.Step{} = step] = walking.steps
    assert step.walk_type == "0"
    assert step.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]
  end

  test "maps the bus lines, their stops and the segment's entrances", %{
    server: server,
    client: client
  } do
    expect_once_planned(server)

    assert {:ok, %Transit{transits: [%Plan{segments: [segment]}]}} = call_transit(client)

    assert [%Busline{} = busline] = segment.bus
    assert busline.name == "445路(南十里居--地铁望京西站)"
    assert busline.type == "地铁线路"

    assert %Stop{name: "阜通东大街", id: "BV1001", location: {116.481, 39.991}} =
             busline.departure_stop

    assert %Stop{name: "西直门", id: "BV1002"} = busline.arrival_stop
    assert busline.via_num == "8"
    # The line's timetables stay strings — 0600 means 06:00 in Amap's own notation.
    assert busline.start_time == "0600"
    assert busline.station_end_time == "2200"
    assert busline.polyline == [{116.481247, 39.990704}, {116.481270, 39.990726}]

    assert [%Stop{name: "望京"}, %Stop{name: "三元桥"}] = busline.via_stops
    assert %Stop{name: "阜通站A口", location: {116.482, 39.991}} = segment.entrance
    assert %Stop{name: "西直门站B口"} = segment.exit
  end

  test "maps a railway leg, including the stops only a train has", %{
    server: server,
    client: client
  } do
    expect_once_planned(server)

    assert {:ok, %Transit{transits: [%Plan{segments: [segment]}]}} = call_transit(client)

    assert %Railway{} = railway = segment.railway
    assert railway.trip == "G101"
    assert railway.name == "京沪线"
    # 2011 is a G 字头 train in Amap's 线路类型 table; the code stays a string.
    assert railway.type == "2011"
    assert railway.time == "1800"
    assert railway.distance == "1300000"

    assert %Stop{name: "北京南", adcode: "110106", start: "1"} = railway.departure_stop
    assert %Stop{name: "上海虹桥", end: "1"} = railway.arrival_stop
    assert [%Stop{name: "济南西", time: "0930", wait: "5"}] = railway.via_stop

    assert [%Alter{id: "A1", name: "备选方案一"} = alter] = railway.alters
    assert [%Space{code: "9", cost: "553"}, %Space{code: "10", cost: "553.0"}] = alter.spaces
  end

  test "leaves a segment's absent parts nil rather than guessing", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @walking_only}
    end)

    assert {:ok, %Transit{transits: [%Plan{segments: [segment]}]}} = call_transit(client)

    assert %Walking{distance: "800", origin: nil, destination: nil} = segment.walking
    assert segment.bus == []
    assert segment.entrance == nil
    assert segment.exit == nil
    assert segment.railway == nil
  end

  test "leaves a bus-only segment's walking leg nil", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @bus_only}
    end)

    assert {:ok, %Transit{transits: [%Plan{segments: [segment]}]}} = call_transit(client)

    # The other half of the pair above: the field's type is `Path.t() | nil`, so a leg
    # Amap did not send a walk for must not arrive as an all-nil struct.
    assert segment.walking == nil
    assert [%Busline{name: "445路"}] = segment.bus
    assert segment.entrance == nil
    assert segment.railway == nil
  end

  test "answers an empty Transit when Amap sends no route at all", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @no_route}
    end)

    assert {:ok, %Transit{origin: nil, destination: nil, transits: []}} = call_transit(client)
  end

  test "answers a route with no transits when Amap found no way to make the trip", %{
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @empty}
    end)

    assert {:ok, %Transit{transits: []}} = call_transit(client)
  end

  test "returns an error rather than raising for a refusal", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @refusal}
    end)

    assert {:error, %Amap.Error{}} = call_transit(client)
  end

  defp call_transit(client) do
    Direction.transit(client, {116.481499, 39.990475}, {116.465063, 39.999538}, "010")
  end

  defp expect_once_planned(server) do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn _req ->
      {200, @planned}
    end)
  end

  defp expect_transit(server, body, parent) do
    TestServer.expect_once(server, "GET", "/v3/direction/transit/integrated", fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, body}
    end)
  end
end
