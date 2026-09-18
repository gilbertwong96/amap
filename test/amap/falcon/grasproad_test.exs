defmodule Amap.Falcon.GrasproadTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Grasproad
  alias Amap.Falcon.Grasproad.Degraded
  alias Amap.Falcon.Grasproad.Point
  alias Amap.Falcon.Grasproad.Result
  alias Amap.Falcon.Grasproad.RoadResult
  alias Amap.Falcon.Grasproad.RoadTrack
  alias Amap.Falcon.Grasproad.Track
  alias Amap.TestServer

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

  defp arm_query(server, path, body) do
    parent = self()

    TestServer.expect_once(server, "GET", path, fn req ->
      send(parent, {:query, URI.decode_query(req.query)})
      {200, body}
    end)

    parent
  end

  @one_track ~s({"errcode":10000,"errmsg":"OK","data":{"counts":1,"tracks":[{"trid":20,"trname":"早晨","distance":1200,"time":60000,"counts":5,"points":[{"location":"114.1589,22.2799","locatetime":1789703117430,"speed":40,"direction":120,"accuracy":20,"height":39,"props":{"driver":"abc"}}]}],"degradedParams":{"threshold":0}}})

  describe "trsearch/4" do
    test "reads one trace by trid", %{server: server, client: client} do
      arm_query(server, "/v1/track/terminal/trsearch", @one_track)

      assert {:ok,
              %Result{counts: 1, tracks: [track], degraded_params: %Degraded{threshold: false}}} =
               Grasproad.trsearch(client, 1, 456, trid: 20)

      assert %Track{trid: 20, trname: "早晨", distance: 1200, time: 60_000, counts: 5} = track

      assert [%Point{location: {114.1589, 22.2799}, speed: 40, props: %{"driver" => "abc"}}] =
               track.points

      assert_receive {:query, query}
      assert query["sid"] == "1"
      assert query["tid"] == "456"
      assert query["trid"] == "20"
      refute Map.has_key?(query, "starttime")
    end

    test "takes a window as DateTimes or milliseconds", %{server: server, client: client} do
      arm_query(server, "/v1/track/terminal/trsearch", @one_track)

      # A window that ends in the future would be rejected, so this is a past one.
      start = DateTime.add(DateTime.utc_now(), -7200, :second)
      finish = DateTime.add(start, 3600, :second)

      Grasproad.trsearch(client, 1, 456,
        starttime: start,
        endtime: finish,
        correction: [mapmatch: true]
      )

      assert_receive {:query, query}
      assert query["starttime"] == Integer.to_string(DateTime.to_unix(start, :millisecond))
      assert query["endtime"] == Integer.to_string(DateTime.to_unix(finish, :millisecond))
      assert query["correction"] == "denoise=1,mapmatch=1,attribute=0,threshold=0,mode=driving"
    end

    test "takes a window in milliseconds too", %{server: server, client: client} do
      arm_query(server, "/v1/track/terminal/trsearch", @one_track)

      now = System.system_time(:millisecond)
      Grasproad.trsearch(client, 1, 456, starttime: now - 600_000, endtime: now - 60_000)

      assert_receive {:query, query}
      assert query["starttime"] == Integer.to_string(now - 600_000)
      assert query["endtime"] == Integer.to_string(now - 60_000)
    end

    test "maps the optional query options", %{server: server, client: client} do
      arm_query(server, "/v1/track/terminal/trsearch", @one_track)

      Grasproad.trsearch(client, 1, 456,
        trid: 20,
        recoup: true,
        gap: 1000,
        ispoints: false,
        page: 2,
        pagesize: 100
      )

      assert_receive {:query, query}
      assert query["recoup"] == "1"
      assert query["gap"] == "1000"
      assert query["ispoints"] == "0"
      assert query["page"] == "2"
      assert query["pagesize"] == "100"
    end

    test "a point may arrive with nothing but a location, since correction drops fields", %{
      server: server,
      client: client
    } do
      arm_query(
        server,
        "/v1/track/terminal/trsearch",
        ~s({"errcode":10000,"errmsg":"OK","data":{"counts":1,"tracks":[{"trid":20,"counts":1,"points":[{"location":"114.1589,22.2799"}]}]}})
      )

      assert {:ok, %Result{tracks: [%Track{points: [point]}]}} =
               Grasproad.trsearch(client, 1, 456, trid: 20)

      assert %Point{location: {114.1589, 22.2799}, locatetime: nil, speed: nil} = point
    end

    test "rejects a call that does not say what to read", %{client: client} do
      assert_raise ArgumentError, ~r/needs either :trid or both :starttime and :endtime/, fn ->
        Grasproad.trsearch(client, 1, 456, [])
      end
    end

    test "rejects a window longer than a day", %{client: client} do
      now = DateTime.utc_now()

      # 100_000 seconds back is a little over 27 hours; the boundary itself,
      # exactly 24 hours, is allowed.
      assert_raise ArgumentError, ~r/may not exceed 24 hours/, fn ->
        Grasproad.trsearch(client, 1, 456,
          starttime: DateTime.add(now, -100_000, :second),
          endtime: DateTime.add(now, -3600, :second)
        )
      end
    end

    test "rejects options outside Amap's ranges", %{client: client} do
      assert_raise ArgumentError, ~r/:gap must be between 50 and 10000/, fn ->
        Grasproad.trsearch(client, 1, 456, trid: 20, gap: 10)
      end

      assert_raise ArgumentError, ~r/:page must be between 1 and 100/, fn ->
        Grasproad.trsearch(client, 1, 456, trid: 20, page: 101)
      end

      assert_raise ArgumentError, ~r/:pagesize must be between 1 and 999/, fn ->
        Grasproad.trsearch(client, 1, 456, trid: 20, pagesize: 1000)
      end

      assert_raise ArgumentError, ~r/expected a boolean, got: "yes"/, fn ->
        Grasproad.trsearch(client, 1, 456, trid: 20, recoup: "yes")
      end
    end
  end

  describe "roaddata/2" do
    @road_result ~s({"errcode":10000,"errmsg":"OK","data":{"counts":1,"distance":1200,"tracks":[{"roadName":"皇后大道中","speedLimit":50,"roadClass":44000,"roadClassName":"主要道路","isToll":0,"isOwnership":1,"points":[{"location":"114.1589,22.2799","locatetime":"1789703117430"}]}]}})

    test "reads road attributes for a trace", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "POST", "/v1/track/terminal/roaddata", fn req ->
        send(parent, {:body, URI.decode_query(req.body)})
        {200, @road_result}
      end)

      assert {:ok, %RoadResult{counts: 1, distance: 1200, tracks: [track]}} =
               Grasproad.roaddata(client,
                 sid: 1,
                 tid: 456,
                 trid: 20,
                 car_type: :truck,
                 threshold: 100
               )

      # camelCase on the wire, snake_case in the struct.
      assert %RoadTrack{
               road_name: "皇后大道中",
               speed_limit: 50,
               road_class: 44_000,
               road_class_name: "主要道路",
               is_toll: false,
               is_ownership: true
             } = track

      assert [%Point{location: {114.1589, 22.2799}}] = track.points

      assert_receive {:body, body}
      assert body["carType"] == "1"
      assert body["threshold"] == "100"
      assert body["trid"] == "20"
    end

    test "takes points instead of a trace", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "POST", "/v1/track/terminal/roaddata", fn req ->
        send(parent, {:body, URI.decode_query(req.body)})
        {200, @road_result}
      end)

      points =
        for n <- 0..4,
            do: %{location: {114.158 + n / 1000, 22.279}, locatetime: 1_789_703_117_430}

      assert {:ok, %RoadResult{}} = Grasproad.roaddata(client, points: points, car_type: :bus)

      assert_receive {:body, body}
      refute Map.has_key?(body, "trid")
      assert body["carType"] == "0"
      assert [first | _] = JSON.decode!(body["points"])
      assert first["location"] == "114.158,22.279"
    end

    test "insists on one way of saying what to read", %{client: client} do
      assert_raise ArgumentError, ~r/needs either :points, or all of :sid, :tid and :trid/, fn ->
        Grasproad.roaddata(client, [])
      end

      assert_raise ArgumentError, ~r/not both/, fn ->
        Grasproad.roaddata(client, sid: 1, tid: 2, trid: 3, points: List.duplicate(%{}, 5))
      end
    end

    test "validates the point count, the car type and the threshold", %{client: client} do
      assert_raise ArgumentError, ~r/:points must be between 5 and 500, got: 4/, fn ->
        Grasproad.roaddata(client, points: List.duplicate(%{location: {1, 2}, locatetime: 1}, 4))
      end

      assert_raise ArgumentError, ~r/:car_type must be :bus or :truck, got: :bike/, fn ->
        Grasproad.roaddata(client, sid: 1, tid: 2, trid: 3, car_type: :bike)
      end

      assert_raise ArgumentError, ~r/:threshold must be between 0 and 99999/, fn ->
        Grasproad.roaddata(client, sid: 1, tid: 2, trid: 3, threshold: 100_000)
      end
    end
  end
end
