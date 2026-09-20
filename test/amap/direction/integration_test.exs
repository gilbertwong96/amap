defmodule Amap.Direction.IntegrationTest do
  @moduledoc """
  Live checks for the S4 batch — the fourteen questions Amap's v3 and v5 routing
  pages leave open.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/direction/integration_test.exs

  One `describe` per open question. Each check asserts
  the shape its own module promises — a struct, a list of them, a string or a tuple —
  and prints the answer with `report/2` rather than failing on it: most of these are
  hypotheses about the wire, and a hypothesis that turns out wrong is a finding rather
  than a regression. Findings are recorded with the run that made them, and page
  discrepancies with the other page-versus-service differences.
  """

  use ExUnit.Case, async: false

  alias Amap.Direction
  alias Amap.Direction.Distance
  alias Amap.Error
  alias Amap.NewRoute
  alias Amap.Param
  alias Amap.Response
  alias Amap.Routing

  @moduletag :integration
  @moduletag timeout: 60_000

  # .exs files are loaded on every run, so setting AMAP_KEY and re-running is
  # enough; without one the module skips rather than failing.
  if System.get_env("AMAP_KEY") in [nil, ""] do
    @moduletag :skip
  end

  # 天安门 to 国贸, in Beijing: short enough for every mode on both pages, and on the
  # 1号线, so the transit plans have walking legs at both ends.
  @origin {116.397428, 39.90923}
  @destination {116.461, 39.9087}
  @citycode "010"
  # The trip is within Beijing, so the destination city is the same code; the wire
  # demands it either way.
  @city2 "010"

  # The six groups the v5 driving page documents, so its probe can ask for all of them
  # and see where each lands.
  @driving_groups ~w(cost tmcs navi cities district polyline)

  setup do
    client = Amap.new(key: System.fetch_env!("AMAP_KEY"))
    {:ok, client: client}
  end

  describe "1. /v3/direction/driving without extensions" do
    test "the parameter table marks it required; its own sample says otherwise", %{client: client} do
      result = Direction.driving(client, @origin, @destination)
      report("v3 driving, no extensions", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Direction.Route))
    end
  end

  describe "2. /v4/direction/bicycling answers the Falcon envelope" do
    test "errcode is 0 and data.paths is a list", %{client: client} do
      body =
        raw_get(client, "/v4/direction/bicycling",
          origin: Param.location(@origin),
          destination: Param.location(@destination)
        )

      case Response.decode(body) do
        {:ok, decoded} when is_map(decoded) ->
          report("v4 bicycling envelope keys", fn -> inspect(Map.keys(decoded)) end)

          report("v4 bicycling errcode", fn ->
            "#{inspect(decoded["errcode"])} (#{type_of(decoded["errcode"])})"
          end)

          report("v4 bicycling data.paths", fn -> paths_shape(decoded["data"]) end)

        {:ok, other} ->
          report("v4 bicycling envelope", fn -> "not an object: #{inspect(other)}" end)

        {:error, raw} ->
          report("v4 bicycling envelope", fn -> "not JSON: #{String.slice(raw, 0, 200)}" end)
      end

      result = Direction.bicycling(client, @origin, @destination)
      report("v4 bicycling mapped", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Direction.Route))
    end
  end

  describe "3. /v3/distance per-item code/info on a success" do
    test "the page says they appear only when a result fails", %{client: client} do
      result = Direction.distance(client, [@origin, {116.404, 39.915}], @destination)
      report("v3 distance results", fn -> summary(result) end)

      case result do
        {:ok, distances} ->
          report("v3 distance per-item code/info", fn -> distance_fields(distances) end)
          assert Enum.all?(distances, &(is_nil(&1.code) or is_binary(&1.code)))
          assert Enum.all?(distances, &(is_nil(&1.info) or is_binary(&1.info)))

        _error ->
          :ok
      end

      accept!(result, &structs?(&1, Distance))
    end
  end

  describe "4. v3 driving: `paths: [...]` or `paths: {path: [...]}`" do
    test "the page's response table prints both names", %{client: client} do
      raw =
        probe(client, "/v3/direction/driving",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          extensions: :all
        )

      case raw do
        {:ok, %{"route" => route}} ->
          report("v3 driving route keys", fn -> inspect(Map.keys(route)) end)
          report("v3 driving paths shape", fn -> paths_shape(route) end)

          # The third run proved the aggregated step's keys; whether a v3 plain path's
          # step carries `cities` has never been printed.
          report("v3 driving first step keys", fn -> first_path_step_keys(route) end)

        other ->
          report("v3 driving raw", fn -> summary(other) end)
      end

      result = Direction.driving(client, @origin, @destination, extensions: :all)
      report("v3 driving mapped", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Direction.Route))
    end
  end

  describe "5. v5 show_fields with a name the page does not list" do
    test "error or silence — the SDK refuses it at the call site either way", %{client: client} do
      assert_raise ArgumentError, ~r/:show_fields must be a subset of/, fn ->
        NewRoute.driving(client, @origin, @destination, show_fields: [:typo])
      end

      result =
        probe(client, "/v5/direction/driving",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          show_fields: "typo"
        )

      report("v5 driving show_fields=typo", fn -> summary(result) end)
      accept!(result)
    end
  end

  describe "6. v5 driving: 16 waypoints and 32 avoid polygons over GET" do
    test "the length at which the page's POST advice starts to matter", %{client: client} do
      waypoints = for n <- 1..16, do: {116.30 + n * 0.001, 39.91 + n * 0.001}
      polygons = for n <- 0..31, do: ring(115.0 + rem(n, 8) * 0.05, 39.0 + div(n, 8) * 0.05)

      query_bytes =
        query_length(client,
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          waypoints: Routing.waypoints(waypoints),
          avoidpolygons: Routing.avoidpolygons(polygons)
        )

      report("v5 driving max waypoints and avoid polygons", fn ->
        "#{query_bytes} bytes of query before host and path"
      end)

      opts = [waypoints: waypoints, avoidpolygons: polygons]

      get = NewRoute.driving(client, @origin, @destination, [method: :get] ++ opts)
      report("v5 driving same request over GET", fn -> summary(get) end)
      accept!(get, &is_struct(&1, NewRoute.Route))

      post = NewRoute.driving(client, @origin, @destination, [method: :post] ++ opts)
      report("v5 driving same request over POST", fn -> summary(post) end)
      accept!(post, &is_struct(&1, NewRoute.Route))
    end
  end

  describe "7. v5 transit: city2 is required, as the wire and the sample table say" do
    test "a city1-only call is refused with 20001, and the SDK now demands city2", %{
      client: client
    } do
      raw =
        probe(client, "/v5/direction/transit/integrated",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          city1: @citycode
        )

      report("v5 transit, city1 only", fn -> summary(raw) end)
      accept!(raw)

      result = NewRoute.transit(client, @origin, @destination, @citycode, @city2)
      report("v5 transit, both cities", fn -> summary(result) end)
      accept!(result, &is_struct(&1, NewRoute.Transit))
    end
  end

  describe "8. v3 driving roadaggregation: a grouping above steps, or steps replaced" do
    test "nothing maps `roads`, so an empty step list would be silent data loss", %{
      client: client
    } do
      raw =
        probe(client, "/v3/direction/driving",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          roadaggregation: true,
          extensions: :all
        )

      case raw do
        {:ok, %{"route" => route}} ->
          report("v3 roadaggregation raw path", fn -> aggregation_shape(route) end)

        other ->
          report("v3 roadaggregation raw", fn -> summary(other) end)
      end

      result =
        Direction.driving(client, @origin, @destination,
          roadaggregation: true,
          extensions: :all
        )

      report("v3 roadaggregation mapped steps", fn -> mapped_steps(result) end)
      report("v3 roadaggregation mapped roads", fn -> mapped_roads(result) end)
      accept!(result, &is_struct(&1, Direction.Route))
    end
  end

  describe "9. v3 transit walking legs carry their own origin/destination" do
    test "the page says they do; `Amap.Direction.Path` has no slots for them", %{client: client} do
      case transit_probe(client) do
        {:ok, %{"route" => route}} ->
          report("v3 transit walking legs", fn -> walking_legs(route) end)

        other ->
          report("v3 transit walking legs", fn -> summary(other) end)
      end
    end
  end

  describe "10. v3 transit emergency — one event or a list" do
    test "the page names it under extensions=all without saying which", %{client: client} do
      case transit_probe(client) do
        {:ok, %{"route" => route}} ->
          report("v3 transit emergency", fn -> emergency_shape(route) end)

        other ->
          report("v3 transit emergency", fn -> summary(other) end)
      end
    end
  end

  describe "11. /v3/distance: results[].result or a flat list" do
    test "the page prints both names; the mapper reads either", %{client: client} do
      raw =
        probe(client, "/v3/distance",
          origins: Param.pipe([Param.location(@origin), Param.location({116.404, 39.915})]),
          destination: Param.location(@destination)
        )

      case raw do
        {:ok, %{"results" => results}} ->
          report("v3 distance results shape", fn -> results_shape(results) end)

        other ->
          report("v3 distance results shape", fn -> summary(other) end)
      end

      result = Direction.distance(client, [@origin, {116.404, 39.915}], @destination)
      report("v3 distance mapped", fn -> summary(result) end)

      case result do
        {:ok, distances} ->
          report("v3 distance mapped fields", fn -> distance_fields(distances) end)

        _error ->
          :ok
      end

      accept!(result, &structs?(&1, Distance))
    end
  end

  describe "12. which level the v5 show_fields groups hang at" do
    test "the page prints them as flat object rows without a level", %{client: client} do
      raw =
        probe(client, "/v5/direction/driving",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          show_fields: Enum.join(@driving_groups, ",")
        )

      case raw do
        {:ok, %{"route" => route}} ->
          report("v5 driving group levels (raw)", fn -> group_levels(route) end)

        other ->
          report("v5 driving group levels (raw)", fn -> summary(other) end)
      end

      result =
        NewRoute.driving(client, @origin, @destination,
          show_fields: [:cost, :tmcs, :navi, :cities, :district, :polyline]
        )

      report("v5 driving group levels (mapped)", fn -> mapped_groups(result) end)

      case result do
        {:ok, %{paths: [path | _]}} ->
          # Both a path's and a step's polyline are decoded tuples when the group
          # arrived at that level, and nil when it did not.
          assert_locations!(path.polyline)
          assert is_list(path.tmcs)
          Enum.each(path.steps, &assert_locations!(&1.polyline))

        _error ->
          :ok
      end

      accept!(result, &is_struct(&1, NewRoute.Route))
    end
  end

  describe "13. v5 walk_type: a step field or a member of navi" do
    test "the page prints it at the same level as polyline", %{client: client} do
      raw =
        probe(client, "/v5/direction/walking",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          show_fields: "navi,walk_type"
        )

      case raw do
        {:ok, %{"route" => route}} ->
          report("v5 walking walk_type (raw)", fn -> walk_type_levels(route) end)

        other ->
          report("v5 walking walk_type (raw)", fn -> summary(other) end)
      end

      result = NewRoute.walking(client, @origin, @destination, show_fields: [:navi, :walk_type])
      report("v5 walking walk_type (mapped)", fn -> mapped_walk_type(result) end)

      case result do
        {:ok, %{paths: [path | _]}} ->
          Enum.each(path.steps, fn step ->
            navi = step.navi
            assert is_nil(navi) or is_binary(navi.walk_type) or is_nil(navi.walk_type)
          end)

        _error ->
          :ok
      end

      accept!(result, &is_struct(&1, NewRoute.Route))
    end
  end

  describe "14. the time wire form on v5 transit: 9:54 or 9-54" do
    test "the v5 page's example uses a hyphen; the shared Param.time writes a colon",
         %{client: client} do
      date = ~D[2026-09-21]
      time = ~T[09:54:00]

      scheduled =
        NewRoute.transit(client, @origin, @destination, @citycode, @city2,
          date: date,
          time: time
        )

      report("v5 transit time=#{Param.time(time)}", fn -> summary(scheduled) end)
      accept!(scheduled, &is_struct(&1, NewRoute.Transit))

      hyphenated =
        probe(client, "/v5/direction/transit/integrated",
          origin: Param.location(@origin),
          destination: Param.location(@destination),
          city1: @citycode,
          city2: @city2,
          date: Param.date(date),
          time: "9-54"
        )

      report("v5 transit time=9-54", fn -> summary(hyphenated) end)
      accept!(hyphenated)
    end
  end

  # The payload a business module sees has the envelope already stripped, so a question
  # about the wire's own body is asked of `Amap.request/6` directly — the same pipeline
  # with no mapper in the way.
  defp probe(client, path, params), do: Amap.request(client, :restapi, :get, path, params)

  # Transit's raw answer, shared by the two questions about a leg and about emergency.
  defp transit_probe(client) do
    probe(client, "/v3/direction/transit/integrated",
      origin: Param.location(@origin),
      destination: Param.location(@destination),
      city: @citycode,
      extensions: :all
    )
  end

  # An envelope question is asked of the wire with Finch directly: `Amap.request/6`
  # returns the payload after either envelope, and `errcode` is gone by then.
  defp raw_get(client, path, params) do
    query =
      params
      |> Keyword.put(:key, client.key)
      |> Param.encode()
      |> URI.encode_query()

    url = client.base_urls.restapi <> path <> "?" <> query

    case Finch.request(Finch.build(:get, url), client.pool) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        report("raw GET #{path}", fn -> "HTTP #{status}, #{byte_size(body)} bytes" end)
        body

      {:error, reason} ->
        flunk("raw GET #{path} failed: #{inspect(reason)}")
    end
  end

  # A 16-vertex ring around a centre, so the polygon list is as long as the page allows.
  defp ring(lon, lat) do
    for n <- 0..15 do
      angle = n * :math.pi() / 8
      {lon + 0.01 * :math.cos(angle), lat + 0.01 * :math.sin(angle)}
    end
  end

  defp query_length(client, params) do
    [{"key", client.key} | Param.encode(params)]
    |> URI.encode_query()
    |> byte_size()
  end

  # The two shapes every public function here promises: the struct (or list of them)
  # it maps, or an `Amap.Error` for what Amap refused. A refusal is an answer for
  # several of these questions, so it is reported rather than failed on; anything else
  # is a bug rather than an answer, and flunks.
  defp accept!(result, predicate \\ fn _ -> true end) do
    case result do
      {:ok, value} ->
        assert predicate.(value), "expected the promised shape, got: #{inspect(value)}"

      {:error, %Error{}} ->
        :ok

      other ->
        flunk("expected {:ok, _} or {:error, %Amap.Error{}}, got: #{inspect(other)}")
    end
  end

  defp structs?(values, module), do: is_list(values) and Enum.all?(values, &is_struct(&1, module))

  defp summary({:ok, %{paths: paths}}) when is_list(paths) do
    case paths do
      [%{distance: distance} | _] ->
        "ok, #{length(paths)} path(s), first distance #{inspect(distance)}"

      [] ->
        "ok, no paths"
    end
  end

  defp summary({:ok, %{transits: transits}}) when is_list(transits),
    do: "ok, #{length(transits)} transit(s)"

  defp summary({:ok, values}) when is_list(values), do: "ok, #{length(values)} result(s)"

  defp summary({:ok, payload}) when is_map(payload) do
    case payload do
      %{"route" => route} -> "ok, route: #{paths_shape(route)}"
      _other -> "ok, keys: #{inspect(Map.keys(payload))}"
    end
  end

  defp summary({:error, %Error{reason: reason, code: code, message: message}}) do
    "error, reason=#{inspect(reason)} code=#{inspect(code)} message=#{inspect(message)}"
  end

  defp summary(other), do: inspect(other)

  defp paths_shape(nil), do: "no route"

  defp paths_shape(route) when is_map(route) do
    cond do
      is_list(route["paths"]) -> "paths: list of #{length(route["paths"])}"
      is_list(route["path"]) -> "path: list of #{length(route["path"])}"
      Map.has_key?(route, "paths") -> "paths: #{type_of(route["paths"])}"
      Map.has_key?(route, "path") -> "path: #{type_of(route["path"])}"
      true -> "keys: #{inspect(Map.keys(route))}"
    end
  end

  defp paths_shape(other), do: type_of(other)

  # Which case it hit is part of the answer: the next run's line must not be readable two
  # ways when `paths` is absent, empty, or starts with something that is not an object.
  defp first_path_step_keys(%{"paths" => [%{"steps" => [step | _]} | _]}) when is_map(step),
    do: inspect(Map.keys(step))

  defp first_path_step_keys(%{"paths" => [%{"steps" => steps} | _]}),
    do: "first path has steps: #{type_of(steps)}"

  defp first_path_step_keys(%{"paths" => [first | _]}), do: "first path: #{type_of(first)}"
  defp first_path_step_keys(%{"paths" => []}), do: "paths: empty list"
  defp first_path_step_keys(%{"paths" => paths}), do: "paths: #{type_of(paths)}"
  defp first_path_step_keys(%{}), do: "no paths key"

  defp first_path_step_keys(other), do: "not a route: #{type_of(other)}"

  defp count_or_absent(map, key) do
    case map do
      %{^key => value} when is_list(value) -> "list of #{length(value)}"
      %{^key => value} -> "#{type_of(value)} #{inspect(value)}"
      _other -> "absent"
    end
  end

  defp aggregation_shape(%{"paths" => [path | _]}) when is_map(path) do
    "path keys: #{inspect(Map.keys(path))}; roads: #{count_or_absent(path, "roads")}; " <>
      "steps: #{count_or_absent(path, "steps")}; #{first_road(path)}; #{road_key_sets(path)}"
  end

  defp aggregation_shape(route), do: "no path: #{inspect(route)}"

  # What `Amap.Direction.Road`'s field types wait on: the key list is already known,
  # so this prints the first entry whole to pin the values, and the first inner step's
  # keys in case this `steps` is the same shape as a path's. `road_key_sets/1` lists
  # every entry's keys — the struct maps the four it knows and drops the rest, so a
  # fifth key on any entry but the first would otherwise go unseen.
  defp first_road(%{"roads" => [road | _]}) when is_map(road) do
    "first road: #{inspect(road)}; #{first_road_step(road)}"
  end

  defp first_road(_path), do: "no roads key"

  defp first_road_step(%{"steps" => [step | _]}) when is_map(step),
    do: "inner step keys: #{inspect(Map.keys(step))}"

  defp first_road_step(%{"steps" => steps}), do: "inner steps: #{type_of(steps)}"

  defp first_road_step(_road), do: "no inner steps key"

  defp road_key_sets(%{"roads" => roads}) when is_list(roads) do
    "road key sets: " <>
      inspect(
        Enum.map(roads, fn
          road when is_map(road) -> Enum.sort(Map.keys(road))
          other -> type_of(other)
        end)
      )
  end

  defp road_key_sets(_path), do: "no roads key"

  defp mapped_roads({:ok, %{paths: [path | _]}}),
    do: "#{length(path.roads)} road(s); first mapped: #{inspect(List.first(path.roads))}"

  defp mapped_roads(other), do: summary(other)

  defp mapped_steps({:ok, %{paths: [path | _]}}),
    do: "#{length(path.steps)} step(s) on the first path"

  defp mapped_steps(other), do: summary(other)

  defp walking_legs(route) do
    legs =
      for transit <- route["transits"] || [],
          segment <- transit["segments"] || [],
          walking = segment["walking"],
          is_map(walking),
          do: walking

    case legs do
      [] ->
        "no walking leg in this answer"

      [first | _] ->
        with_origin = Enum.count(legs, &Map.has_key?(&1, "origin"))
        with_destination = Enum.count(legs, &Map.has_key?(&1, "destination"))
        sample = Map.take(first, ["origin", "destination", "distance", "duration"])

        "#{length(legs)} leg(s); origin on #{with_origin}, destination on #{with_destination}; " <>
          "first: #{inspect(sample)}"
    end
  end

  defp emergency_shape(route) do
    case Map.fetch(route, "emergency") do
      {:ok, value} ->
        "route.emergency: #{type_of(value)} #{inspect(value)}"

      :error ->
        in_transits =
          for transit <- route["transits"] || [],
              Map.has_key?(transit, "emergency"),
              do: transit["emergency"]

        case in_transits do
          [] -> "absent at route level and in every transit"
          values -> "route level absent; in transits: #{inspect(values)}"
        end
    end
  end

  defp results_shape(results) when is_list(results) do
    case results do
      [] ->
        "empty list"

      [first | _] when is_map(first) ->
        "list of #{length(results)}, first keys: #{inspect(Map.keys(first))}"

      [first | _] ->
        "list of #{length(results)}, first is #{type_of(first)}"
    end
  end

  defp results_shape(%{"result" => nested}),
    do: "object wrapping `result`: #{results_shape(nested)}"

  defp results_shape(other), do: type_of(other)

  defp distance_fields(distances) do
    Enum.map_join(distances, "; ", fn item ->
      "origin_id=#{inspect(item.origin_id)} dest_id=#{inspect(item.dest_id)} " <>
        "distance=#{inspect(item.distance)} code=#{inspect(item.code)} info=#{inspect(item.info)}"
    end)
  end

  defp group_levels(route) do
    case route["paths"] do
      [path | _] when is_map(path) ->
        at_path = Enum.filter(@driving_groups, &Map.has_key?(path, &1))
        step = path["steps"] |> List.wrap() |> List.first()

        at_step =
          if is_map(step), do: Enum.filter(@driving_groups, &Map.has_key?(step, &1)), else: []

        values = for group <- at_path, do: "#{group}=#{outer_shape(path[group])}"

        # The one group whose level the page leaves open: the step carries the key, and
        # the third run settled that it holds a list of city objects. Printed in full so
        # the shape the mapper reads stays visible.
        step_cities =
          if is_map(step), do: "; first step cities: #{inspect(step["cities"])}", else: ""

        "path: #{inspect(at_path)}; first step: #{inspect(at_step)}; #{Enum.join(values, ", ")}#{step_cities}"

      other ->
        "no paths: #{inspect(other)}"
    end
  end

  defp outer_shape(value) when is_map(value), do: "map #{inspect(Map.keys(value))}"
  defp outer_shape(value) when is_list(value), do: "list of #{length(value)}"
  defp outer_shape(value), do: type_of(value)

  defp mapped_groups({:ok, %{paths: [path | _]}}) do
    case List.first(path.steps) do
      nil -> "path: #{group_reading(path)}; no steps"
      step -> "path: #{group_reading(path)}; first step: #{group_reading(step)}"
    end
  end

  defp mapped_groups(other), do: summary(other)

  defp group_reading(struct) do
    base =
      "cost=#{inspect(struct.cost)} tmcs=#{length(struct.tmcs)} navi=#{inspect(struct.navi)} " <>
        "polyline=#{point_count(struct.polyline)}"

    case struct do
      %Amap.NewRoute.Path{} ->
        base <> " cities=#{inspect(struct.cities)} district=#{inspect(struct.district)}"

      %Amap.NewRoute.Step{} ->
        base <> " cities=#{inspect(struct.cities)}"

      _step ->
        base
    end
  end

  defp point_count(nil), do: "nil"
  defp point_count(points) when is_list(points), do: "#{length(points)} tuple(s)"
  defp point_count(other), do: type_of(other)

  defp walk_type_levels(route) do
    case route["paths"] do
      [path | _] when is_map(path) ->
        steps = path["steps"] || []
        at_step = Enum.count(steps, &(is_map(&1) and Map.has_key?(&1, "walk_type")))
        in_navi = Enum.count(steps, &navi_walk_type?/1)
        sample = steps |> List.first() |> sample_step()

        "#{at_step}/#{length(steps)} step(s) carry walk_type; #{in_navi} inside navi; " <>
          "first: #{inspect(sample)}"

      other ->
        "no paths: #{inspect(other)}"
    end
  end

  defp navi_walk_type?(step) do
    is_map(step) and is_map(step["navi"]) and Map.has_key?(step["navi"], "walk_type")
  end

  defp sample_step(step) when is_map(step),
    do: Map.take(step, ["instruction", "walk_type", "navi"])

  defp sample_step(step), do: step

  defp mapped_walk_type({:ok, %{paths: [path | _]}}) do
    steps = path.steps
    in_navi = Enum.count(steps, &(is_map(&1.navi) and is_binary(&1.navi.walk_type)))
    first = List.first(steps)

    "#{in_navi}/#{length(steps)} step(s) have a walk_type inside navi; first navi: " <>
      "#{inspect(first && first.navi)}"
  end

  defp mapped_walk_type(other), do: summary(other)

  defp assert_locations!(nil), do: :ok

  defp assert_locations!(points) when is_list(points) do
    assert Enum.all?(points, &match?({lon, lat} when is_float(lon) and is_float(lat), &1)),
           "expected {lon, lat} tuples, got: #{inspect(points)}"
  end

  defp assert_locations!(other), do: flunk("expected a point list or nil, got: #{inspect(other)}")

  defp type_of(nil), do: "nil"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_list(value), do: "list"
  defp type_of(value) when is_map(value), do: "map"
  defp type_of(_other), do: "other"

  # One line per finding, prefixed so a run's output reads as a list of answers.
  defp report(label, fun), do: IO.puts("[integration] #{label}: #{fun.()}")
end
