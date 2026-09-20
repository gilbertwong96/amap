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
  - `:avoidpolygons`: at most 32 regions of at most 16 points each, **longitude first**
    (经度在前，纬度在后) — the same limits and the same order on both pages;
  - the four fields a `route` object carries before either version wraps them in a
    struct: the two endpoints decoded into tuples, the taxi cost, and the raw `paths`.

  The last one lives here because the two `Route` structs are not the same type: v3 and
  v5 name a step's fields differently, so each generation builds its own struct out of
  these values rather than sharing one — which is also AGENTS.md's rule for a helper
  that touches a struct it does not own.

  The v3-shaped mappers (`v3_path/1`, `v3_walking/1`, `v3_stop/1`, `v3_buslines/1`,
  `v3_railway/1`) live here for the mirror reason: v5's transit page documents its
  `walking`, `bus` and `railway` parts as 参考 v3 老接口, so those parts of a v5 answer
  really are v3's shapes, and one set of functions maps them for both generations rather
  than each module keeping a copy that would drift.
  """

  alias Amap.{Coord, Param, Validate}

  @max_waypoints 16
  @max_avoid_regions 32
  @max_avoid_vertices 16

  @cartypes %{fuel: "0", electric: "1", hybrid: "2"}

  @doc """
  Encodes the `:avoidpolygons` option, longitude first.

  Both pages document the same limits — at most 32 regions of at most 16 points each —
  and both need 经度在前，纬度在后. `Amap.Param.polygon_lon_first/1` is the encoder;
  `Amap.Param.polygon/1` is latitude-first and belongs to Falcon's search endpoints,
  where the same code would transpose every vertex without the request failing.
  """
  @spec avoidpolygons(Validate.input()) :: String.t() | nil
  def avoidpolygons(nil), do: nil

  def avoidpolygons(rings) do
    rings
    |> Validate.polygons!(":avoidpolygons", @max_avoid_regions, @max_avoid_vertices)
    |> Param.polygon_lon_first()
  end

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
  knows which fields one of its `paths` entries has. A `null` entry the wire sends in
  place of a path is dropped, so this list never holds a `nil`.
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
  # Amap writes a path it could not build as a literal `null` inside the list, and a
  # mapper answers that with `nil` — so the entry is dropped here rather than landing in
  # `Route.paths`, whose type is a list of paths and never a list with a hole in it. Both
  # generations get this from the one line, which is why it lives in the shared mapper.
  @spec route_fields(Amap.JSON.value(), (Amap.JSON.value() -> path | nil)) :: route_fields(path)
        when path: var
  def route_fields(payload, path_mapper) do
    values = route_values(payload)

    [
      origin: values.origin,
      destination: values.destination,
      taxi_cost: values.taxi_cost,
      paths: values.paths |> Enum.map(path_mapper) |> Enum.reject(&is_nil/1)
    ]
  end

  @spec route_values(Amap.JSON.value()) :: route_values()
  defp route_values(nil), do: empty_route()
  defp route_values(payload) when is_map(payload), do: read_route(payload)
  defp route_values(_other), do: empty_route()

  # The declared `route_values()` intermediate, deliberately not either generation's
  # `Route` struct: the doc on `route_fields/2` says why a shared module must not hold
  # one generation's fields for both. reach.check reads this map as a duplicate of the
  # two structs; the four names are the wire's, and both structs are built from these
  # values by the modules that own them.
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

  @doc """
  Maps a v3-shaped path — v3's own `paths[]`, and the shape v5's transit page documents
  参考 v3 老接口 for a segment's `walking` leg.

  It builds `Amap.Direction.Path`, because that is whose shape it is: v5 renames a step's
  fields, so v5's own paths have a different struct, but the parts v5 inherits from v3 are
  v3's and are mapped here rather than in either module.

  `nil` means Amap returned no path at all, and it stays `nil` rather than becoming an
  all-nil struct a truthiness check would accept — the same discipline `v3_walking/1`
  and `v3_railway/1` keep for their own absent objects.
  """
  @spec v3_path(Amap.JSON.value()) :: Amap.Direction.Path.t() | nil
  def v3_path(nil), do: nil

  def v3_path(payload) do
    %Amap.Direction.Path{
      distance: payload["distance"],
      duration: payload["duration"],
      strategy: payload["strategy"],
      tolls: payload["tolls"],
      restriction: payload["restriction"],
      traffic_lights: payload["traffic_lights"],
      toll_distance: payload["toll_distance"],
      steps: Enum.map(payload["steps"] || [], &v3_step/1),
      tmcs: Enum.map(payload["tmcs"] || [], &v3_tmc/1),
      cities: v3_cities(payload["cities"]),
      districts: v3_districts(payload["districts"]),
      roads: Enum.map(payload["roads"] || [], &v3_road/1)
    }
  end

  @doc """
  Maps a v3-shaped walking leg — the `walking` object inside a transit segment.

  It builds `Amap.Direction.Transit.Walking` rather than `Amap.Direction.Path`, because
  this leg carries its own `origin` and `destination`: a walk is between two points on a
  plan, while a `Path` gets its endpoints from the `route` around it. Its `steps` are the
  v3 step shape, so the same mapper `v3_path/1` uses fills them.

  `nil` means Amap sent no walking leg at all — a segment that starts on the bus has
  none — and it stays `nil`, as an absent group does beside `v3_stop/1` and
  `v3_railway/1`. A caller that gets a struct back can read it; one that gets `nil`
  knows there was no leg.
  """
  @spec v3_walking(Amap.JSON.value()) :: Amap.Direction.Transit.Walking.t() | nil
  def v3_walking(nil), do: nil

  def v3_walking(payload) do
    %Amap.Direction.Transit.Walking{
      origin: Coord.parse_location(payload["origin"]),
      destination: Coord.parse_location(payload["destination"]),
      distance: payload["distance"],
      duration: payload["duration"],
      steps: Enum.map(payload["steps"] || [], &v3_step/1)
    }
  end

  defp v3_step(payload) do
    %Amap.Direction.Step{
      instruction: payload["instruction"],
      road: payload["road"],
      distance: payload["distance"],
      orientation: payload["orientation"],
      duration: payload["duration"],
      polyline: Coord.parse_locations(payload["polyline"]),
      action: payload["action"],
      assistant_action: payload["assistant_action"],
      walk_type: payload["walk_type"],
      tolls: payload["tolls"],
      toll_distance: payload["toll_distance"],
      toll_road: payload["toll_road"],
      cities: v3_cities(payload["cities"]),
      tmcs: Enum.map(payload["tmcs"] || [], &v3_tmc/1)
    }
  end

  defp v3_tmc(payload) do
    %Amap.Direction.Tmc{
      distance: payload["distance"],
      status: payload["status"],
      polyline: Coord.parse_locations(payload["polyline"])
    }
  end

  # The helpers stay total: a value that is not a list answers `[]`, and a list holding
  # something that is not an object drops that element - a malformed entry loses itself,
  # not the city or the path around it. That filtering is also why the mappers below carry
  # no clause for another shape: only an object ever reaches one.
  defp v3_city(payload) when is_map(payload) do
    %Amap.Direction.City{
      name: payload["name"],
      citycode: payload["citycode"],
      adcode: payload["adcode"],
      districts: v3_districts(payload["districts"])
    }
  end

  defp v3_cities(list) when is_list(list),
    do: list |> Enum.filter(&is_map/1) |> Enum.map(&v3_city/1)

  defp v3_cities(_other), do: []

  defp v3_districts(list) when is_list(list),
    do: list |> Enum.filter(&is_map/1) |> Enum.map(&v3_district/1)

  defp v3_districts(_other), do: []

  defp v3_district(payload) when is_map(payload),
    do: %Amap.Direction.District{name: payload["name"], adcode: payload["adcode"]}

  defp v3_road(payload) do
    %Amap.Direction.Road{
      road_distance: payload["road_distance"],
      road_name: payload["road_name"],
      steps: Enum.map(payload["steps"] || [], &v3_step/1),
      traffic_lights: payload["traffic_lights"]
    }
  end

  @doc """
  Maps a v3-shaped station: a bus stop, a train stop, or a segment's entrance or exit.

  The three share one struct, so nothing is decided here — an entrance simply arrives
  with `name` and `location` and the rest `nil`.
  """
  @spec v3_stop(Amap.JSON.value()) :: Amap.Direction.Transit.Stop.t() | nil
  def v3_stop(nil), do: nil

  def v3_stop(payload) do
    %Amap.Direction.Transit.Stop{
      name: payload["name"],
      id: payload["id"],
      location: Coord.parse_location(payload["location"]),
      adcode: payload["adcode"],
      time: payload["time"],
      start: payload["start"],
      end: payload["end"],
      wait: payload["wait"]
    }
  end

  @doc """
  Maps a v3-shaped `bus` object into the list of lines it wraps.

  Amap nests the lines one level deeper (`bus.buslines`) and the wrapper holds nothing
  else, so the list itself is what a segment carries.
  """
  @spec v3_buslines(Amap.JSON.value()) :: [Amap.Direction.Transit.Busline.t()]
  def v3_buslines(nil), do: []
  def v3_buslines(payload), do: Enum.map(payload["buslines"] || [], &v3_busline/1)

  defp v3_busline(payload) do
    %Amap.Direction.Transit.Busline{
      departure_stop: v3_stop(payload["departure_stop"]),
      arrival_stop: v3_stop(payload["arrival_stop"]),
      name: payload["name"],
      id: payload["id"],
      type: payload["type"],
      distance: payload["distance"],
      duration: payload["duration"],
      polyline: Coord.parse_locations(payload["polyline"]),
      start_time: payload["start_time"],
      end_time: payload["end_time"],
      station_start_time: payload["station_start_time"],
      station_end_time: payload["station_end_time"],
      via_num: payload["via_num"],
      via_stops: Enum.map(payload["via_stops"] || [], &v3_stop/1)
    }
  end

  @doc """
  Maps a v3-shaped `railway` object — the train a leg rides.

  `via_stop` and `alters` are what Amap sends only when the call asked for
  `extensions: :all`, and both simply arrive empty otherwise.
  """
  @spec v3_railway(Amap.JSON.value()) :: Amap.Direction.Transit.Railway.t() | nil
  def v3_railway(nil), do: nil

  def v3_railway(payload) do
    %Amap.Direction.Transit.Railway{
      id: payload["id"],
      time: payload["time"],
      name: payload["name"],
      trip: payload["trip"],
      distance: payload["distance"],
      type: payload["type"],
      departure_stop: v3_stop(payload["departure_stop"]),
      arrival_stop: v3_stop(payload["arrival_stop"]),
      via_stop: Enum.map(payload["via_stop"] || [], &v3_stop/1),
      alters: Enum.map(payload["alters"] || [], &v3_alter/1)
    }
  end

  defp v3_alter(payload) do
    %Amap.Direction.Transit.Alter{
      id: payload["id"],
      name: payload["name"],
      spaces: Enum.map(payload["spaces"] || [], &v3_space/1)
    }
  end

  defp v3_space(payload),
    do: %Amap.Direction.Transit.Space{code: payload["code"], cost: payload["cost"]}
end
