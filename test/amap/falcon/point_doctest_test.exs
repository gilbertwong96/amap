defmodule Amap.Falcon.PointDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # 20100 is a partial success: the first point was stored, the second refused.
  @partial ~s({"errcode":20100,"errmsg":"PARTIAL_SUCCESS",) <>
             ~s("data":{"errorpoints":[{"_err_point_index":"2",) <>
             ~s("_param_err_info":"invalid direction","direction":"999"}]}})

  @stored ~s({"errcode":10000,"errmsg":"OK","data":{"errorpoints":[]}})

  setup_all do
    server = TestServer.start_doctest!()

    # Only the documented encoding is accepted: `location` as `lon,lat`, a
    # DateTime as unix milliseconds, `props` as a JSON object string, and no
    # measurement the caller did not give.
    TestServer.expect(server, "POST", "/v1/track/point/upload", fn request ->
      body = URI.decode_query(request.body)
      points = body |> Map.get("points", "[]") |> JSON.decode!()

      case points do
        [
          %{"location" => "114.158,22.279", "locatetime" => 1_789_703_117_430},
          %{"location" => "114.159,22.28", "direction" => 999}
        ] ->
          {200, @partial}

        [
          %{
            "location" => "114.158,22.279",
            "locatetime" => 1_789_646_400_000,
            "props" => ~s({"driver":"abc"})
          } = point
        ] ->
          if Map.has_key?(point, "speed") or Map.has_key?(point, "height") do
            {404, "unexpected optional fields"}
          else
            {200, @stored}
          end

        _other ->
          {404, "unexpected points"}
      end
    end)

    :ok
  end

  doctest Amap.Falcon.Point
end
