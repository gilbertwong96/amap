defmodule Amap.Falcon.TrackMatch do
  @moduledoc """
  How much two trajectories overlap.

  Both tracks are given as `{sid, tid, trid}` tuples, and they travel in a **JSON
  body** — this is the one Amap endpoint in this SDK that asks for one, which is why
  `Amap.request/6` grew its `body: :json` option.

  `match_ratio` arrives as a **string** (`"84.7"`), and is kept that way rather than
  parsed: it is what Amap said, and a caller who wants a number can say so.
  """

  alias Amap.Falcon.TrackMatch.Match
  alias Amap.Falcon.TrackMatch.Track
  alias Amap.Numeric

  @base "/v1/track/match"

  @doc """
  Compares a target trajectory against a baseline one.

  Both are `{sid, tid, trid}` tuples. `is_points: true` asks for the corrected
  coordinates of both tracks back as well; Amap leaves them out by default.
  """
  @spec match(
          Amap.Client.t(),
          {integer(), integer(), integer()},
          {integer(), integer(), integer()},
          keyword()
        ) :: {:ok, Match.t()} | {:error, Amap.Error.t()}
  def match(client, baseline, target, opts \\ []) do
    params = %{
      "baseline" => encode_track!(baseline, ":baseline"),
      "target" => encode_track!(target, ":target"),
      "isPoints" => json_flag!(Keyword.get(opts, :is_points))
    }

    client
    |> Amap.request(:tsapi, :post, @base, params, body: :json)
    |> to_match()
  end

  defp encode_track!({sid, tid, trid}, _field), do: %{"sid" => sid, "tid" => tid, "trid" => trid}

  defp encode_track!(other, field),
    do: raise(ArgumentError, "#{field} must be a {sid, tid, trid} tuple, got: #{inspect(other)}")

  # A JSON body carries numbers, not the "1"/"0" strings a form does.
  defp json_flag!(nil), do: 0
  defp json_flag!(true), do: 1
  defp json_flag!(false), do: 0

  defp json_flag!(other),
    do: raise(ArgumentError, ":is_points must be a boolean, got: #{inspect(other)}")

  defp to_match({:ok, payload}) do
    {:ok,
     %Match{
       match_ratio: payload["matchRatio"],
       match_distance: payload["matchDistance"],
       mismatch_distance: payload["mismatchDistance"],
       mismatch_time: Numeric.to_integer(payload["mismatchTime"]),
       match_points: parse_points(payload["matchPoints"]),
       baseline: to_track(payload["baseline"]),
       target: to_track(payload["target"])
     }}
  end

  defp to_match({:error, _} = error), do: error

  defp to_track(nil), do: nil

  defp to_track(payload) when is_map(payload) do
    %Track{points: parse_points(payload["points"]), distance: payload["distance"]}
  end

  defp parse_points(nil), do: nil

  # Amap documents this endpoint's coordinate strings as comma-separated, unlike the
  # semicolons every other endpoint uses, and does not say how a coordinate is then
  # separated from its pair. Both readings are handled — semicolons between points,
  # or one flat comma-separated list — and the live run reports which it really is.
  defp parse_points(string) when is_binary(string) do
    string
    |> split_points()
    |> Enum.map(&Amap.Falcon.Point.parse_location/1)
    |> Enum.reject(&is_nil/1)
  end

  defp split_points(string) do
    if String.contains?(string, ";") do
      String.split(string, ";", trim: true)
    else
      # One flat comma-separated list, "lon,lat,lon,lat", read as pairs.
      string
      |> String.split(",", trim: true)
      |> Enum.chunk_every(2)
      |> Enum.map(&Enum.join(&1, ","))
    end
  end
end
