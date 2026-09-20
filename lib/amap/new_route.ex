defmodule Amap.NewRoute do
  @moduledoc """
  路径规划 2.0 — planning a way from one coordinate to another, on Amap's v5 pages.

  Amap's newer routing service (`guide/api/newroute`). It asks the same question as
  `Amap.Direction`'s v3 pages and answers with different parameters, differently named
  fields and a different set of strategies, so the two are separate modules with
  separate structs rather than one module with two modes.

  Two things belong to v5 alone. **`:show_fields`** names the optional groups a caller
  wants and Amap returns base fields only when it is unset; each endpoint refuses a group
  its own page does not list — six on driving (`cost`, `tmcs`, `navi`, `cities`,
  `district`, `polyline`) and four on walking, bicycling, electrobike and transit
  (`cost`, `navi`, `walk_type`, `polyline`) —
  because Amap would answer a request it silently ignored and the typo would look like an
  answer. Amap itself **ignores** an unknown group and answers `ok` with base fields (the
  live run confirmed it), so raising here is a deliberate, stricter choice.
  **The strategies are a different enum**: `0`, `1`, `2` and `32`–`45`,
  where `32` is Amap's own default and the rest are its app's combinations — v3's `10`,
  which means "give me several routes", is not one of them.

  `:avoidpolygons` is longitude-first here as everywhere on the Web service side
  (经度在前，纬度在后): `Amap.Param.polygon_lon_first/1` is the encoder, and
  `Amap.Param.polygon/1` — latitude-first, written for the Falcon search endpoints —
  would transpose every vertex without the request failing.
  """

  alias Amap.Coord
  alias Amap.NewRoute.City
  alias Amap.NewRoute.Cost
  alias Amap.NewRoute.District
  alias Amap.NewRoute.Navi
  alias Amap.NewRoute.Path
  alias Amap.NewRoute.Route
  alias Amap.NewRoute.Step
  alias Amap.NewRoute.Tmc
  alias Amap.NewRoute.Transit
  alias Amap.NewRoute.Transit.Cost, as: TransitCost
  alias Amap.NewRoute.Transit.Plan, as: TransitPlan
  alias Amap.NewRoute.Transit.Segment, as: TransitSegment
  alias Amap.NewRoute.Transit.Taxi
  alias Amap.Param
  alias Amap.Routing
  alias Amap.Validate

  @driving_path "/v5/direction/driving"
  @walking_path "/v5/direction/walking"
  @bicycling_path "/v5/direction/bicycling"
  @electrobike_path "/v5/direction/electrobike"
  @transit_path "/v5/direction/transit/integrated"

  # 0 速度优先, 1 费用优先, 2 常规最快, 32 高德推荐 — Amap's own default — and 33–45, its
  # app-style combinations. Not v3's 0–20: the same digits mean other things there.
  @strategies [0, 1, 2] ++ Enum.to_list(32..45)

  # 1 多备选路线中第一条, 2 前两条, 3 三条; unset returns one route.
  @alternative_routes [1, 2, 3]

  # Transit's own numbers again: 0 推荐, 1 最经济, 2 最少换乘, 3 最少步行, 4 最舒适,
  # 5 不乘地铁, 6 地铁图模式, 7 地铁优先, 8 时间短 — a contiguous run, and a different
  # meaning for every digit driving uses.
  @transit_strategies Enum.to_list(0..8)

  # This page spells its parameter with a capital A and takes 1–10, where the other v5
  # endpoints' lowercase `alternative_route` takes 1–3. Both are the page's own doing.
  @transit_alternative_routes Enum.to_list(1..10)

  # What each endpoint's 返回结果 section turns on, and nothing else: a group Amap does
  # not have comes back looking like base fields, so a typo is a call-site mistake.
  # Driving's page alone returns `tmcs`, `cities` and `district`; walking, bicycling,
  # electrobike and transit document the same four, so they share one list.
  @driving_show_fields ~w(cost tmcs navi cities district polyline)a
  @walking_riding_and_transit_show_fields ~w(cost navi walk_type polyline)a

  @doc """
  Plans a driving route.

  `origin` and `destination` are `{lon, lat}` tuples, at most six decimals. Unlike v3's
  driving endpoint the origin is **one** pair: the 定位飘点 form that takes up to three
  is v3's own, and this page does not document it.

  `:strategy` is `0` 速度优先, `1` 费用优先, `2` 常规最快, or one of `32`–`45` — `32`
  高德推荐 is Amap's default, so the parameter is sent only when named, and v3's `10` is
  refused rather than passed through. `:waypoints` are up to 16 intermediate pairs,
  planned in the order given, and `:avoidpolygons` up to 32 regions of up to 16 points
  each — given as one ring or a list of rings, **longitude first**. A region whose area
  exceeds 81 km² is ignored by Amap silently, which this module cannot check.

  `:plate` is the whole plate (京AHA322, six or seven characters), where v3's page
  splits the same information into `:province` and `:number`. `:cartype` is `:fuel` (the
  default), `:electric` or `:hybrid`, and `:ferry` is `:use` (the default: the wire's
  `0` means *take* the ferry) or `:avoid` — named after the intent, so that `0` never
  reads as "off".

  `:show_fields` names the optional groups to return, and a group that was not asked
  for leaves its fields `nil` — `tmcs` is the exception, a list that comes back `[]`
  either way, so an empty one cannot say whether it was asked for. The wire returns
  `cities` on a step rather than on the path, which is where `Amap.NewRoute.Step`
  reads it; `district` stays where its page puts it. `:method` is
  `:get`, the verb the page documents, or `:post`, which the page asks for when the
  parameters grow too long for a URL: the same parameters then travel as a form body,
  and the request is signed either way, because signing follows the host and envelope
  rather than the verb.

  Returns the route Amap planned, or `%Amap.NewRoute.Route{paths: []}` when it found
  none, as `Amap.Direction.walking/4` does.
  """
  @spec driving(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def driving(client, origin, destination, opts \\ []) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      origin_id: Validate.optional_present!(Keyword.get(opts, :origin_id), ":origin_id"),
      destination_id:
        Validate.optional_present!(Keyword.get(opts, :destination_id), ":destination_id"),
      destination_type:
        Validate.optional_present!(Keyword.get(opts, :destination_type), ":destination_type"),
      strategy: Validate.integer_one_of!(Keyword.get(opts, :strategy), ":strategy", @strategies),
      waypoints: Routing.waypoints(Keyword.get(opts, :waypoints)),
      avoidpolygons: Routing.avoidpolygons(Keyword.get(opts, :avoidpolygons)),
      plate: Validate.optional_present!(Keyword.get(opts, :plate), ":plate"),
      cartype: Routing.cartype(Keyword.get(opts, :cartype)),
      ferry: Routing.ferry(Keyword.get(opts, :ferry)),
      show_fields:
        Validate.optional_show_fields!(
          Keyword.get(opts, :show_fields),
          ":show_fields",
          @driving_show_fields
        )
    ]

    method = validate_method!(Keyword.get(opts, :method))

    case Amap.request(client, :restapi, method, @driving_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Plans a walking route.

  The same two `{lon, lat}` points as `driving/4`, and Amap's answer is the same skeleton
  without `restriction` and `taxi_cost`, plus `walk_type` — a road-type code Amap sends
  inside a step's `navi` object, even though its `show_fields` group shares the field's
  name.

  `:alternative_route` takes `1`, `2` or `3` — the first of several routes, the first
  two, or three — and unset returns one, so it is sent only when named. `:isindoor` is
  `0` or `1` on the wire, where `1` asks for indoor routing.

  `:show_fields` names this endpoint's four groups: `cost`, `navi`, `walk_type` and
  `polyline`. Asking for one of driving's instead is a call-site mistake and raises,
  because Amap would answer it with base fields and no complaint.

  Returns the route Amap planned, or `%Amap.NewRoute.Route{paths: []}` when it found none.
  """
  @spec walking(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def walking(client, origin, destination, opts \\ []) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      origin_id: Validate.optional_present!(Keyword.get(opts, :origin_id), ":origin_id"),
      destination_id:
        Validate.optional_present!(Keyword.get(opts, :destination_id), ":destination_id"),
      alternative_route:
        Validate.integer_one_of!(
          Keyword.get(opts, :alternative_route),
          ":alternative_route",
          @alternative_routes
        ),
      isindoor: Validate.optional_boolean!(Keyword.get(opts, :isindoor), ":isindoor", as: :int),
      show_fields:
        Validate.optional_show_fields!(
          Keyword.get(opts, :show_fields),
          ":show_fields",
          @walking_riding_and_transit_show_fields
        )
    ]

    case Amap.request(client, :restapi, :get, @walking_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Plans a cycling route.

  The same two `{lon, lat}` points as `walking/4`, the same answer skeleton, and the same
  `:alternative_route` and `:show_fields` values — the electrobike page's parameter list is
  this one's character for character, so the two functions differ only in where the request
  goes.

  `Amap.Direction.bicycling/4` asks the same question of the older `/v4/` page, which
  documents nothing but the two points and answers in the Falcon envelope.
  """
  @spec bicycling(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def bicycling(client, origin, destination, opts \\ []) do
    plan_ride(client, @bicycling_path, origin, destination, opts)
  end

  @doc """
  Plans an electric-bike route.

  v5's own endpoint: v3 has no equivalent. Its parameter list is `bicycling/4`'s and its
  answer is the same skeleton — what differs is Amap's planning, which 会考虑限行等条件,
  it weighs no-travel restrictions, where cycling does not.
  """
  @spec electrobike(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def electrobike(client, origin, destination, opts \\ []) do
    plan_ride(client, @electrobike_path, origin, destination, opts)
  end

  # These two pages document identical parameter lists, so the path is the only thing
  # that differs — it is the argument, and neither public function repeats this body.
  defp plan_ride(client, path, origin, destination, opts) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      alternative_route:
        Validate.integer_one_of!(
          Keyword.get(opts, :alternative_route),
          ":alternative_route",
          @alternative_routes
        ),
      show_fields:
        Validate.optional_show_fields!(
          Keyword.get(opts, :show_fields),
          ":show_fields",
          @walking_riding_and_transit_show_fields
        )
    ]

    case Amap.request(client, :restapi, :get, path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  defp validate_method!(nil), do: :get
  defp validate_method!(value) when value in [:get, :post], do: value

  defp validate_method!(other) do
    raise ArgumentError, ":method must be one of [:get, :post], got: #{inspect(other)}"
  end

  # Amap leaves `route` out entirely when it found nothing, which is an answer rather
  # than a failure: `Amap.Routing` reads that as empty endpoints and no paths, so
  # callers get an empty Route instead of a nil to branch on.
  #
  # `struct/2` rather than a literal because ExDNA counts the two generations' route
  # construction as one clone. The field names live in `Amap.Routing.route_fields/2`'s
  # return type, and a key it does not know about is dropped without complaint.
  defp to_route(payload), do: struct(Route, Routing.route_fields(payload, &to_path/1))

  # A path the wire sent as `null` — `Amap.Routing.route_fields/2` drops it rather than
  # letting an all-nil struct reach `Route.paths`.
  defp to_path(nil), do: nil

  defp to_path(payload) do
    %Path{
      distance: payload["distance"],
      restriction: payload["restriction"],
      cost: to_cost(payload["cost"]),
      tmcs: to_tmcs(payload["tmcs"]),
      navi: to_navi(payload["navi"]),
      cities: to_city(payload["cities"]),
      district: to_district(payload["district"]),
      polyline: Coord.parse_locations(payload["polyline"]),
      steps: Enum.map(payload["steps"] || [], &to_step/1)
    }
  end

  defp to_step(payload) do
    %Step{
      instruction: payload["instruction"],
      orientation: payload["orientation"],
      road_name: payload["road_name"],
      step_distance: payload["step_distance"],
      cost: to_cost(payload["cost"]),
      tmcs: to_tmcs(payload["tmcs"]),
      navi: to_navi(payload["navi"]),
      cities: to_step_cities(payload["cities"]),
      polyline: Coord.parse_locations(payload["polyline"])
    }
  end

  # The wire puts a step's `cities` on the step (the live run's step keys named it while
  # the path carried `cost` alone), and the third run printed what it holds there: a list
  # of the objects `Amap.NewRoute.City` documents. Anything else answers `nil` rather
  # than raising on a shape no source has shown.
  defp to_step_cities(nil), do: nil

  defp to_step_cities(payload) when is_list(payload) do
    if Enum.all?(payload, &is_map/1), do: Enum.map(payload, &to_city/1), else: nil
  end

  defp to_step_cities(_other), do: nil

  defp to_cost(nil), do: nil

  defp to_cost(payload) do
    %Cost{
      duration: payload["duration"],
      tolls: payload["tolls"],
      toll_distance: payload["toll_distance"]
    }
  end

  # The page prints this group as one object and does not say which level it hangs
  # from, so all three shapes it could take are read the way `Amap.Direction` reads the
  # `results`/`result` pair on `/v3/distance`. The list form was wrong once: it mapped
  # with `to_tmc/1`, so a list of `tmc`-wrapped objects came back as one empty struct.
  defp to_tmcs(nil), do: []
  defp to_tmcs(list) when is_list(list), do: Enum.flat_map(list, &to_tmcs/1)
  defp to_tmcs(%{"tmc" => nested}), do: to_tmcs(nested)
  defp to_tmcs(payload) when is_map(payload), do: [to_tmc(payload)]

  defp to_tmc(payload) do
    %Tmc{
      tmc_status: payload["tmc_status"],
      tmc_distance: payload["tmc_distance"],
      tmc_polyline: Coord.parse_locations(payload["tmc_polyline"])
    }
  end

  defp to_navi(nil), do: nil

  defp to_navi(payload) do
    %Navi{
      action: payload["action"],
      assistant_action: payload["assistant_action"],
      walk_type: payload["walk_type"]
    }
  end

  # The city mapper stays total: a shape it does not read answers `nil` rather than
  # raising, and a `districts` value that is not a list, or holds an element that is not
  # an object, drops that value - a malformed element loses itself, not the city around
  # it, which is the tolerance `to_tmcs/1` keeps too.
  defp to_city(payload) when is_map(payload) do
    %City{
      adcode: payload["adcode"],
      citycode: payload["citycode"],
      city: payload["city"],
      districts: to_districts(payload["districts"])
    }
  end

  defp to_city(_other), do: nil

  defp to_districts(list) when is_list(list),
    do: list |> Enum.filter(&is_map/1) |> Enum.map(&to_district/1)

  defp to_districts(_other), do: []

  defp to_district(payload) when is_map(payload),
    do: %District{name: payload["name"], adcode: payload["adcode"]}

  defp to_district(_other), do: nil

  @doc """
  Plans a public transport route.

  `city1` and `city2` are both required and positional — `city1` is the city the trip
  starts in, `city2` the one it ends in, 跨城 or not — and each takes a **citycode**
  (`"010"`), not a name. The page's 必填 column leaves `city2`'s cell empty while its own
  sample table says 是; the wire settles it the sample table's way, refusing a
  `city1`-only call with `20001 MISSING_REQUIRED_PARAMS`.

  `:strategy` is **a third enum**: `0` 推荐 (Amap's default), `1` 最经济, `2` 最少换乘,
  `3` 最少步行, `4` 最舒适, `5` 不乘地铁, `6` 地铁图模式, `7` 地铁优先 and `8` 时间短 —
  the digits driving uses mean other things entirely. Mode `6` has no other way to name a
  station, so it requires `:originpoi` and `:destinationpoi`.

  `:originpoi` and `:destinationpoi` **travel as a pair or not at all**: sending one alone
  is a call-site mistake and raises, because the page documents the POI id as overriding
  the coordinate it sits beside.

  `:alternative_route` is 1–10 here and reaches the wire as **`AlternativeRoute`**, with a
  capital A — this page's own spelling, against the lowercase `alternative_route` (1–3)
  the other v5 endpoints take. `:ad1`/`:ad2` are the start and end 行政区域编码, `:nightflag`
  asks for a 夜班车-aware plan, and `:date`/`:time` are sent only when a scheduled
  departure is wanted.

  `:show_fields` names this endpoint's four groups — `cost`, `navi`, `walk_type`,
  `polyline` — and the `cost` group splits across two levels here: `taxi_fee` arrives on
  the route, `transit_fee` under each segment, and `steps` never carry a cost at all.

  The `walking`, `bus` and `railway` parts of a segment keep v3's structs, because this
  page documents them as 参考 v3 老接口; `taxi` is v5's own.

  Returns the plans Amap found, or `%Amap.NewRoute.Transit{transits: []}` when it found
  none, the way `walking/4` answers an empty route.
  """
  @spec transit(
          Amap.Client.t(),
          {number(), number()},
          {number(), number()},
          String.t(),
          String.t(),
          keyword()
        ) ::
          {:ok, Transit.t()} | {:error, Amap.Error.t()}
  def transit(client, origin, destination, city1, city2, opts \\ []) do
    strategy =
      Validate.integer_one_of!(Keyword.get(opts, :strategy), ":strategy", @transit_strategies)

    originpoi = Validate.optional_present!(Keyword.get(opts, :originpoi), ":originpoi")

    destinationpoi =
      Validate.optional_present!(Keyword.get(opts, :destinationpoi), ":destinationpoi")

    reject_station_pair!(strategy, originpoi, destinationpoi)

    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      city1: Validate.present!(city1, ":city1"),
      city2: Validate.present!(city2, ":city2"),
      originpoi: originpoi,
      destinationpoi: destinationpoi,
      ad1: Validate.optional_present!(Keyword.get(opts, :ad1), ":ad1"),
      ad2: Validate.optional_present!(Keyword.get(opts, :ad2), ":ad2"),
      strategy: strategy,
      AlternativeRoute:
        Validate.integer_one_of!(
          Keyword.get(opts, :alternative_route),
          ":alternative_route",
          @transit_alternative_routes
        ),
      nightflag:
        Validate.optional_boolean!(Keyword.get(opts, :nightflag), ":nightflag", as: :int),
      date: Validate.optional_date!(Keyword.get(opts, :date), ":date"),
      time: Validate.optional_time!(Keyword.get(opts, :time), ":time"),
      show_fields:
        Validate.optional_show_fields!(
          Keyword.get(opts, :show_fields),
          ":show_fields",
          @walking_riding_and_transit_show_fields
        )
    ]

    case Amap.request(client, :restapi, :get, @transit_path, params) do
      {:ok, payload} -> {:ok, to_transit(payload["route"])}
      {:error, _} = error -> error
    end
  end

  # Two rules about the POI pair: it travels whole or not at all, and mode 6 地铁图模式 has
  # no coordinates to fall back on. Both are call-site mistakes, so both raise — and the
  # mode-6 messages name which of the two is missing, since saying "neither" while one
  # was given sends the caller looking in the wrong place.
  defp reject_station_pair!(6, nil, nil) do
    raise ArgumentError,
          ":strategy 6 地铁图模式 requires :originpoi and :destinationpoi, got neither"
  end

  defp reject_station_pair!(6, nil, _destinationpoi) do
    raise ArgumentError,
          ":strategy 6 地铁图模式 requires :originpoi and :destinationpoi, " <>
            ":originpoi is missing"
  end

  defp reject_station_pair!(6, _originpoi, nil) do
    raise ArgumentError,
          ":strategy 6 地铁图模式 requires :originpoi and :destinationpoi, " <>
            ":destinationpoi is missing"
  end

  defp reject_station_pair!(_strategy, originpoi, destinationpoi)
       when is_nil(originpoi) != is_nil(destinationpoi) do
    raise ArgumentError,
          ":originpoi and :destinationpoi must be given together, got: " <>
            "#{inspect(originpoi)} and #{inspect(destinationpoi)}"
  end

  defp reject_station_pair!(_strategy, _originpoi, _destinationpoi), do: :ok

  # No `route` in the answer means Amap found no plan, which is an answer rather than a
  # failure — the same reading `walking/4` gives an empty route.
  defp to_transit(nil), do: %Transit{transits: []}

  defp to_transit(payload) do
    %Transit{
      origin: Coord.parse_location(payload["origin"]),
      destination: Coord.parse_location(payload["destination"]),
      cost: to_transit_cost(payload["cost"]),
      transits: Enum.map(payload["transits"] || [], &to_transit_plan/1)
    }
  end

  defp to_transit_plan(payload) do
    %TransitPlan{
      distance: payload["distance"],
      nightflag: payload["nightflag"],
      segments: Enum.map(payload["segments"] || [], &to_transit_segment/1)
    }
  end

  defp to_transit_segment(payload) do
    %TransitSegment{
      walking: Routing.v3_walking(payload["walking"]),
      bus: Routing.v3_buslines(payload["bus"]),
      railway: Routing.v3_railway(payload["railway"]),
      taxi: to_taxi(payload["taxi"]),
      cost: to_transit_cost(payload["cost"])
    }
  end

  # The cost group exists at two levels on this page and neither carries all of it, so one
  # struct holds what either level sends and the other fields stay nil.
  defp to_transit_cost(nil), do: nil

  defp to_transit_cost(payload) do
    %TransitCost{
      duration: payload["duration"],
      taxi_fee: payload["taxi_fee"],
      transit_fee: payload["transit_fee"]
    }
  end

  defp to_taxi(nil), do: nil

  defp to_taxi(payload) do
    %Taxi{
      price: payload["price"],
      drivetime: payload["drivetime"],
      distance: payload["distance"],
      polyline: Coord.parse_locations(payload["polyline"]),
      startpoint: payload["startpoint"],
      startname: payload["startname"],
      endpoint: payload["endpoint"],
      endname: payload["endname"]
    }
  end
end
