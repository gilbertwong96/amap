defmodule Amap.Direction do
  @moduledoc """
  路径规划 — planning a way from one coordinate to another.

  Amap's v3 page (`guide/api/direction`). `walking/4` plans on foot, at most
  **100 km**; `driving/4` plans by car, and is the endpoint that fills in the fields
  the structs mark as driving's own: the taxi cost, the tolls, the traffic lights,
  the 限行 answer a plate implies, and the traffic flow along the way. `transit/5`
  plans by public transport, where the answer is a list of ways to make the trip and
  each of those is a list of legs. `distance/4` is the odd one out: it plans nothing —
  it measures how far each of up to a hundred origins is from one destination, which is
  why every result carries a per-item `code` and why it lives on its own path
  (`/v3/distance`, not `/v3/direction/…`). `bicycling/4` is the second odd one out:
  the page documents it, it is the only endpoint here that is not `/v3/`, and it is
  the only one that answers the **track family's** envelope while living on the Web
  service host — the reason `family` and `host` are two axes and not one.

  Both ends go in as `{lon, lat}` tuples and come back the same way — including
  every step's `polyline`, which Amap writes as one `;`-separated string and this
  module decodes into tuples, so no caller has to split it.
  """

  alias Amap.Coord
  alias Amap.Direction.Distance
  alias Amap.Direction.Route
  alias Amap.Direction.Transit
  alias Amap.Direction.Transit.Plan
  alias Amap.Direction.Transit.Segment
  alias Amap.Param
  alias Amap.Routing
  alias Amap.Validate

  @walking_path "/v3/direction/walking"
  @driving_path "/v3/direction/driving"
  @transit_path "/v3/direction/transit/integrated"
  @distance_path "/v3/distance"
  @bicycling_path "/v4/direction/bicycling"

  @max_origin_pairs 3
  @max_origins 100

  # Amap documents 0/1/2/3/5 for this endpoint — not a range, and no 4.
  @transit_strategies [0, 1, 2, 3, 5]

  # 0 the straight line, 1 the driving distance (Amap's own default), 3 walking.
  @distance_types [0, 1, 3]

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
      origin_id: Validate.optional_present!(Keyword.get(opts, :origin_id), ":origin_id"),
      destination_id:
        Validate.optional_present!(Keyword.get(opts, :destination_id), ":destination_id")
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
  One region may be given on its own instead of a list of them, since a ring of points
  and a list of rings cannot be confused. **A region whose area exceeds 81 km² is
  silently ignored by Amap**, which this module cannot check.

  A plate is two options here — `:province` (京) and `:number` (NH1N11, upper case,
  6 or 7 characters) — and what they buy is 限行 avoidance, reported per path in
  `restriction`. `:cartype` is `:fuel` (the default), `:electric` or `:hybrid`.
  `:ferry` is `:use` (the default: the wire's `0` means *take* the ferry) or
  `:avoid`; the option is named after the intent so that `0` never reads as "off".
  `:roadaggregation` asks Amap to aggregate the route by road and travels as the text
  `true`; **it replaces `steps` with `roads` rather than adding a grouping above them** —
  the page words it as 在 `steps` 上层增加 `roads` 做聚合, but the live run saw a path whose
  keys held `roads` and no `steps` at all, so a caller who sets the flag reads the route
  from `Amap.Direction.Path`'s `roads` and `steps` stays empty. `:nosteps` keeps the step
  list empty if only the totals are wanted; and `:extensions` is `:base` or `:all` — only `all` carries the `tmcs`,
  `cities` and `districts` this module also maps. The page's parameter table marks
  `extensions` required while its own sample says otherwise, so it is sent only when
  given.

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
      originid: Validate.optional_present!(Keyword.get(opts, :origin_id), ":origin_id"),
      destinationid:
        Validate.optional_present!(Keyword.get(opts, :destination_id), ":destination_id"),
      destinationtype:
        Validate.optional_present!(Keyword.get(opts, :destination_type), ":destination_type"),
      strategy: Validate.optional_range!(Keyword.get(opts, :strategy), ":strategy", 0, 20),
      waypoints: Routing.waypoints(Keyword.get(opts, :waypoints)),
      avoidpolygons: Routing.avoidpolygons(Keyword.get(opts, :avoidpolygons)),
      province: Validate.optional_present!(Keyword.get(opts, :province), ":province"),
      number: Validate.optional_present!(Keyword.get(opts, :number), ":number"),
      cartype: Routing.cartype(Keyword.get(opts, :cartype)),
      ferry: Routing.ferry(Keyword.get(opts, :ferry)),
      roadaggregation:
        Validate.optional_boolean!(Keyword.get(opts, :roadaggregation), ":roadaggregation",
          as: :bool
        ),
      nosteps: Validate.optional_boolean!(Keyword.get(opts, :nosteps), ":nosteps", as: :int),
      extensions:
        Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all])
    ]

    case Amap.request(client, :restapi, :get, @driving_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Plans a public transport route.

  `city` is the city the trip starts in — a name, or a `citycode` like `"010"` — and
  is required, because Amap cannot search a network it has not been told to search.
  `:cityd` names the city the trip ends in and is for a 跨城 trip only.

  `:strategy` is one of Amap's five: `0` 最快捷 (its own default when none is given),
  `1` 最经济, `2` 最少换乘, `3` 最少步行 and `5` 不乘地铁. **The values are not a range —
  there is no 4.** `:nightflag` asks Amap to consider 夜班车 as well, and travels as
  `1`/`0`.

  `:date` and `:time` take a `Date` and a `Time` and say when the caller means to
  travel; Amap then answers with what still runs at that hour. **The page says twice
  not to send them unless a scheduled departure is what you mean**, so both stay out
  of the request unless given.

  Returns the plans Amap offers, ranked, as an `Amap.Direction.Transit`; a trip it
  cannot plan comes back with `transits: []` rather than an error. Trains arrive as
  `railway` legs, whose `via_stop` and `alters` need `extensions: :all`.
  """
  @spec transit(
          Amap.Client.t(),
          {number(), number()},
          {number(), number()},
          String.t(),
          keyword()
        ) ::
          {:ok, Transit.t()} | {:error, Amap.Error.t()}
  def transit(client, origin, destination, city, opts \\ []) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      city: Validate.present!(city, ":city"),
      cityd: Validate.optional_present!(Keyword.get(opts, :cityd), ":cityd"),
      extensions:
        Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all]),
      strategy:
        Validate.integer_one_of!(Keyword.get(opts, :strategy), ":strategy", @transit_strategies),
      nightflag:
        Validate.optional_boolean!(Keyword.get(opts, :nightflag), ":nightflag", as: :int),
      date: Validate.optional_date!(Keyword.get(opts, :date), ":date"),
      time: Validate.optional_time!(Keyword.get(opts, :time), ":time")
    ]

    case Amap.request(client, :restapi, :get, @transit_path, params) do
      {:ok, payload} -> {:ok, to_transit(payload["route"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Measures how far each of several origins is from one destination.

  The asymmetry is the endpoint: `origins` is a list of one to **100** `{lon, lat}`
  tuples and `destination` is a single one, and the answers arrive in the order the
  origins were given — each result's `origin_id` is that order's 1-based number.

  `:type` says how to measure: `0` the straight line, `1` the driving distance —
  Amap's own default, so it is sent only when named — or `3` the walking distance,
  for points no more than 5 km apart. **`1` is a route, not a ruler**: it reads the
  traffic when it runs, so the same pair of points can answer differently at two times
  of day.

  A result Amap could not measure carries its own `info` and `code`, and the call is
  still `{:ok, [...]}` — across a hundred origins a failure is data rather than an
  error. `Amap.Direction.Distance` says what each code means.
  """
  @spec distance(
          Amap.Client.t(),
          [{number(), number()}],
          {number(), number()},
          keyword()
        ) ::
          {:ok, [Distance.t()]} | {:error, Amap.Error.t()}
  def distance(client, origins, destination, opts \\ []) do
    origins = Validate.points!(origins, ":origins")

    Validate.range!(length(origins), ":origins count", 1, @max_origins)

    params = [
      origins: Param.pipe(Enum.map(origins, &Param.location/1)),
      destination: Param.location(Validate.point!(destination, ":destination")),
      type: Validate.integer_one_of!(Keyword.get(opts, :type), ":type", @distance_types)
    ]

    case Amap.request(client, :restapi, :get, @distance_path, params) do
      {:ok, payload} -> {:ok, to_distances(payload["results"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Plans a cycling route, at most **500 km**.

  This endpoint is why `family` and `host` are two axes rather than one. Amap
  documents it on the same page as the four above, but it answers
  `{errcode, errmsg, errdetail, data}` — the **track family's** envelope, not the
  `{status, info, infocode}` the rest of this page uses — and it lives on
  `restapi.amap.com` all the same. So the call names the family that parses and signs
  (`:tsapi`, which signs nothing, since this page documents no `sig`) and names the
  host separately. `/v4/grasproad/driving` is the second endpoint of that kind, which
  is why §10 #10 of the design doc calls this a property of `/v4/` rather than one
  accident.

  It takes nothing but the two ends: the page documents only `key`, `origin` and
  `destination` — no POI ids, no strategy, nothing optional — so the keyword list
  exists for the shape the other four share and carries nothing.

  Returns the route Amap planned, or `%Amap.Direction.Route{paths: []}` when it found
  none, as `walking/4` does.
  """
  @spec bicycling(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def bicycling(client, origin, destination, _opts \\ []) do
    # A Falcon envelope on the Web service host: `:tsapi` decides the envelope and
    # signing, `host: :restapi` decides where the request goes.
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination"))
    ]

    case Amap.request(client, :tsapi, :get, @bicycling_path, params, host: :restapi) do
      {:ok, payload} -> {:ok, to_route(payload)}
      {:error, _} = error -> error
    end
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

  # Amap leaves `route` out entirely when it found nothing, which is an answer
  # rather than a failure: `Amap.Routing` reads that as empty endpoints and no paths,
  # so callers get an empty Route instead of a nil to branch on.
  defp to_route(payload), do: struct(Route, Routing.route_fields(payload, &Routing.v3_path/1))

  # The page prints both `results` and `result` for this list, the way driving's page
  # prints both `paths` and `path`; read whichever arrived.
  defp to_distances(%{"result" => nested}), do: to_distances(nested)
  defp to_distances(results) when is_list(results), do: Enum.map(results, &to_distance/1)
  defp to_distances(_other), do: []

  defp to_distance(payload) do
    %Distance{
      origin_id: payload["origin_id"],
      dest_id: payload["dest_id"],
      distance: payload["distance"],
      duration: payload["duration"],
      info: payload["info"],
      code: payload["code"]
    }
  end

  # Same as the other two endpoints: no `route` in the answer means Amap found no
  # plan, which is an answer rather than a failure.
  defp to_transit(nil), do: %Transit{transits: []}

  defp to_transit(payload) do
    %Transit{
      origin: Coord.parse_location(payload["origin"]),
      destination: Coord.parse_location(payload["destination"]),
      distance: payload["distance"],
      taxi_cost: payload["taxi_cost"],
      transits: Enum.map(payload["transits"] || [], &to_plan/1)
    }
  end

  defp to_plan(payload) do
    %Plan{
      cost: payload["cost"],
      duration: payload["duration"],
      nightflag: payload["nightflag"],
      walking_distance: payload["walking_distance"],
      segments: Enum.map(payload["segments"] || [], &to_segment/1)
    }
  end

  defp to_segment(payload) do
    %Segment{
      walking: Routing.v3_walking(payload["walking"]),
      bus: Routing.v3_buslines(payload["bus"]),
      entrance: Routing.v3_stop(payload["entrance"]),
      exit: Routing.v3_stop(payload["exit"]),
      railway: Routing.v3_railway(payload["railway"])
    }
  end
end
