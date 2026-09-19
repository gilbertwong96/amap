defmodule Amap.Routing do
  @moduledoc """
  What the two routing generations share.

  `Amap.Direction` covers Amap's v3 routing pages and `Amap.NewRoute` its v5 ones. The
  pages differ — different strategies, different response field names — but these
  things are the same on both, because they are Amap's own conventions rather than
  either generation's:

  - the cartype values: `0` 普通燃油汽车, `1` 纯电动汽车, `2` 插电式混合动力汽车;
  - waypoints: up to 16 pairs, planned in the order given, joined with `;` — the same
    sentence on both pages (经度和纬度用","分割 … 坐标点之间用";"分隔);
  - `:ferry`, whose wire value `0` means *take* the ferry on both pages;
  - the four fields a `route` object carries before either version wraps them in a
    struct: the two endpoints decoded into tuples, the taxi cost, and the raw `paths`.

  The last one lives here because the two `Route` structs are not the same type: v3 and
  v5 name a step's fields differently, so each generation builds its own struct out of
  these values rather than sharing one — which is also AGENTS.md's rule for a helper
  that touches a struct it does not own.
  """

  alias Amap.{Coord, Param, Validate}

  @max_waypoints 16

  @cartypes %{fuel: "0", electric: "1", hybrid: "2"}

  @doc """
  Maps the `:cartype` option to the value the wire takes.

  Both pages document the same three, so the mapping is Amap's rather than either
  generation's. `nil` means the caller left the parameter out and it stays out; an
  unknown name is a call-site mistake and raises.
  """
  @spec cartype(Validate.input()) :: String.t() | nil
  def cartype(nil), do: nil
  def cartype(value) when is_map_key(@cartypes, value), do: Map.fetch!(@cartypes, value)

  def cartype(other) do
    raise ArgumentError,
          ":cartype must be one of #{inspect(Map.keys(@cartypes))}, got: #{inspect(other)}"
  end

  @doc """
  Maps the `:ferry` option to the wire's `0`/`1`.

  The option is named after the intent — `:use` or `:avoid` — because the wire's `0`
  means *take* the ferry on both pages, and a caller reading only the value would read
  it backwards.
  """
  @spec ferry(Validate.input()) :: String.t() | nil
  def ferry(nil), do: nil
  def ferry(:use), do: "0"
  def ferry(:avoid), do: "1"

  def ferry(other) do
    raise ArgumentError, ":ferry must be one of [:use, :avoid], got: #{inspect(other)}"
  end

  @doc """
  Encodes `:waypoints` for the wire: `{lon, lat}` pairs joined with `;`.

  Both pages cap the list at 16 and plan the points in the order given, so the cap is
  checked here: `Validate.points!/2` rejects an entry that is not a pair, and this
  rejects a list that is too long for either endpoint.
  """
  @spec waypoints(Validate.input()) :: String.t() | nil
  def waypoints(nil), do: nil

  def waypoints(pairs) do
    pairs = Validate.points!(pairs, ":waypoints")

    if length(pairs) > @max_waypoints do
      raise ArgumentError,
            ":waypoints must be at most #{@max_waypoints} coordinate pairs, got: #{length(pairs)}"
    end

    Param.locations(pairs)
  end

  @typedoc """
  The decoded scalars of a `route` object, plus the paths a generation has mapped.

  The paths are the caller's type, because only the generation that owns the struct
  knows which fields one of its `paths` entries has.
  """
  @type route_fields(path) :: [
          {:origin, {float(), float()} | nil}
          | {:destination, {float(), float()} | nil}
          | {:taxi_cost, String.t() | nil}
          | {:paths, [path]}
        ]

  @typedoc "The same four fields before a generation has mapped its paths."
  @type route_values :: %{
          origin: {float(), float()} | nil,
          destination: {float(), float()} | nil,
          taxi_cost: String.t() | nil,
          paths: [Amap.JSON.value()]
        }

  @doc """
  Reads a `route` object into the fields the generation that owns the struct builds.

  Both pages answer `route{origin, destination, taxi_cost, paths}` with the same four
  names and decode the two endpoints the same way; the generations differ only in which
  struct holds them and in what one entry of `paths` becomes. So this decodes what is
  Amap's — the two endpoint strings into tuples, the raw `paths` list — and lets each
  module map the paths and build its own struct:

      defp to_route(payload), do: struct(Route, Routing.route_fields(payload, &to_path/1))

  That is AGENTS.md's first branch for a helper that touches a struct it does not own:
  it returns the values narrowly typed, and the module that owns the struct builds it —
  rather than the shared module holding one generation's field list for both.
  """
  @spec route_fields(Amap.JSON.value(), (Amap.JSON.value() -> path)) :: route_fields(path)
        when path: var
  def route_fields(payload, path_mapper) do
    values = route_values(payload)

    [
      origin: values.origin,
      destination: values.destination,
      taxi_cost: values.taxi_cost,
      paths: Enum.map(values.paths, path_mapper)
    ]
  end

  @spec route_values(Amap.JSON.value()) :: route_values()
  defp route_values(nil), do: empty_route()
  defp route_values(payload) when is_map(payload), do: read_route(payload)
  defp route_values(_other), do: empty_route()

  defp read_route(payload) do
    %{
      origin: Coord.parse_location(payload["origin"]),
      destination: Coord.parse_location(payload["destination"]),
      taxi_cost: payload["taxi_cost"],
      paths: paths(payload)
    }
  end

  defp empty_route, do: %{origin: nil, destination: nil, taxi_cost: nil, paths: []}

  # The pages print `paths` as a list. Anything else is answered with no paths rather
  # than a crash, the way the mappers treat the other shapes Amap leaves open.
  defp paths(payload) do
    case payload["paths"] do
      paths when is_list(paths) -> paths
      _other -> []
    end
  end
end
