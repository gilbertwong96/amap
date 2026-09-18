defmodule Amap.Coord do
  @moduledoc """
  Parses the coordinate strings Amap writes into payloads.

  `Amap.Param` is the other direction: it takes tuples and produces the strings
  Amap's requests want. This module reads the answer back, so a struct field can
  be a `{lon, lat}` tuple rather than a string every caller has to split.

  Amap uses two separators and they do not mean the same thing — `;` separates
  points inside one string, and `|` separates whole parts of a boundary. Every
  parser here is total: an absent, mistyped or malformed value reads as `nil`, so
  a payload nobody expected surfaces as "no value" rather than as a crash.
  """

  @doc """
  Parses one `"lon,lat"` string into a tuple.

  Returns `nil` for anything unparseable. The order — longitude first — was
  confirmed against the live API on 2026-09-17 by uploading a known track and
  reading it back.
  """
  @spec parse_location(term()) :: {float(), float()} | nil
  def parse_location(nil), do: nil

  def parse_location(string) when is_binary(string) do
    with [lon, lat] <- String.split(string, ","),
         {lon, ""} <- Float.parse(lon),
         {lat, ""} <- Float.parse(lat) do
      {lon, lat}
    else
      _unparseable -> nil
    end
  end

  def parse_location(_other), do: nil

  @doc """
  Parses a `;`-separated list of points into a list of tuples.

  Amap writes a collection of points this way inside an object — convert's answer,
  for instance — while the same collection in a request is `|`-separated.
  """
  @spec parse_locations(term()) :: [{float(), float()}] | nil
  def parse_locations(nil), do: nil

  def parse_locations(string) when is_binary(string) do
    string
    |> String.split(";")
    |> map_all(&parse_location/1)
  end

  def parse_locations(_other), do: nil

  @doc """
  Parses a boundary into one list of points per part.

  District polylines separate the parts of a district that is not contiguous
  (朝阳区, for instance) with `|`, and the points inside each part with `;`.
  """
  @spec parse_polyline(term()) :: [[{float(), float()}]] | nil
  def parse_polyline(nil), do: nil

  def parse_polyline(string) when is_binary(string) do
    string
    |> String.split("|")
    |> map_all(&parse_locations/1)
  end

  def parse_polyline(_other), do: nil

  # All or nothing: one unreadable part makes the whole value unusable, since a
  # half-read boundary or point list is not something a caller can act on.
  defp map_all(parts, fun) do
    parsed = Enum.map(parts, fun)

    if Enum.any?(parsed, &is_nil/1), do: nil, else: parsed
  end
end
