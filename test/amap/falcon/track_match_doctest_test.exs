defmodule Amap.Falcon.TrackMatchDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  @with_points ~s({"errcode":10000,"errmsg":"OK",) <>
                 ~s("data":{"matchRatio":"84.7","matchDistance":12000,) <>
                 ~s("mismatchDistance":2000,"mismatchTime":1789703117430,) <>
                 ~s("matchPoints":"114.1589,22.2799;114.16,22.28",) <>
                 ~s("baseline":{"points":"114.1589,22.2799;114.16,22.28","distance":14000},) <>
                 ~s("target":{"points":"114.1589,22.2799;114.16,22.28","distance":15000}}})

  @ratio_only ~s({"errcode":10000,"errmsg":"OK",) <>
                ~s("data":{"matchRatio":"84.7","matchDistance":12000,) <>
                ~s("mismatchDistance":2000,) <>
                ~s("baseline":{"distance":14000},"target":{"distance":15000}}})

  setup_all do
    server = TestServer.start_doctest!()

    # The JSON body is the point of this endpoint: nested tracks with numeric
    # ids, and isPoints as a number rather than a form flag.
    TestServer.expect(server, "POST", "/v1/track/match", fn request ->
      body = JSON.decode!(request.body)

      valid? =
        String.starts_with?(request.headers["content-type"], "application/json") and
          body["baseline"] == %{"sid" => 1000, "tid" => 456, "trid" => 20} and
          body["target"] == %{"sid" => 1000, "tid" => 457, "trid" => 21} and
          is_integer(body["isPoints"])

      case {valid?, body["isPoints"]} do
        {true, 1} -> {200, @with_points}
        {true, 0} -> {200, @ratio_only}
        _other -> {404, "unexpected match body"}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.TrackMatch
end
