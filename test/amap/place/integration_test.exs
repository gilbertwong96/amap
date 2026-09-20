defmodule Amap.Place.IntegrationTest do
  @moduledoc """
  Live checks for the S5 batch — the nine endpoints of 搜索POI (v3), 搜索POI 2.0 (v5)
  and 输入提示, and the shapes the three pages leave open.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/place/integration_test.exs

  What this run is for, and which question its answer settles:

    * the envelopes — which keys each of the three pages really sends, whether v5
      carries a `suggestion` its tables do not list, and whether `infocode` arrives;
    * **every `show_fields` group on the v5 side**, raw: `children`, `business`,
      `indoor`, `navi` and `photos` are typed as a union (`[X.t()] | X.t() | nil`)
      because the page prints each as an `object` whose fields follow; the run has only
      shown lists, and the file prints every group raw so the remaining branch stays honest;
    * what `extensions=all` adds on the v3 side, and the shapes of `photos`, `biz_ext`
      and `indoor_data` there;
    * pagination: what `count` means against the rows returned, and whether a
      `page_num` the 200-row ceiling cannot fill is refused or answered empty;
    * `/v3/place/detail`'s own 高级权限 gate, which the page says can refuse while the
      three searches work;
    * whether Amap enforces the v5 pages' 80-character keyword rule at all;
    * 输入提示: its `datatype` default (the page's sample table calls it required while
      its parameter table says optional), and the page's claim that `location` only
      works beside `city`.

  Each check asserts the shape its module promises — a struct, or an `Amap.Error` for
  what Amap refused — and prints the rest with `report/2` rather than failing on it: a
  hypothesis that turns out wrong is a finding, not a regression.
  """

  use ExUnit.Case, async: false

  alias Amap.Error
  alias Amap.InputTips
  alias Amap.InputTips.Result, as: TipsResult
  alias Amap.NewPlace
  alias Amap.NewPlace.Poi, as: NewPoi
  alias Amap.NewPlace.Result, as: NewResult
  alias Amap.Param
  alias Amap.Place
  alias Amap.Place.Poi
  alias Amap.Place.Result
  alias Amap.Response

  @moduletag :integration
  @moduletag timeout: 60_000

  # .exs files are loaded on every run, so setting AMAP_KEY and re-running is
  # enough; without one the module skips rather than failing.
  if System.get_env("AMAP_KEY") in [nil, ""] do
    @moduletag :skip
  end

  @keyword "北京大学"
  @generic_keyword "美食"
  # The v5 page's own sample id, and the v3 page's sample id.
  @v5_detail_id "B000A7BM4H"
  @v3_detail_id "B0FFFAB6J2"

  setup do
    client = Amap.new(key: System.fetch_env!("AMAP_KEY"))
    {:ok, client: client}
  end

  describe "v3 关键字搜索: the envelope, count, and the generic-keyword suggestion" do
    test "a generic keyword without city answers, and the raw body says how", %{client: client} do
      result = Place.text(client, keywords: @generic_keyword)
      report("v3 text mapped", fn -> compact_result(result) end)
      accept!(result, &is_struct(&1, Result))

      case result do
        {:ok, %Result{} = placed} ->
          report("v3 text count", fn -> "#{inspect(placed.count)} (#{type_of(placed.count)})" end)
          report("v3 text suggestion", fn -> inspect(placed.suggestion) end)
          report("v3 text pois", fn -> "mapped #{length(placed.pois)} row(s)" end)

        _refusal ->
          :ok
      end

      raw = raw_get(client, "/v3/place/text", keywords: @generic_keyword)
      report("v3 text raw envelope keys", fn -> envelope_keys(raw) end)
      report("v3 text raw count", fn -> raw_field(raw, "count") end)
      report("v3 text raw suggestion shape", fn -> raw_field_shape(raw, "suggestion") end)
      report("v3 text raw pois shape", fn -> raw_field_shape(raw, "pois") end)
    end
  end

  describe "v3 关键字搜索: types alone, and the offset/page pair" do
    test "types-only works, and page 2 answers other rows", %{client: client} do
      typed = Place.text(client, types: ["141201"], offset: 25, page: 1)
      second = Place.text(client, types: ["141201"], offset: 25, page: 2)

      report("v3 types-only offset=25 page=1", fn -> compact_result(typed) end)
      accept!(typed, &is_struct(&1, Result))
      report("v3 types-only offset=25 page=2", fn -> compact_result(second) end)
      accept!(second, &is_struct(&1, Result))

      report("v3 offset/page moved the rows", fn -> page_ids(typed, second) end)
    end
  end

  describe "v3 周边搜索: the substituted categories" do
    test "a call with neither keywords nor types still answers", %{client: client} do
      result = Place.around(client, {116.473168, 39.993015}, radius: 1_000)
      report("v3 around no keywords, no types", fn -> compact_result(result) end)
      accept!(result, &is_struct(&1, Result))

      case result do
        {:ok, %Result{pois: [%Poi{} = poi | _]}} ->
          report("v3 around first row", fn ->
            "#{inspect(poi.name)} type=#{inspect(poi.type)} distance=#{inspect(poi.distance)}"
          end)

        _other ->
          :ok
      end
    end
  end

  describe "v3 多边形搜索: the | polygon is longitude-first" do
    test "a two-corner rectangle finds Beijing rows", %{client: client} do
      rectangle = [{116.460988, 40.006919}, {116.48231, 40.007381}]
      result = Place.polygon(client, rectangle, keywords: "kfc")
      report("v3 polygon rectangle", fn -> compact_result(result) end)
      accept!(result, &is_struct(&1, Result))

      # A transposed ring would cover land outside Beijing; the first hit's location
      # is the cheap detector, and the request succeeding is not one.
      case result do
        {:ok, %Result{pois: [%Poi{} = poi | _]}} ->
          report("v3 polygon first hit", fn -> "#{poi.name} #{inspect(poi.location)}" end)

        _other ->
          :ok
      end
    end
  end

  describe "v3 ID 查询: the page's own 高级权限 gate" do
    test "one id, and a refusal here is the page's finding rather than a bug", %{client: client} do
      result = Place.detail(client, @v3_detail_id)
      report("v3 detail", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Result))

      raw = raw_get(client, "/v3/place/detail", id: @v3_detail_id)
      report("v3 detail raw envelope keys", fn -> envelope_keys(raw) end)
    end
  end

  describe "v3 extensions=all: where the deep fields sit" do
    test "the base and all key sets, and the three nested shapes", %{client: client} do
      base = raw_get(client, "/v3/place/text", keywords: @keyword)
      all = raw_get(client, "/v3/place/text", keywords: @keyword, extensions: :all)

      report("v3 base vs all poi keys", fn -> poi_key_diff(base, all) end)

      case first_poi(all) do
        {:ok, poi} ->
          report("v3 photos shape", fn -> shape_of(poi["photos"]) end)
          report("v3 biz_ext shape", fn -> shape_of(poi["biz_ext"]) end)
          report("v3 indoor_data shape", fn -> shape_of(poi["indoor_data"]) end)

        :error ->
          report("v3 all poi", fn -> "none" end)
      end

      result = Place.text(client, keywords: @keyword, extensions: :all)
      report("v3 all mapped", fn -> mapped_extension_report(result) end)
      accept!(result, &is_struct(&1, Result))
    end
  end

  describe "v5 关键字搜索: the envelope and every show_fields group" do
    test "one call asks for all five groups", %{client: client} do
      fields = [:children, :business, :indoor, :navi, :photos]
      result = NewPlace.text(client, keywords: @keyword, show_fields: fields)
      report("v5 text mapped", fn -> compact_new_result(result) end)
      accept!(result, &is_struct(&1, NewResult))

      case result do
        {:ok, %NewResult{pois: [%NewPoi{} = poi | _]}} ->
          report("v5 group shapes (mapped)", fn -> mapped_group_shapes(poi) end)

        _other ->
          :ok
      end

      raw =
        raw_get(client, "/v5/place/text",
          keywords: @keyword,
          show_fields: "children,business,indoor,navi,photos"
        )

      report("v5 text raw envelope keys", fn -> envelope_keys(raw) end)
      report("v5 text raw count", fn -> raw_field(raw, "count") end)
      report("v5 text raw suggestion", fn -> raw_field(raw, "suggestion") end)
      report("v5 text raw infocode", fn -> raw_field(raw, "infocode") end)
      report("v5 text raw pois shape", fn -> raw_field_shape(raw, "pois") end)

      case first_poi(raw) do
        {:ok, poi} -> report("v5 group shapes (raw)", fn -> raw_group_shapes(poi) end)
        :error -> report("v5 raw poi", fn -> "none" end)
      end
    end
  end

  describe "v5 分页: page_size/page_num, count, and the 200-row ceiling" do
    test "two pages of two rows, and a page beyond the ceiling", %{client: client} do
      one = paged(client, 1)
      two = paged(client, 2)
      beyond = paged(client, 21)

      report("v5 page_size=2 page_num=1", fn -> compact_new_result(one) end)
      accept!(one, &is_struct(&1, NewResult))
      report("v5 page_size=2 page_num=2", fn -> compact_new_result(two) end)
      accept!(two, &is_struct(&1, NewResult))
      report("v5 page_size=10 page_num=21", fn -> compact_new_result(beyond) end)
      accept!(beyond, &is_struct(&1, NewResult))

      report("v5 count against rows", fn -> count_vs_rows(one, two, beyond) end)
    end
  end

  describe "v5 keyword length: does Amap enforce the 80-character rule" do
    test "an 81-character keyword, raw", %{client: client} do
      long = String.duplicate("北", 81)
      raw = raw_get(client, "/v5/place/text", keywords: long, page_size: 1)
      report("v5 81-char keyword raw status", fn -> raw_field(raw, "status") end)
      report("v5 81-char keyword raw info", fn -> raw_field(raw, "info") end)
      report("v5 81-char keyword raw count", fn -> raw_field(raw, "count") end)
    end
  end

  describe "v5 周边搜索 and 多边形搜索" do
    test "radius with substituted categories, and the same | polygon", %{client: client} do
      around = NewPlace.around(client, {116.473168, 39.993015}, radius: 1_000, page_size: 5)
      report("v5 around no keywords, no types", fn -> compact_new_result(around) end)
      accept!(around, &is_struct(&1, NewResult))

      polygon =
        NewPlace.polygon(
          client,
          [{116.460988, 40.006919}, {116.48231, 40.007381}],
          keywords: "kfc",
          page_size: 5
        )

      report("v5 polygon rectangle", fn -> compact_new_result(polygon) end)
      accept!(polygon, &is_struct(&1, NewResult))
    end
  end

  describe "v5 ID 搜索: up to ten ids, atag, and the count its page omits" do
    test "two ids in one call", %{client: client} do
      result = NewPlace.detail(client, [@v5_detail_id, "B0FFKEPXS2"])
      report("v5 detail two ids", fn -> compact_new_result(result) end)
      accept!(result, &is_struct(&1, NewResult))

      case result do
        {:ok, %NewResult{count: count, pois: pois}} ->
          report("v5 detail ids, atag and count", fn ->
            "count=#{inspect(count)} ids=#{inspect(Enum.map(pois, & &1.id))} " <>
              "atags=#{inspect(Enum.map(pois, & &1.atag))}"
          end)

        _refusal ->
          :ok
      end
    end
  end

  describe "输入提示: datatype's default and location's dependence on city" do
    test "keyword only, the city pair, and a busline datatype", %{client: client} do
      plain = InputTips.inputtips(client, "招商")
      with_city = InputTips.inputtips(client, "招商", city: "010", location: {116.45, 39.93})
      buslines = InputTips.inputtips(client, "地铁", datatype: [:busline])

      report("inputtips keyword only", fn -> tips_report(plain) end)
      accept!(plain, &is_struct(&1, TipsResult))
      report("inputtips city+location", fn -> tips_report(with_city) end)
      accept!(with_city, &is_struct(&1, TipsResult))
      report("inputtips datatype=busline", fn -> tips_report(buslines) end)
      accept!(buslines, &is_struct(&1, TipsResult))

      report("inputtips first ids", fn ->
        "plain #{first_ids(plain)} / city #{first_ids(with_city)}"
      end)

      report("inputtips busline tips without location", fn ->
        case buslines do
          {:ok, %TipsResult{tips: tips}} ->
            "#{length(tips)} tip(s), #{Enum.count(tips, &is_nil(&1.location))} without a location"

          other ->
            summary(other)
        end
      end)

      raw = raw_get(client, "/v3/assistant/inputtips", keywords: "招商")
      report("inputtips raw envelope keys", fn -> envelope_keys(raw) end)
      report("inputtips raw count", fn -> raw_field(raw, "count") end)
      report("inputtips raw tips shape", fn -> raw_field_shape(raw, "tips") end)
    end
  end

  # --- the batch's own calls that need no report, only a call ------------------

  defp paged(client, page_num) do
    NewPlace.text(client,
      keywords: @generic_keyword,
      region: "北京市",
      page_size: if(page_num == 21, do: 10, else: 2),
      page_num: page_num
    )
  end

  # --- raw wire helpers --------------------------------------------------------

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

  defp decode(raw) do
    case Response.decode(raw) do
      {:ok, decoded} -> decoded
      {:error, _body} -> nil
    end
  end

  defp envelope_keys(raw) do
    case decode(raw) do
      %{} = body -> inspect(Enum.sort(Map.keys(body)))
      other -> "not an object: #{inspect(other)}"
    end
  end

  defp raw_field(raw, field) do
    case decode(raw) do
      %{} = body ->
        value = Map.get(body, field)
        "#{inspect(value)} (#{type_of(value)})"

      _other ->
        "not JSON"
    end
  end

  defp raw_field_shape(raw, field) do
    case decode(raw) do
      %{} = body -> shape_of(Map.get(body, field))
      _other -> "not JSON"
    end
  end

  defp first_poi(raw) do
    with %{} = body <- decode(raw),
         pois when is_list(pois) <- unwrap_pois(Map.get(body, "pois")),
         [poi | _] when is_map(poi) <- pois do
      {:ok, poi}
    else
      _other -> :error
    end
  end

  defp unwrap_pois(%{"poi" => list}) when is_list(list), do: list
  defp unwrap_pois(list) when is_list(list), do: list
  defp unwrap_pois(_other), do: []

  # The inventory's `extensions=all` question, read off the first poi: which keys
  # `all` adds that `base` did not carry.
  defp poi_key_diff(base_raw, all_raw) do
    with {:ok, base_poi} <- first_poi(base_raw),
         {:ok, all_poi} <- first_poi(all_raw) do
      "added #{inspect(Map.keys(all_poi) -- Map.keys(base_poi))}; removed " <>
        "#{inspect(Map.keys(base_poi) -- Map.keys(all_poi))}"
    else
      _other -> "could not read a poi from both bodies"
    end
  end

  # --- the v5 show_fields groups, raw and mapped -------------------------------

  @groups ["children", "business", "indoor", "navi", "photos"]

  defp raw_group_shapes(poi) do
    Enum.map_join(@groups, "; ", fn field ->
      value = poi[field]
      "#{field}=#{shape_of(value)} #{truncate(inspect(value))}"
    end)
  end

  defp mapped_group_shapes(poi) do
    Enum.map_join(@groups, "; ", fn field ->
      "#{field}=#{mapped_shape(Map.get(poi, String.to_existing_atom(field)))}"
    end)
  end

  defp mapped_shape(nil), do: "nil"
  defp mapped_shape(list) when is_list(list), do: "list of #{length(list)}"
  defp mapped_shape(%module{}), do: inspect(module)

  defp shape_of(nil), do: "nil"

  defp shape_of(value) when is_list(value),
    do: "list of #{length(value)} (#{Enum.map_join(value, ",", &type_of/1)})"

  defp shape_of(%{} = map), do: "map; keys: #{inspect(Enum.sort(Map.keys(map)))}"
  defp shape_of(value), do: "#{type_of(value)}: #{truncate(inspect(value))}"

  # --- compact mapped summaries ------------------------------------------------

  defp compact_result({:ok, %Result{} = result}) do
    "count=#{inspect(result.count)} (#{type_of(result.count)}) rows=#{length(result.pois)}; " <>
      "first=#{short(List.first(result.pois))}"
  end

  defp compact_result(other), do: summary(other)

  defp compact_new_result({:ok, %NewResult{} = result}) do
    "count=#{inspect(result.count)} (#{type_of(result.count)}) rows=#{length(result.pois)}; " <>
      "first=#{short(List.first(result.pois))}"
  end

  defp compact_new_result(other), do: summary(other)

  defp mapped_extension_report({:ok, %Result{pois: [%Poi{} = poi | _]}}) do
    "website=#{inspect(poi.website)} photos=#{length(poi.photos)} " <>
      "biz_ext=#{inspect(poi.biz_ext)} indoor_data=#{inspect(poi.indoor_data)}"
  end

  defp mapped_extension_report({:ok, %Result{pois: []}}), do: "no rows"
  defp mapped_extension_report(other), do: summary(other)

  defp tips_report({:ok, %TipsResult{} = result}) do
    "count=#{inspect(result.count)} (#{type_of(result.count)}) tips=#{length(result.tips)}; " <>
      "first=#{short(List.first(result.tips))}"
  end

  defp tips_report(other), do: summary(other)

  defp page_ids({:ok, %Result{pois: first}}, {:ok, %Result{pois: second}}) do
    ids = fn pois -> Enum.map(pois, & &1.id) end
    "page=1 #{inspect(ids.(first))} vs page=2 #{inspect(ids.(second))}"
  end

  defp page_ids(_first, _second), do: "a call was refused"

  defp count_vs_rows({:ok, one}, {:ok, two}, {:ok, beyond}) do
    "p1 count=#{inspect(one.count)} rows=#{length(one.pois)} ids=#{inspect(Enum.map(one.pois, & &1.id))}; " <>
      "p2 count=#{inspect(two.count)} rows=#{length(two.pois)} ids=#{inspect(Enum.map(two.pois, & &1.id))}; " <>
      "p21 count=#{inspect(beyond.count)} rows=#{length(beyond.pois)}"
  end

  defp count_vs_rows(_one, _two, _beyond), do: "a call was refused"

  defp first_ids({:ok, %TipsResult{tips: tips}}), do: inspect(Enum.map(tips, & &1.id))
  defp first_ids(other), do: summary(other)

  defp short(nil), do: "none"

  defp short(value) when is_map(value),
    do: "#{inspect(value.__struct__)} #{truncate(inspect(value))}"

  defp short(value), do: truncate(inspect(value))

  defp truncate(string), do: String.slice(string, 0, 160)

  # --- shape assertions and summaries ------------------------------------------

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

  defp summary({:ok, value}), do: "ok: #{truncate(inspect(value))}"

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
