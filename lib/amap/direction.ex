defmodule Amap.Direction do
  @moduledoc """
  路径规划 — planning a way from one coordinate to another.

  Amap's v3 page (`guide/api/direction`). `walking/4` plans on foot, at most
  **100 km**; `driving/4` plans by car, and is the endpoint that fills in the fields
  the structs mark as driving's own: the taxi cost, the tolls, the traffic lights,
  the 限行 answer a plate implies, and the traffic flow along the way.

  Both ends go in as `{lon, lat}` tuples and come back the same way — including
  every step's `polyline`, which Amap writes as one `;`-separated string and this
  module decodes into tuples, so no caller has to split it.
  """

  alias Amap.Coord
  alias Amap.Direction.City
  alias Amap.Direction.District
  alias Amap.Direction.Path
  alias Amap.Direction.Route
  alias Amap.Direction.Step
  alias Amap.Direction.Tmc
  alias Amap.Param
  alias Amap.Validate

  @walking_path "/v3/direction/walking"
  @driving_path "/v3/direction/driving"

  @max_origin_pairs 3
  @max_waypoints 16
  @max_avoid_regions 32
  @max_avoid_vertices 16

  # Amap documents 0 as 普通汽车, 1 as 纯电动 and 2 as 插电混动.
  @cartypes %{fuel: "0", electric: "1", hybrid: "2"}

  @doc """
  Plans a walking route.

  `origin` and `destination` are `{lon, lat}` tuples, at most six decimals.
  **Amap plans walking routes up to 100 km**; a longer pair is refused by the
  service rather than by this module.

  `:origin_id` and `:destination_id` are the POI ids of the two ends when they are
  known POIs, which Amap says improves the plan's accuracy. Note the underscores:
  this endpoint's page spells them `origin_id`/`destination_id`, while the driving
  endpoint's spells the same two parameters `originid`/`destinationid`.

  Returns the route Amap planned, or `%Amap.Direction.Route{paths: []}` when it
  found none — an answer with no `route` in it is not an error, and callers should
  not have to branch on a `nil` to enumerate paths. The number Amap also sends is
  not carried, since its length is the same thing.
  """
  @spec walking(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def walking(client, origin, destination, opts \\ []) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      origin_id: optional_present(opts, :origin_id),
      destination_id: optional_present(opts, :destination_id)
    ]

    case Amap.request(client, :restapi, :get, @walking_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Plans a driving route.

  `origin` is one `{lon, lat}` tuple or **up to three of them**. Amap plans from the
  last pair and takes the 抓路 angle — the direction the car was pointing — from the
  first to the last, which is how a caller says "the fix drifted, this is the line
  I was on" rather than "I was here". Each pair must be more than 2 m from the next,
  and Amap admits that past 4 m the angle is a guess.

  `:strategy` is an integer 0–20. The lower half (0–9) returns one route, the upper
  (10–20) several, and Amap recommends the upper — `10` is its own app's default
  behaviour and it suggests using it in place of `11`. `:waypoints` are up to 16
  intermediate `{lon, lat}` pairs, planned in the order given, and `:avoidpolygons`
  up to 32 regions of up to 16 points each, `|` between regions and `;` inside one.
  **A region whose area exceeds 81 km² is silently ignored by Amap**, which this
  module cannot check.

  A plate is two options here — `:province` (京) and `:number` (NH1N11, upper case,
  6 or 7 characters) — and what they buy is 限行 avoidance, reported per path in
  `restriction`. `:cartype` is `:fuel` (the default), `:electric` or `:hybrid`.
  `:ferry` is `:use` (the default: the wire's `0` means *take* the ferry) or
  `:avoid`; the option is named after the intent so that `0` never reads as "off".
  `:roadaggregation` adds a `roads` grouping above `steps` and travels as the text
  `true`; `:nosteps` keeps the step list empty if only the totals are wanted; and
  `:extensions` is `:base` or `:all` — only `all` carries the `tmcs`, `cities` and
  `districts` this module also maps. The page's parameter table marks `extensions`
  required while its own sample says otherwise, so it is sent only when given.

  `:origin_id`, `:destination_id` and `:destination_type` are the POI ids and the
  destination's POI category, and reach the wire without underscores — this is the
  endpoint that spells them `originid`/`destinationid`/`destinationtype`.

  Returns what `walking/4` returns, with the driving fields filled: `taxi_cost` on
  the route, and per path the strategy, tolls, lights and limit rules above.
  """
  @spec driving(
          Amap.Client.t(),
          {number(), number()} | [{number(), number()}],
          {number(), number()},
          keyword()
        ) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def driving(client, origin, destination, opts \\ []) do
    params = [
      origin: encode_origin!(origin),
      destination: Param.location(Validate.point!(destination, ":destination")),
      originid: optional_present(opts, :origin_id),
      destinationid: optional_present(opts, :destination_id),
      destinationtype: optional_present(opts, :destination_type),
      strategy: Validate.optional_range!(Keyword.get(opts, :strategy), ":strategy", 0, 20),
      waypoints: encode_waypoints(opts),
      avoidpolygons: encode_avoidpolygons(opts),
      province: optional_present(opts, :province),
      number: optional_present(opts, :number),
      cartype: optional_cartype(opts),
      ferry: optional_ferry(opts),
      roadaggregation: optional_boolean(opts, :roadaggregation, :bool),
      nosteps: optional_boolean(opts, :nosteps, :int),
      extensions:
        Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all])
    ]

    case Amap.request(client, :restapi, :get, @driving_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  defp optional_present(opts, key) do
    Validate.optional!(&Validate.present!/2, Keyword.get(opts, key), ":#{key}")
  end

  # A single pair is the common case; a list is the 定位飘点 form, where only the
  # last pair is planned and the bearing from the first to it sets the 抓路 angle.
  defp encode_origin!(origin) do
    case origin do
      {_lon, _lat} ->
        Param.location(Validate.point!(origin, ":origin"))

      pairs when is_list(pairs) ->
        pairs = Validate.points!(pairs, ":origin")

        if length(pairs) > @max_origin_pairs do
          raise ArgumentError,
                ":origin must be at most #{@max_origin_pairs} coordinate pairs, got: #{length(pairs)}"
        end

        Enum.map_join(pairs, "|", &Param.location/1)

      other ->
        raise ArgumentError,
              ":origin must be a {lon, lat} pair of numbers, got: #{inspect(other)}"
    end
  end

  defp encode_waypoints(opts) do
    case Keyword.get(opts, :waypoints) do
      nil ->
        nil

      pairs ->
        pairs = Validate.points!(pairs, ":waypoints")

        if length(pairs) > @max_waypoints do
          raise ArgumentError,
                ":waypoints must be at most #{@max_waypoints} coordinate pairs, got: #{length(pairs)}"
        end

        Param.locations(pairs)
    end
  end

  # 经度在前，纬度在后, the order `Param.location/1` writes and the one this
  # parameter's own rules give — *not* `Param.polygon/1`, which is latitude-first
  # for the Falcon search endpoints and would swap every coordinate here.
  defp encode_avoidpolygons(opts) do
    case Keyword.get(opts, :avoidpolygons) do
      nil ->
        nil

      rings ->
        rings
        |> validate_rings!()
        |> Enum.map_join("|", fn ring -> Enum.map_join(ring, ";", &Param.location/1) end)
    end
  end

  defp validate_rings!(rings) when is_list(rings) and rings != [] do
    if length(rings) > @max_avoid_regions do
      raise ArgumentError,
            ":avoidpolygons must be at most #{@max_avoid_regions} regions, got: #{length(rings)}"
    end

    Enum.map(rings, &validate_ring!/1)
  end

  defp validate_rings!(other) do
    raise ArgumentError,
          ":avoidpolygons must be a non-empty list of regions, got: #{inspect(other)}"
  end

  defp validate_ring!(ring) do
    points = Validate.points!(ring, ":avoidpolygons ring")

    if length(points) > @max_avoid_vertices do
      raise ArgumentError,
            ":avoidpolygons ring must be at most #{@max_avoid_vertices} vertices, got: #{length(points)}"
    end

    points
  end

  defp optional_cartype(opts) do
    case Keyword.get(opts, :cartype) do
      nil ->
        nil

      value when is_map_key(@cartypes, value) ->
        Map.fetch!(@cartypes, value)

      other ->
        raise ArgumentError,
              ":cartype must be one of #{inspect(Map.keys(@cartypes))}, got: #{inspect(other)}"
    end
  end

  defp optional_ferry(opts) do
    case Keyword.get(opts, :ferry) do
      nil -> nil
      :use -> "0"
      :avoid -> "1"
      other -> raise ArgumentError, ":ferry must be one of [:use, :avoid], got: #{inspect(other)}"
    end
  end

  defp optional_boolean(opts, key, as) do
    case Keyword.get(opts, key) do
      nil ->
        nil

      value when is_boolean(value) ->
        Param.boolean(value, as: as)

      other ->
        raise ArgumentError, ":#{key} must be a boolean, got: #{inspect(other)}"
    end
  end

  # Amap leaves `route` out entirely when it found nothing, which is an answer
  # rather than a failure: callers get an empty Route instead of a nil to branch on.
  defp to_route(nil), do: %Route{paths: []}

  defp to_route(payload) do
    %Route{
      origin: Coord.parse_location(payload["origin"]),
      destination: Coord.parse_location(payload["destination"]),
      taxi_cost: payload["taxi_cost"],
      paths: Enum.map(payload["paths"] || [], &to_path/1)
    }
  end

  defp to_path(payload) do
    %Path{
      distance: payload["distance"],
      duration: payload["duration"],
      strategy: payload["strategy"],
      tolls: payload["tolls"],
      restriction: payload["restriction"],
      traffic_lights: payload["traffic_lights"],
      toll_distance: payload["toll_distance"],
      steps: Enum.map(payload["steps"] || [], &to_step/1),
      tmcs: Enum.map(payload["tmcs"] || [], &to_tmc/1),
      cities: Enum.map(payload["cities"] || [], &to_city/1),
      districts: Enum.map(payload["districts"] || [], &to_district/1)
    }
  end

  defp to_step(payload) do
    %Step{
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
      tmcs: Enum.map(payload["tmcs"] || [], &to_tmc/1)
    }
  end

  defp to_tmc(payload) do
    %Tmc{
      distance: payload["distance"],
      status: payload["status"],
      polyline: Coord.parse_locations(payload["polyline"])
    }
  end

  defp to_city(payload) do
    %City{
      name: payload["name"],
      citycode: payload["citycode"],
      adcode: payload["adcode"],
      districts: Enum.map(payload["districts"] || [], &to_district/1)
    }
  end

  defp to_district(payload) do
    %District{name: payload["name"], adcode: payload["adcode"]}
  end
end
