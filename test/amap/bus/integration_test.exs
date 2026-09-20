defmodule Amap.Bus.IntegrationTest do
  @moduledoc """
  Live checks for the S8 batch — the four 公交信息查询 endpoints, and the shapes
  the batch's own page leaves open.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/bus/integration_test.exs

  Each check asserts the shape its module promises — a struct, a list of them, a
  tuple — and prints the answer with `report/2` rather than failing on it: the
  page's tables disagree with themselves in two places, and a hypothesis that
  turns out wrong is a finding rather than a regression. The findings are recorded
  with the run that made them.
  """

  use ExUnit.Case, async: false

  alias Amap.Bus
  alias Amap.Bus.Line
  alias Amap.Bus.Lines
  alias Amap.Bus.Stop
  alias Amap.Bus.Stops
  alias Amap.Bus.Suggestion
  alias Amap.Error
  alias Amap.Param
  alias Amap.Response

  @moduletag :integration
  @moduletag timeout: 60_000

  # .exs files are loaded on every run, so setting AMAP_KEY and re-running is
  # enough; without one the module skips rather than failing.
  if System.get_env("AMAP_KEY") in [nil, ""] do
    @moduletag :skip
  end

  # The stop and the two keywords the 2026-09-20 probes already named, so a live
  # run's answers are comparable with the recorded ones.
  @stop_id "BV10006672"
  @stop_keyword "来广营路口西"
  @line_keyword "地铁1号线"

  setup do
    client = Amap.new(key: System.fetch_env!("AMAP_KEY"))
    {:ok, client: client}
  end

  describe "stopid: count's type and suggestion's absence" do
    test "the wire carries count as a string and no suggestion", %{client: client} do
      result = Bus.stopid(client, @stop_id)
      report("stopid mapped", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Stops))

      case result do
        {:ok, stops} ->
          report("stopid count", fn -> "#{inspect(stops.count)} (#{type_of(stops.count)})" end)

          report("stopid suggestion", fn -> "#{inspect(stops.suggestion)}" end)

          report("stopid first stop", fn ->
            case stops.busstops do
              [%Stop{} = stop | _] ->
                "#{stop.name} at #{inspect(stop.location)}, adcode #{inspect(stop.adcode)}, " <>
                  "#{length(stop.buslines)} line(s); first: #{inspect(List.first(stop.buslines))}"

              [] ->
                "no stops"
            end
          end)

        _refusal ->
          :ok
      end

      raw = raw_get(client, "/v3/bus/stopid", id: @stop_id)
      report("stopid raw envelope keys", fn -> envelope_keys(raw) end)
      report("stopid raw count type", fn -> raw_field_type(raw, "count") end)
      report("stopid raw suggestion", fn -> raw_field(raw, "suggestion") end)
    end
  end

  describe "stopname: city is optional" do
    test "with and without city answer the same stations", %{client: client} do
      without = Bus.stopname(client, @stop_keyword)
      with_city = Bus.stopname(client, @stop_keyword, city: "110000")

      report("stopname without city", fn -> stops_report(without) end)
      report("stopname with city=110000", fn -> stops_report(with_city) end)

      assert_same_stations!(without, with_city)

      for result <- [without, with_city] do
        accept!(result, &is_struct(&1, Stops))

        case result do
          {:ok, stops} ->
            report("stopname suggestion", fn -> inspect(stops.suggestion) end)

          _refusal ->
            :ok
        end
      end
    end
  end

  describe "linename: city is optional, and 全国 is what that means" do
    test "without city the search leaves the capital", %{client: client} do
      result = Bus.linename(client, @line_keyword)
      report("linename without city", fn -> lines_report(result) end)
      accept!(result, &is_struct(&1, Lines))

      case result do
        {:ok, lines} ->
          report("linename cities", fn ->
            Enum.map_join(lines.buslines, ", ", fn %Line{} = line ->
              "#{line.id} citycode=#{inspect(line.citycode)} type=#{inspect(line.type)}"
            end)
          end)

          report("linename count", fn -> "#{inspect(lines.count)} (#{type_of(lines.count)})" end)
          report("linename suggestion", fn -> inspect(lines.suggestion) end)

        _refusal ->
          :ok
      end

      raw = raw_get(client, "/v3/bus/linename", keywords: @line_keyword)
      report("linename raw count type", fn -> raw_field_type(raw, "count") end)
      report("linename raw suggestion", fn -> raw_field(raw, "suggestion") end)
    end
  end

  describe "lineid with extensions=all: the page's fare and rectangle fields" do
    test "the fields the page lists around the second `distance` row", %{client: client} do
      result = Bus.lineid(client, "110100014478", extensions: :all)
      report("lineid all", fn -> lines_report(result) end)
      accept!(result, &is_struct(&1, Lines))

      case result do
        {:ok, lines} ->
          report("lineid fare and rectangle", fn -> fare_report(lines) end)
          report("lineid stops", fn -> line_stops(lines) end)

        _refusal ->
          :ok
      end
    end
  end

  # The payload a business module sees has the envelope already stripped, so a
  # question about the raw body is asked of the wire with Finch directly.
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

  defp envelope_keys(raw) do
    case Response.decode(raw) do
      {:ok, decoded} when is_map(decoded) -> inspect(Enum.sort(Map.keys(decoded)))
      {:ok, other} -> "not an object: #{type_of(other)}"
      {:error, _body} -> "not JSON"
    end
  end

  defp raw_field(raw, field) do
    case Response.decode(raw) do
      {:ok, decoded} when is_map(decoded) ->
        value = Map.get(decoded, field)
        "#{inspect(value)} (#{type_of(value)})"

      _other ->
        "no decoded object"
    end
  end

  defp raw_field_type(raw, field) do
    case Response.decode(raw) do
      {:ok, decoded} when is_map(decoded) -> type_of(Map.get(decoded, field))
      _other -> "no decoded object"
    end
  end

  # The comparison the ruling rests on: both calls asked the same keyword, and the
  # page-level claim is that omitting `city` changes nothing but the search area.
  defp assert_same_stations!({:ok, %Stops{} = without}, {:ok, %Stops{} = with_city}) do
    names = fn stops -> Enum.map(stops.busstops, & &1.id) end
    assert names.(without) == names.(with_city)
  end

  defp assert_same_stations!(_refused, _other), do: :ok

  defp stops_report({:ok, %Stops{} = stops}) do
    "#{length(stops.busstops)} stop(s), count=#{inspect(stops.count)}: " <>
      Enum.map_join(stops.busstops, ", ", &"#{&1.id} #{&1.name}")
  end

  defp stops_report(other), do: summary(other)

  defp lines_report({:ok, %Lines{} = lines}) do
    "#{length(lines.buslines)} line(s), count=#{inspect(lines.count)}: " <>
      Enum.map_join(lines.buslines, ", ", &"#{&1.id} #{&1.name}")
  end

  defp lines_report(other), do: summary(other)

  defp fare_report(%Lines{buslines: [line | _]}) do
    "distance=#{inspect(line.distance)} basic_price=#{inspect(line.basic_price)} " <>
      "total_price=#{inspect(line.total_price)} bounds=#{inspect(line.bounds)} " <>
      "timedesc=#{inspect(line.timedesc)} polyline parts=" <>
      "#{if(line.polyline, do: length(line.polyline), else: "nil")}"
  end

  defp fare_report(%Lines{buslines: []}), do: "no lines"
  defp fare_report(other), do: summary(other)

  defp line_stops(%Lines{buslines: [line | _]}) do
    "#{length(line.busstops)} stop(s); first: #{inspect(List.first(line.busstops))}"
  end

  defp line_stops(%Lines{buslines: []}), do: "no lines"
  defp line_stops(other), do: summary(other)

  # The two shapes every public function here promises: the struct it maps, or an
  # `Amap.Error` for what Amap refused. A refusal is an answer for these checks, so
  # it is reported rather than failed on; anything else is a bug and flunks.
  defp accept!(result, predicate) do
    case result do
      {:ok, value} ->
        assert predicate.(value), "expected the promised shape, got: #{inspect(value)}"

      {:error, %Error{}} ->
        :ok

      other ->
        flunk("expected {:ok, _} or {:error, %Amap.Error{}}, got: #{inspect(other)}")
    end
  end

  defp summary({:ok, %Stops{} = stops}), do: stops_report({:ok, stops})
  defp summary({:ok, %Lines{} = lines}), do: lines_report({:ok, lines})
  defp summary({:ok, %Suggestion{} = suggestion}), do: inspect(suggestion)

  defp summary({:error, %Error{reason: reason, code: code, message: message}}) do
    "refused: reason=#{inspect(reason)} code=#{inspect(code)} message=#{inspect(message)}"
  end

  defp summary(other), do: inspect(other)

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
