defmodule Amap.Grasproad do
  @moduledoc """
  轨迹纠偏 — snapping a driven track onto the roads it was driven on.

  The page is one endpoint, `POST /v4/grasproad/driving`, and it breaks two of this
  SDK's usual assumptions at once:

    * its URL is on `restapi.amap.com`, but its answer is the Falcon (猎鹰) envelope —
      `errcode`/`errmsg`/`errdetail` around a `data` object. It is the second of the
      three known `/v4/`-on-`restapi` endpoints that do this (the first is
      `Amap.Direction.bicycling/4`; `/v4/etd/driving` is the third), which is why the
      call names host `:restapi` for the destination and envelope `:tsapi` for the
      answer;
    * its request body is a **JSON array** of up to 500 point objects, the only
      endpoint in this SDK besides `Amap.Falcon.TrackMatch` that sends JSON at all.

  A point is a map: the wire's `x`/`y` are one `{lon, lat}` tuple here, as every
  other coordinate in the SDK, and `ag`/`tm`/`sp` keep the page's names:

      %{location: {116.478928, 39.997761}, ag: 0, tm: 1_478_031_031, sp: 19}

  One such map is a one-point track; a list of them is the array form. Both go out as
  the page's `JsonArray` of `{x,y,ag,tm,sp}` objects, which for that point is:

      [{"x": 116.478928, "y": 39.997761, "ag": 0, "tm": 1478031031, "sp": 19}]

  `tm` is **seconds** — the first point's is a Unix timestamp (the page's 从1970年0点开始),
  and every later point's is the difference from it. `sp` is km/h and `ag` the angle
  from due north in degrees; the page warns that an `ag` of 0, or an unreasonable `sp`,
  makes a failed correction likely — and its own sample starts with `ag: 0`.

  The page caps access for 个人认证开发者 at 10000 calls a day (每天仅能访问该接口
  10000 次), and points bulk users at the Falcon track service (猎鹰轨迹服务).

  A live run (2026-09-21) settled the shapes the page leaves open. Success is
  `errcode: 0` with `errmsg` "OK" and no `errdetail`, and the raw envelope carries a
  fifth `ext` key beside the four fields `Amap.Response` reads. `data` is
  `{distance, points[]}`: `distance` arrives as a **float** (`696.0`) and each point
  `{"x": …, "y": …}` a pair of JSON numbers — the two `/v4/`-on-`restapi` endpoints'
  numeric shape, not the string distances the v3 and v5 routing pages send. The run also
  shows Amap **densifying** the corrected track: the page's 8-point sample came back as
  28 points, so a returned point is a coordinate on the road the track was snapped to,
  not the answer to one sent point.

  A correction Amap cannot make answers `30001` 抓路失败 — often because the points were
  too few or too sparse, and the run saw it for an empty array, a single point and a
  sparse two-point track alike. Its wire text is the generic `ENGINE_RESPONSE_DATA_ERROR`
  with `errdetail` 引擎返回数据异常; `Amap.Error` reports it as `:grasproad_failed` with
  `retry: :no`. The 500-object cap is Amap's too: a raw 501-object body answered `20000`
  `INVALID_PARAMS` with a 500-specific `errdetail`, while this SDK raises `ArgumentError`
  before sending one.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> track = [
      ...>   %{location: {116.478928, 39.997761}, ag: 0, tm: 1_478_031_031, sp: 19},
      ...>   %{location: {116.478907, 39.998422}, ag: 0, tm: 2, sp: 10},
      ...>   %{location: {116.479384, 39.998546}, ag: 110, tm: 3, sp: 10},
      ...>   %{location: {116.481053, 39.998204}, ag: 120, tm: 4, sp: 10},
      ...>   %{location: {116.481793, 39.997868}, ag: 120, tm: 5, sp: 10},
      ...>   %{location: {116.482898, 39.998217}, ag: 30, tm: 6, sp: 10},
      ...>   %{location: {116.483789, 39.999063}, ag: 30, tm: 7, sp: 10},
      ...>   %{location: {116.484674, 39.999844}, ag: 30, tm: 8, sp: 10}
      ...> ]
      iex> {:ok, corrected} = Amap.Grasproad.driving(client, track)
      iex> {corrected.distance, Enum.map(corrected.points, &{&1.x, &1.y})}
      {696.0, [{116.478928, 39.997761}, {116.47893, 39.9978}, {116.479384, 39.998546}]}
      iex> Amap.Grasproad.driving(client, List.duplicate(%{location: {116.4, 39.9}, ag: 0, tm: 1, sp: 10}, 501))
      ** (ArgumentError) :points must be between 1 and 500, got: 501

  The corrected track is what the call decodes to: `data.distance` as a float and
  each `data.points` entry as an `Amap.Grasproad.Point`. A track over the page's
  500-point cap is refused before a request is built.

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> {:error, failed} =
      ...>   Amap.Grasproad.driving(client, %{
      ...>     location: {116.478928, 39.997761},
      ...>     ag: 0,
      ...>     tm: 1_478_031_031,
      ...>     sp: 19
      ...>   })
      iex> {failed.reason, failed.retry}
      {:grasproad_failed, :no}

  A correction Amap cannot make is a failure rather than an empty result: 30001
  arrives as `:grasproad_failed` with `retry: :no`.
  """

  alias Amap.Grasproad.Point
  alias Amap.Grasproad.Result
  alias Amap.Param
  alias Amap.Validate

  @path "/v4/grasproad/driving"
  @max_points 500

  @typedoc """
  A point to correct: where it was, which way it faced, how fast, and when.

  `location` is a `{lon, lat}` tuple — the body splits it into the wire's `x` and `y`.
  `ag`, `tm` and `sp` are the page's names: degrees from due north, seconds (the first
  point's from 1970, later points' as differences from it), and km/h.
  """
  @type point :: %{
          required(:location) => {number(), number()},
          required(:ag) => number(),
          required(:tm) => non_neg_integer() | DateTime.t(),
          required(:sp) => number()
        }

  @doc """
  Corrects a driving track and returns the road coordinates Amap snapped it to.

  `points` is one point map or a list of them, at most 500 — a list of one is the same
  call as a bare point map, and the body goes out as the JSON array the page requires
  either way.

  The first point's `tm` may be a `DateTime` or unix seconds; every later point's must
  be seconds from the first, because the page defines later values as differences and
  an absolute instant there would silently mean the wrong moment.
  """
  @spec driving(Amap.Client.t(), point() | [point()]) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def driving(client, points) do
    case Amap.request(client, :restapi, :post, @path, encode_points(points!(points)),
           body: :json,
           envelope: :tsapi
         ) do
      {:ok, payload} -> {:ok, to_result(payload)}
      {:error, _} = error -> error
    end
  end

  defp points!(%{} = point), do: [point]

  defp points!(points) when is_list(points) and points != [] do
    Enum.each(points, fn point ->
      unless is_map(point) do
        raise ArgumentError, "each point must be a map, got: #{inspect(point)}"
      end
    end)

    Validate.range!(length(points), ":points", 1, @max_points)
    points
  end

  defp points!(other) do
    raise ArgumentError,
          "points must be a point map or a non-empty list of point maps, got: #{inspect(other)}"
  end

  defp encode_points(points) do
    points
    |> Enum.with_index()
    |> Enum.map(fn {point, index} -> encode_point(point, index) end)
  end

  defp encode_point(point, index) do
    {lon, lat} =
      point
      |> Validate.required!(:location)
      |> Validate.point!(":location")

    %{
      "x" => json_coord(lon),
      "y" => json_coord(lat),
      "ag" => number!(Validate.required!(point, :ag), ":ag"),
      "tm" => time!(Validate.required!(point, :tm), index),
      "sp" => speed!(Validate.required!(point, :sp))
    }
  end

  # The page caps a coordinate at six decimals, which is `Param.coord/1`'s rule — the
  # body carries them as JSON numbers, though, so the formatted value is read back as a
  # number. An integer is already exact and stays one.
  defp json_coord(value) when is_integer(value), do: value

  defp json_coord(value) when is_float(value) do
    value
    |> Param.coord()
    |> Float.parse()
    |> elem(0)
  end

  defp number!(value, _field) when is_number(value), do: value

  defp number!(value, field) do
    raise ArgumentError, "#{field} must be a number, got: #{inspect(value)}"
  end

  defp speed!(value) when is_number(value) and value >= 0, do: value

  defp speed!(value) when is_number(value) do
    raise ArgumentError, ":sp must be a non-negative speed in km/h, got: #{inspect(value)}"
  end

  defp speed!(value) do
    raise ArgumentError, ":sp must be a number, got: #{inspect(value)}"
  end

  defp time!(%DateTime{} = time, 0), do: DateTime.to_unix(time)

  defp time!(time, 0) when is_integer(time) and time >= 0, do: time

  defp time!(time, _index) when is_integer(time) and time >= 0, do: time

  defp time!(%DateTime{} = time, _index) do
    raise ArgumentError,
          ":tm must be a DateTime only on the first point; later points are seconds " <>
            "from the first, got: #{inspect(time)}"
  end

  defp time!(time, _index) do
    raise ArgumentError,
          ":tm must be non-negative seconds, or a DateTime on the first point, got: " <>
            inspect(time)
  end

  defp to_result(payload) when is_map(payload) do
    %Result{distance: payload["distance"], points: to_points(payload["points"])}
  end

  defp to_result(_missing_or_unexpected), do: %Result{}

  # The page types none of the three scalars, so each is kept as sent — see
  # `Amap.Grasproad.Point`. An entry that is not an object is dropped, as
  # `Amap.Search.rows/4` drops one.
  defp to_points(points) when is_list(points) do
    points
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn point -> %Point{x: point["x"], y: point["y"]} end)
  end

  defp to_points(_missing), do: []
end
