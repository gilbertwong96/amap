defmodule Amap.Param do
  @moduledoc """
  Amap's parameter encoding rules.

  These are not generic URL encoding rules — Amap has its own conventions and
  is inconsistent between endpoints (booleans in particular), so every encoder
  here is explicit about what it produces.
  """

  @decimals 6

  @doc """
  Formats a coordinate as Amap expects: at most six decimal places, never in
  scientific notation.
  """
  @spec coord(number()) :: String.t()
  def coord(value) when is_number(value) do
    format_float(value)
  end

  @doc "Formats `{longitude, latitude}` as `lon,lat`."
  @spec location({number(), number()}) :: String.t()
  def location({lon, lat}), do: coord(lon) <> "," <> coord(lat)

  @doc "Formats a list of points separated by `;`."
  @spec locations([{number(), number()}]) :: String.t()
  def locations(points), do: points |> Enum.map(&location/1) |> Enum.join(";")

  @doc "Joins a list with `|`, as used by search `types` and similar."
  @spec pipe([String.t()]) :: String.t()
  def pipe(values), do: Enum.map_join(values, "|", &to_string/1)

  @doc """
  Encodes a boolean. Amap accepts `1/0` on some endpoints and `true/false` on
  others, so the caller states which one it wants.
  """
  @spec boolean(boolean(), as: :int | :bool) :: String.t()
  def boolean(value, as: :int), do: if(value, do: "1", else: "0")
  def boolean(value, as: :bool), do: if(value, do: "true", else: "false")

  @doc "Encodes a `DateTime` as Unix seconds, as Falcon endpoints expect."
  @spec unix_time(DateTime.t()) :: String.t()
  def unix_time(%DateTime{} = dt), do: dt |> DateTime.to_unix() |> Integer.to_string()

  @doc """
  Encodes Falcon custom fields (`props`) as a JSON object string.
  """
  @spec props(map()) :: String.t()
  def props(map) when is_map(map), do: Amap.JSON.encode!(map)

  @doc """
  Normalizes a parameter container, dropping `nil` values so that absent
  parameters are absent from the request rather than sent empty.

  Floats are formatted with the same rules as `coord/1`, so no float can leave
  this module in scientific notation. Integers, strings and atoms are
  stringified as-is.
  """
  @spec encode(map() | keyword()) :: [{String.t(), String.t()}]
  def encode(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {to_string(k), encode_value(v)} end)
  end

  # `to_string/1` delegates to `Float.to_string/1` for floats, which emits
  # scientific notation for small and large magnitudes ("1.0e-5"), the form
  # Amap rejects. Integers keep `to_string/1` so they stay exact and do not gain
  # a decimal point.
  defp encode_value(value) when is_float(value), do: format_float(value)
  defp encode_value(value), do: to_string(value)

  defp format_float(value) do
    :erlang.float_to_binary(value * 1.0, [:compact, decimals: @decimals])
  end
end
