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
  def locations(points), do: Enum.map_join(points, ";", &location/1)

  @doc """
  Formats `{longitude, latitude}` as `lat,lon`.

  The Falcon search endpoints take the centre and the polygon latitude first,
  the reverse of `location/1`. Both orders occur in one family, so each
  endpoint's order is chosen here rather than by the caller.
  """
  @spec lat_lng({number(), number()}) :: String.t()
  def lat_lng({lon, lat}), do: coord(lat) <> "," <> coord(lon)

  @doc """
  Formats one polygon ring, or several, in lat,lon order — the order the Falcon (猎鹰)
  search endpoints take.

  A ring is a list of `{lon, lat}` points; several rings are a list of rings.
  Rings are joined with `;` and groups with `|`, which is the form Amap's
  `polygon` parameter takes. Amap also caps the total bounding area at 3000 km²,
  which this cannot check.

  **Latitude-first is the Falcon (猎鹰) rule, not Amap's.** Every Web service
  (Web 服务) polygon — the routing `avoidpolygons`, the search endpoints' `polygon`,
  GeoHUB's — is longitude-first and wants `polygon_lon_first/1`; reaching for this function there
  transposes every vertex silently, because the request still succeeds.
  """
  @spec polygon([{number(), number()}] | [[{number(), number()}]]) :: String.t()
  def polygon(ring) when is_list(ring), do: ring |> rings() |> encode_rings(&lat_lng/1)

  @doc """
  Formats one polygon ring, or several, in lon,lat order — Amap's Web-service rule.

  The shape `polygon/1` takes: a ring is a list of `{lon, lat}` points, several rings a
  list of rings, told apart by what they hold. Rings are joined with `;` and groups
  with `|`, the form the `polygon` parameter takes on every family.

  **This is the order every Web-service polygon wants** — the routing `avoidpolygons`,
  the search endpoints' `polygon`, GeoHUB's — because those pages say 经度在前，纬度在后.
  `polygon/1` is the same shape in Falcon's latitude-first order, for the search
  endpoints that take the centre and the polygon latitude first. A transposed polygon
  is not rejected: the request answers `200` and covers the wrong area.
  """
  @spec polygon_lon_first([{number(), number()}] | [[{number(), number()}]]) :: String.t()
  def polygon_lon_first(ring) when is_list(ring), do: ring |> rings() |> encode_rings(&location/1)

  defp rings([{_lon, _lat} | _] = ring), do: [ring]
  defp rings(rings), do: rings

  defp encode_rings(rings, point) do
    Enum.map_join(rings, "|", fn ring -> Enum.map_join(ring, ";", point) end)
  end

  @doc "Joins a list with `|`, as used by search `types` and similar."
  @spec pipe([String.t()]) :: String.t()
  def pipe(values), do: Enum.map_join(values, "|", &to_string/1)

  @doc """
  Joins a list with `,`, which is how the v5 pages take `show_fields`.

  Amap reads it as one parameter holding several names, so a caller's groups — `cost`,
  `navi` and the rest — travel as `cost,navi` rather than as repeated parameters.
  """
  @spec csv([String.t() | atom()]) :: String.t()
  def csv(values), do: Enum.map_join(values, ",", &to_string/1)

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
  Formats a `Date` the way Amap's routing pages write it: `2014-3-19`.

  The month and the day carry no leading zero, because that is the form the pages
  give — `date=2014-3-19`, not `2014-03-19`.
  """
  @spec date(Date.t()) :: String.t()
  def date(%Date{year: year, month: month, day: day}), do: "#{year}-#{month}-#{day}"

  @doc """
  Formats a `Time` as the hour and minute those pages write: `22:34`.

  Seconds are dropped: the parameter carries none, and Amap's own example has none.
  """
  @spec time(Time.t()) :: String.t()
  def time(%Time{hour: hour, minute: minute}), do: "#{hour}:#{minute}"

  @doc """
  Encodes Falcon custom fields (`props`) as a JSON object string.
  """
  @spec props(Amap.JSON.props()) :: String.t()
  def props(map) when is_map(map), do: Amap.JSON.encode!(map)

  @doc """
  Normalizes a parameter container, dropping `nil` values so that absent
  parameters are absent from the request rather than sent empty.

  Floats are formatted with the same rules as `coord/1`, so no float can leave
  this module in scientific notation. Integers, strings and atoms are
  stringified as-is.
  """
  @spec encode(Amap.JSON.props() | keyword()) :: [{String.t(), String.t()}]
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
