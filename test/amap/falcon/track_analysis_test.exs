defmodule Amap.Falcon.TrackAnalysisTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.TrackAnalysis
  alias Amap.Falcon.TrackAnalysis.DrivingBehaviour
  alias Amap.Falcon.TrackAnalysis.Event
  alias Amap.Falcon.TrackAnalysis.Section
  alias Amap.Falcon.TrackAnalysis.StayPoint
  alias Amap.Falcon.TrackAnalysis.StayPoints
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

  defp arm(server, path, body) do
    parent = self()

    TestServer.expect_once(server, "GET", path, fn req ->
      send(parent, {:params, URI.decode_query(req.query)})
      {200, body}
    end)

    parent
  end

  @behaviour_body ~s({"errcode":10000,"errmsg":"OK","data":{"distance":12000,"duration":900000,"aveSpeed":48,"maxSpeed":96,"harshAccelerationCount":1,"harshDecelerationCount":0,"harshSteeringCount":1,"harshAcceleration":{"points":[{"location":"114.1589,22.2799","locateTime":1789703117430,"acceleration":3.2,"initialSpeed":20,"endSpeed":45}]},"harshDeceleration":{"points":[]},"harshSteering":{"points":[{"location":"114.16,22.28","locateTime":1789703118430,"centripetalAcc":2.5,"speed":60}]},"speedLimit":{"points":[{"location":"114.17,22.29","locateTime":1789703119430,"speed":110,"speedLimit":80}]}}})

  describe "driving_behavior/5" do
    test "sends the ids, and camelCase options only when given", %{server: server, client: client} do
      arm(server, "/v1/track/analysis/drivingbehavior", @behaviour_body)

      assert {:ok, %DrivingBehaviour{}} = TrackAnalysis.driving_behavior(client, 1, 456, 20)

      assert_receive {:params, params}
      assert params["sid"] == "1"
      assert params["tid"] == "456"
      assert params["trid"] == "20"
      refute Map.has_key?(params, "startTime")
      refute Map.has_key?(params, "speedLimitThres")
    end

    test "sends a window and the thresholds, camelCased", %{server: server, client: client} do
      arm(server, "/v1/track/analysis/drivingbehavior", @behaviour_body)

      start = DateTime.add(DateTime.utc_now(), -3600, :second)

      TrackAnalysis.driving_behavior(client, 1, 456, 20,
        start_time: start,
        end_time: 1_789_703_117_430,
        acceleration_thres: 2.5,
        speed_limit_thres: 80
      )

      assert_receive {:params, params}
      assert params["startTime"] == Integer.to_string(DateTime.to_unix(start, :millisecond))
      assert params["endTime"] == "1789703117430"
      assert params["accelerationThres"] == "2.5"
      assert params["speedLimitThres"] == "80"
    end

    test "maps the counts and the four sections", %{server: server, client: client} do
      arm(server, "/v1/track/analysis/drivingbehavior", @behaviour_body)

      assert {:ok, behaviour} = TrackAnalysis.driving_behavior(client, 1, 456, 20)

      assert %DrivingBehaviour{
               distance: 12_000,
               duration: 900_000,
               ave_speed: 48,
               max_speed: 96,
               harsh_acceleration_count: 1,
               harsh_deceleration_count: 0,
               harsh_steering_count: 1
             } = behaviour

      assert %Section{points: [acceleration]} = behaviour.harsh_acceleration

      assert %Event{
               location: {114.1589, 22.2799},
               acceleration: 3.2,
               initial_speed: 20,
               end_speed: 45
             } = acceleration

      # This section reports no centripetal acceleration or speed limit.
      assert acceleration.centripetal_acc == nil
      assert acceleration.speed_limit == nil

      assert %Section{points: [steering]} = behaviour.harsh_steering
      assert %Event{centripetal_acc: 2.5, speed: 60} = steering

      assert %Section{points: [speeding]} = behaviour.speed_limit
      assert %Event{speed: 110, speed_limit: 80} = speeding
    end

    test "validates the thresholds Amap documents", %{client: client} do
      assert_raise ArgumentError,
                   ~r/:speed_limit_thres must be between 30 and 120, got: 20/,
                   fn ->
                     TrackAnalysis.driving_behavior(client, 1, 456, 20, speed_limit_thres: 20)
                   end

      assert_raise ArgumentError, ~r/window times must be a DateTime or unix milliseconds/, fn ->
        TrackAnalysis.driving_behavior(client, 1, 456, 20, start_time: "noon")
      end
    end
  end

  test "a payload that is not an object becomes a named error, not a crash", %{
    server: server,
    client: client
  } do
    # Amap's pages say a value arrives as a string or as an array. The live service
    # answered this endpoint with a non-empty array where the docs promise an
    # object, which used to crash inside the mapper on a string index.
    arm(
      server,
      "/v1/track/analysis/drivingbehavior",
      ~s({"errcode":10000,"errmsg":"OK","data":[{"distance":12000}]})
    )

    assert {:error, %Amap.Error{reason: :unexpected_response} = error} =
             TrackAnalysis.driving_behavior(client, 1, 456, 20)

    # The payload travels with the error, so a caller can see what arrived.
    assert %{body: [%{"distance" => 12_000}]} = error.response
  end

  describe "stay_points/5" do
    @stay_body ~s({"errcode":10000,"errmsg":"OK","data":{"stayPointCount":1,"stayPoints":[{"startTime":1789703117430,"endTime":1789703717430,"duration":600000,"location":"114.1589,22.2799","address":"香港中環"}]}})

    test "sends the ids and leaves Amap's defaults out", %{server: server, client: client} do
      arm(server, "/v1/track/analysis/staypoint", @stay_body)

      assert {:ok, %StayPoints{}} = TrackAnalysis.stay_points(client, 1, 456, 20)

      assert_receive {:params, params}
      refute Map.has_key?(params, "stayRadius")
      refute Map.has_key?(params, "stayTime")
      refute Map.has_key?(params, "mode")
    end

    test "sends a window, a radius, a duration and the mode", %{server: server, client: client} do
      arm(server, "/v1/track/analysis/staypoint", @stay_body)

      TrackAnalysis.stay_points(client, 1, 456, 20,
        start_time: 1_789_703_117_430,
        stay_radius: 100,
        stay_time: 120,
        mode: :driving
      )

      assert_receive {:params, params}
      assert params["startTime"] == "1789703117430"
      assert params["stayRadius"] == "100"
      assert params["stayTime"] == "120"
      assert params["mode"] == "driving"
    end

    test "maps each stay point, address included", %{server: server, client: client} do
      arm(server, "/v1/track/analysis/staypoint", @stay_body)

      assert {:ok, %StayPoints{count: 1, points: [stay]}} =
               TrackAnalysis.stay_points(client, 1, 456, 20)

      assert %StayPoint{
               start_time: 1_789_703_117_430,
               duration: 600_000,
               location: {114.1589, 22.2799},
               address: "香港中環"
             } = stay
    end

    test "validates the radius, the duration and the mode", %{client: client} do
      assert_raise ArgumentError, ~r/:stay_radius must be between 5 and 500, got: 4/, fn ->
        TrackAnalysis.stay_points(client, 1, 456, 20, stay_radius: 4)
      end

      assert_raise ArgumentError, ~r/:stay_time must be at least 60 seconds, got: 59/, fn ->
        TrackAnalysis.stay_points(client, 1, 456, 20, stay_time: 59)
      end

      assert_raise ArgumentError, ~r/:mode must be :driving, got: :flying/, fn ->
        TrackAnalysis.stay_points(client, 1, 456, 20, mode: :flying)
      end
    end

    test "an Amap error comes back as the error struct", %{server: server, client: client} do
      arm(
        server,
        "/v1/track/analysis/staypoint",
        ~s({"errcode":20051,"errmsg":"TERMINAL_NOT_FOUND"})
      )

      assert {:error, error} = TrackAnalysis.stay_points(client, 1, 456, 20)
      assert error.reason == :terminal_not_found
    end
  end
end
