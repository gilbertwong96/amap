defmodule Amap.Falcon.TrackAnalysisDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # Leaving the thresholds out asks Amap's own policy, so this answer has no
  # speeding section.
  @default_policy ~s({"errcode":10000,"errmsg":"OK",) <>
                    ~s("data":{"distance":12000,"duration":900000,"aveSpeed":48,"maxSpeed":96,) <>
                    ~s("harshAccelerationCount":0,"harshDecelerationCount":0,"harshSteeringCount":0,) <>
                    ~s("harshAcceleration":{"points":[]},"harshDeceleration":{"points":[]},) <>
                    ~s("harshSteering":{"points":[]},"speedLimit":{"points":[]}}})

  # The live service nests a non-empty event list one level deeper than an empty
  # one; asking for speed_limit_thres: 80 is what gets the speeding section.
  @strict ~s({"errcode":10000,"errmsg":"OK",) <>
            ~s("data":{"distance":12000,"duration":900000,"aveSpeed":48,"maxSpeed":96,) <>
            ~s("harshAccelerationCount":1,"harshDecelerationCount":0,"harshSteeringCount":0,) <>
            ~s("harshAcceleration":{"points":[[{"location":"114.1589,22.2799",) <>
            ~s("locateTime":1789703117430,"acceleration":3.2,"initialSpeed":20,"endSpeed":45}]]},) <>
            ~s("harshDeceleration":{"points":[]},"harshSteering":{"points":[]},) <>
            ~s("speedLimit":{"points":[{"location":"114.17,22.29",) <>
            ~s("locateTime":1789703119430,"speed":110,"speedLimit":80}]}}})

  # Neither the endpoint's object nor a one-element wrapper of it.
  @unexpected ~s({"errcode":10000,"errmsg":"OK",) <>
                ~s("data":[{"distance":1},{"distance":2}]})

  @stay ~s({"errcode":10000,"errmsg":"OK",) <>
          ~s("data":{"stayPointCount":1,"stayPoints":[{"startTime":1789703117430,) <>
          ~s("endTime":1789703717430,"duration":600000,) <>
          ~s("location":"114.1589,22.2799","address":"香港中環"}]}})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "GET", "/v1/track/analysis/drivingbehavior", fn request ->
      query = URI.decode_query(request.query)

      cond do
        query["trid"] == "21" -> {200, @unexpected}
        query["speedLimitThres"] == "80" -> {200, @strict}
        not Map.has_key?(query, "speedLimitThres") -> {200, @default_policy}
        true -> {404, "unexpected drivingbehavior parameters"}
      end
    end)

    TestServer.expect(server, "GET", "/v1/track/analysis/staypoint", fn request ->
      query = URI.decode_query(request.query)

      if query["stayRadius"] == "100" and query["stayTime"] == "120" and
           query["mode"] == "driving" and query["startTime"] == "1789703117430" do
        {200, @stay}
      else
        {404, "unexpected staypoint parameters"}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.TrackAnalysis
end
