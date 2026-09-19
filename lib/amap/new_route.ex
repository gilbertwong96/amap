defmodule Amap.NewRoute do
  @moduledoc """
  路径规划 2.0 — planning a way from one coordinate to another, on Amap's v5 pages.

  Amap's newer routing service (`guide/api/newroute`). It asks the same question as
  `Amap.Direction`'s v3 pages and answers with different parameters, differently named
  fields and a different set of strategies, so the two are separate modules with
  separate structs rather than one module with two modes.

  Two things belong to v5 alone. **`:show_fields`** names the optional groups a caller
  wants — `cost`, `tmcs`, `navi`, `cities`, `district`, `polyline` — and Amap returns
  base fields only when it is unset; a group this page does not list is refused here,
  because Amap would answer a request it silently ignored and the typo would look like
  an answer. **The strategies are a different enum**: `0`, `1`, `2` and `32`–`45`,
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
  alias Amap.Param
  alias Amap.Routing
  alias Amap.Validate

  @driving_path "/v5/direction/driving"

  @max_avoid_regions 32
  @max_avoid_vertices 16

  # 0 速度优先, 1 费用优先, 2 常规最快, 32 高德推荐 — Amap's own default — and 33–45, its
  # app-style combinations. Not v3's 0–20: the same digits mean other things there.
  @strategies [0, 1, 2] ++ Enum.to_list(32..45)

  # What this endpoint's 返回结果 section turns on, and nothing else: a group Amap does
  # not have comes back looking like base fields, so a typo is a call-site mistake.
  @show_fields ~w(cost tmcs navi cities district polyline)a

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
  for leaves its fields `nil`, or `[]` where the field holds a collection. `:method` is
  `:get`, the verb the page documents, or `:post`, which the page asks for when the
  parameters grow too long for a URL: the same parameters then travel as a form body,
  and the request is signed either way, because signing follows the family rather than
  the verb.

  Returns the route Amap planned, or `%Amap.NewRoute.Route{paths: []}` when it found
  none, as `Amap.Direction.walking/4` does.
  """
  @spec driving(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def driving(client, origin, destination, opts \\ []) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      origin_id: optional_present(opts, :origin_id),
      destination_id: optional_present(opts, :destination_id),
      destination_type: optional_present(opts, :destination_type),
      strategy: validate_strategy!(Keyword.get(opts, :strategy)),
      waypoints: Routing.waypoints(Keyword.get(opts, :waypoints)),
      avoidpolygons: encode_avoidpolygons(opts),
      plate: optional_present(opts, :plate),
      cartype: Routing.cartype(Keyword.get(opts, :cartype)),
      ferry: Routing.ferry(Keyword.get(opts, :ferry)),
      show_fields: optional_show_fields(opts)
    ]

    method = validate_method!(Keyword.get(opts, :method))

    case Amap.request(client, :restapi, method, @driving_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  defp optional_present(opts, key) do
    Validate.optional!(&Validate.present!/2, Keyword.get(opts, key), ":#{key}")
  end

  # 经度在前，纬度在后, which is what this parameter's rules say and what
  # `Param.polygon_lon_first/1` writes — never `Param.polygon/1`, whose latitude-first
  # order belongs to the Falcon search endpoints.
  defp encode_avoidpolygons(opts) do
    case Keyword.get(opts, :avoidpolygons) do
      nil ->
        nil

      rings ->
        rings
        |> Validate.polygons!(":avoidpolygons", @max_avoid_regions, @max_avoid_vertices)
        |> Param.polygon_lon_first()
    end
  end

  # Amap documents 0/1/2 and 32–45 for this endpoint, which is not v3's range and not
  # v3's meaning either. The check is its own function because
  # `Validate.optional_enum!/3` takes atoms, not integers.
  defp validate_strategy!(nil), do: nil
  defp validate_strategy!(value) when value in @strategies, do: value

  defp validate_strategy!(other) do
    raise ArgumentError,
          ":strategy must be one of #{inspect(@strategies)}, got: #{inspect(other)}"
  end

  # An unknown group is not passed through to Amap, which answers it with base fields
  # and no complaint — so a typo would look like a request Amap chose to answer partly.
  defp optional_show_fields(opts) do
    case Keyword.get(opts, :show_fields) do
      nil ->
        nil

      fields when is_list(fields) and fields != [] ->
        case Enum.reject(fields, &(&1 in @show_fields)) do
          [] ->
            Param.csv(fields)

          unknown ->
            raise ArgumentError,
                  ":show_fields must be a subset of #{inspect(@show_fields)}, got unknown: " <>
                    "#{inspect(unknown)}"
        end

      other ->
        raise ArgumentError,
              ":show_fields must be a non-empty list of #{inspect(@show_fields)}, " <>
                "got: #{inspect(other)}"
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
  defp to_route(payload), do: struct(Route, Routing.route_fields(payload, &to_path/1))

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
      polyline: Coord.parse_locations(payload["polyline"])
    }
  end

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
  # `results`/`result` pair on `/v3/distance`.
  defp to_tmcs(nil), do: []
  defp to_tmcs(list) when is_list(list), do: Enum.map(list, &to_tmc/1)
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

  defp to_city(nil), do: nil

  defp to_city(payload) do
    %City{adcode: payload["adcode"], citycode: payload["citycode"], city: payload["city"]}
  end

  defp to_district(nil), do: nil
  defp to_district(payload), do: %District{name: payload["name"], adcode: payload["adcode"]}
end
