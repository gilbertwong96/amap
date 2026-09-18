defmodule Amap.Falcon.Point do
  @moduledoc """
  Trajectory points.

  Points are uploaded in batches of at most 100 against a trace, and a service's
  custom trace fields (declared through `Amap.Falcon.TraceColumn`) are what a
  point's `:props` may carry.

  A point is a map:

      %{
        location: {114.158, 22.279},          # required, {lon, lat}
        locatetime: ~U[2026-09-17 12:00:00Z], # required, DateTime or unix milliseconds
        speed: 40.0,                          # optional, km/h
        direction: 120,                       # optional, 0..360
        height: 39,                           # optional, metres
        accuracy: 20,                         # optional
        props: %{"driver" => "abc"}           # optional, JSON-encoded for you
      }

  Amap stores the valid points even when some fail: the call answers `20100` and
  names the offending indices in `data.errorpoints`, which `upload/5` maps into
  `%Amap.Falcon.Point.Upload{}`.
  """

  alias Amap.Falcon.Point.Upload
  alias Amap.Falcon.Point.UploadError
  alias Amap.Validate

  @max_points 100
  @base "/v1/track/point"

  @doc """
  Uploads up to 100 points against a trace.

  Returns `{:ok, %Upload{}}` even when some points were refused — check its
  `errorpoints`. Points whose `trid` does not exist are stored against the
  terminal instead, and Amap reports that in the same list.
  """
  @spec upload(Amap.Client.t(), integer(), integer(), integer(), [map()]) ::
          {:ok, Upload.t()} | {:error, Amap.Error.t()}
  def upload(client, sid, tid, trid, points) when is_list(points) do
    Validate.range!(length(points), ":points", 1, @max_points)

    params = [
      sid: sid,
      tid: tid,
      trid: trid,
      points: Amap.JSON.encode!(Enum.map(points, &encode/1))
    ]

    case Amap.request(client, :tsapi, :post, @base <> "/upload", params) do
      {:ok, payload} -> {:ok, to_upload(payload)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Encodes one point into Amap's JSON shape.

  Public because two endpoints take points: this one uploads them, and
  `Amap.Falcon.Grasproad.roaddata/2` asks which roads they ran on.
  """
  @spec encode(map()) :: map()
  def encode(point) when is_map(point) do
    %{
      "location" => Amap.Param.location(required!(point, :location)),
      "locatetime" => unix_ms(required!(point, :locatetime))
    }
    |> put(point, "speed", :speed)
    |> put(point, "direction", :direction)
    |> put(point, "height", :height)
    |> put(point, "accuracy", :accuracy)
    |> put_props(point)
  end

  def encode(other),
    do: raise(ArgumentError, "each point must be a map, got: #{inspect(other)}")

  defp required!(point, key) do
    case Map.get(point, key) do
      nil -> raise ArgumentError, "each point needs #{inspect(key)}, got: #{inspect(point)}"
      value -> value
    end
  end

  defp unix_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp unix_ms(ms) when is_integer(ms), do: ms

  defp unix_ms(other),
    do:
      raise(
        ArgumentError,
        ":locatetime must be a DateTime or unix milliseconds, got: #{inspect(other)}"
      )

  defp put(encoded, point, wire_key, key) do
    case Map.get(point, key) do
      nil -> encoded
      value -> Map.put(encoded, wire_key, value)
    end
  end

  defp put_props(encoded, point) do
    case Map.get(point, :props) do
      nil -> encoded
      props when is_map(props) -> Map.put(encoded, "props", Amap.Param.props(props))
      other -> raise ArgumentError, ":props must be a map, got: #{inspect(other)}"
    end
  end

  defp to_upload(payload) do
    errors =
      payload
      |> Map.get("errorpoints", [])
      |> List.wrap()
      |> Enum.map(&to_upload_error/1)

    %Upload{errorpoints: errors}
  end

  defp to_upload_error(error) when is_map(error) do
    %UploadError{
      index: error["_err_point_index"],
      message: error["_param_err_info"],
      raw: Map.drop(error, ["_err_point_index", "_param_err_info"])
    }
  end
end
