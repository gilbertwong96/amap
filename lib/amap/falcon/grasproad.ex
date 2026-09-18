defmodule Amap.Falcon.Grasproad do
  @moduledoc """
  Reading trajectories back, and the roads they ran on.

  `trsearch/4` describes what to read in one of two ways: a `trid`, or a
  `:starttime`/`:endtime` window of at most 24 hours that does not end in the
  future. Either way a `:correction` keyword list decides how much Amap processes
  the track — see `Amap.Falcon.Correction`.

  `roaddata/2` answers which roads the points ran on. **It is an advanced service
  that Amap enables by ticket**, so a caller without it gets an error from the
  service rather than from this SDK.
  """

  alias Amap.Falcon.Correction
  alias Amap.Falcon.Grasproad.Degraded
  alias Amap.Falcon.Grasproad.Result
  alias Amap.Falcon.Grasproad.RoadResult
  alias Amap.Falcon.Grasproad.RoadTrack
  alias Amap.Falcon.Grasproad.Track
  alias Amap.Falcon.Position
  alias Amap.Falcon.Wire
  alias Amap.Numeric
  alias Amap.Validate

  @base "/v1/track/terminal"

  @doc """
  Reads trajectory information.

  With `trid:`, it returns that one trace. With `:starttime` and `:endtime`, it
  returns every trace segment in the window — which may be more than one.

  Options: `:trid`, `:starttime`, `:endtime`, `:correction`, `:recoup`, `:gap`,
  `:ispoints`, `:page` (at most 100) and `:pagesize` (at most 999).

  Every field of a point except `:location` may come back `nil` when correction
  was applied, because Amap drops what it cannot derive from the snapped track.
  """
  @spec trsearch(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def trsearch(client, sid, tid, opts \\ []) do
    trid = Keyword.get(opts, :trid)
    starttime = to_ms(Keyword.get(opts, :starttime))
    endtime = to_ms(Keyword.get(opts, :endtime))

    Correction.window!(trid, starttime, endtime, System.system_time(:millisecond))

    params = [
      sid: sid,
      tid: tid,
      trid: trid,
      starttime: starttime,
      endtime: endtime,
      correction: Correction.encode(Keyword.get(opts, :correction)),
      recoup: Wire.flag!(Keyword.get(opts, :recoup)),
      gap: Validate.optional_range!(Keyword.get(opts, :gap), ":gap", 50, 10_000),
      ispoints: Wire.flag!(Keyword.get(opts, :ispoints)),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, 100),
      pagesize: Validate.optional_range!(Keyword.get(opts, :pagesize), ":pagesize", 1, 999)
    ]

    case Amap.request(client, :tsapi, :get, @base <> "/trsearch", params) do
      {:ok, payload} -> {:ok, to_result(payload)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Asks which roads the points ran on.

  Say what to read either with `:points` (5 to 500 of them, the same maps
  `Amap.Falcon.Point.upload/5` takes) or with all of `:sid`, `:tid` and `:trid`.
  `:car_type` is `:bus` or `:truck`, and `:threshold` filters out points whose
  accuracy is at least that many metres.

  **Amap has to enable this service by ticket**; without it the call comes back as
  an `%Amap.Error{}` rather than a result.
  """
  @spec roaddata(Amap.Client.t(), keyword()) :: {:ok, RoadResult.t()} | {:error, Amap.Error.t()}
  def roaddata(client, opts) do
    sid = Keyword.get(opts, :sid)
    tid = Keyword.get(opts, :tid)
    trid = Keyword.get(opts, :trid)
    points = Keyword.get(opts, :points)

    identity!(sid, tid, trid, points)

    params = [
      sid: sid,
      tid: tid,
      trid: trid,
      points: encode_points(points),
      carType: encode_car_type(Keyword.get(opts, :car_type)),
      threshold: Validate.optional_range!(Keyword.get(opts, :threshold), ":threshold", 0, 99_999)
    ]

    case Amap.request(client, :tsapi, :post, @base <> "/roaddata", params) do
      {:ok, payload} -> {:ok, to_road_result(payload)}
      {:error, _} = error -> error
    end
  end

  defp identity!(sid, tid, trid, points) do
    cond do
      points != nil and (sid != nil or tid != nil or trid != nil) ->
        raise ArgumentError, "pass either :points or :sid/:tid/:trid, not both"

      points != nil ->
        Validate.range!(length(points), ":points", 5, 500)

      sid != nil and tid != nil and trid != nil ->
        :ok

      true ->
        raise ArgumentError, "roaddata needs either :points, or all of :sid, :tid and :trid"
    end
  end

  defp to_ms(nil), do: nil
  defp to_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp to_ms(ms) when is_integer(ms), do: ms

  defp to_ms(other),
    do:
      raise(
        ArgumentError,
        "trajectory times must be a DateTime or unix milliseconds, got: #{inspect(other)}"
      )

  defp encode_points(nil), do: nil

  defp encode_points(points),
    do: Amap.JSON.encode!(Enum.map(points, &Amap.Falcon.Point.encode/1))

  # `Wire.decode_flag/1` turns Amap's 1/0 back into a boolean; `Wire.flag!/1` is
  # the encoding direction, for request options.
  defp decode_flag(value), do: Wire.decode_flag(value)

  defp encode_car_type(nil), do: nil
  defp encode_car_type(:bus), do: "0"
  defp encode_car_type(:truck), do: "1"

  defp encode_car_type(other),
    do: raise(ArgumentError, ":car_type must be :bus or :truck, got: #{inspect(other)}")

  defp to_result(payload) do
    %Result{
      counts: Numeric.to_integer(payload["counts"]),
      tracks: Enum.map(Map.get(payload, "tracks", []), &to_track/1),
      degraded_params: to_degraded(payload["degradedParams"])
    }
  end

  defp to_degraded(nil), do: nil

  defp to_degraded(payload) when is_map(payload),
    do: %Degraded{threshold: decode_flag(payload["threshold"])}

  defp to_track(payload) do
    %Track{
      trid: Numeric.to_integer(payload["trid"]),
      trname: payload["trname"],
      distance: payload["distance"],
      time: payload["time"],
      counts: Numeric.to_integer(payload["counts"]),
      points: Enum.map(Map.get(payload, "points", []), &Position.from_payload/1)
    }
  end

  defp to_road_result(payload) do
    %RoadResult{
      counts: Numeric.to_integer(payload["counts"]),
      distance: payload["distance"],
      tracks: Enum.map(Map.get(payload, "tracks", []), &to_road_track/1)
    }
  end

  defp to_road_track(payload) do
    %RoadTrack{
      road_name: payload["roadName"],
      speed_limit: Numeric.to_integer(payload["speedLimit"]),
      road_class: Numeric.to_integer(payload["roadClass"]),
      road_class_name: payload["roadClassName"],
      is_toll: decode_flag(payload["isToll"]),
      is_ownership: decode_flag(payload["isOwnership"]),
      points: Enum.map(Map.get(payload, "points", []), &Position.from_payload/1)
    }
  end
end
