defmodule Amap.NewPlace do
  @moduledoc """
  搜索POI 2.0 — searching Amap's places on the v5 page (`guide/api-advanced/newpoisearch`).

  The same four questions `Amap.Place` asks — `text/2` 关键字搜索, `around/3` 周边搜索,
  `polygon/3` 多边形区域搜索, `detail/3` ID 搜索 — put to the newer service, which answers
  differently in three ways worth knowing before the first surprise:

    * **Paging is `page_size`/`page_num`**, not v3's `offset`/`page`: `page_size` is 1..25
      (default 10), `page_num` defaults to 1, and Amap answers at most **200 rows** for one
      set of request parameters (同请求参数翻页查询最多支持获取200条数据) — so `page_num` is
      held to 1..200 here, the last page the ceiling can still fill. `count` on this page is
      单次请求返回的实际 poi 点的个数, the POIs this one request returned.
    * **`region` is a weight, not a filter** — 增加指定区域内数据召回权重 — and only
      `city_limit: true` restricts the answer to it (仅召回 region 对应区域内数据). `region`
      takes a citycode, an adcode or a city-level Chinese name.
    * **`show_fields` names the optional groups** (`children`, `business`, `indoor`, `navi`,
      `photos`); unset returns base fields only, and a group that was not asked for leaves
      its fields `nil`. Amap **ignores** a group it does not know and answers `ok` with base
      fields, so this module refuses an unknown group instead — a typo would otherwise look
      like a request Amap chose to answer partly.

  The keywords rule is the page's 二选一必填 (one of `keywords` or `types`), and the 2.0
  page caps a keyword at **80 characters** on all three of its keyword endpoints, which the
  SDK checks before sending. `detail` takes **up to ten** ids, `|`-separated, where v3 takes
  one. `:lang_code` is `:zh` or `:en` and marks the English search 高级服务 (premium), as
  on v3.

  The answer is `Amap.NewPlace.Result` and, per row, `Amap.NewPlace.Poi` — a shallower
  struct than v3's, because this page nests `parking_type`, `alias`, `rating`, `cost` and
  the indoor block under `business`/`indoor` where v3 keeps them flat.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> {:ok, base} = Amap.NewPlace.text(client, keywords: "北京大学")
      iex> [poi] = base.pois
      iex> {poi.business, poi.indoor}
      {nil, nil}
      iex> {:ok, asked} =
      ...>   Amap.NewPlace.text(client, keywords: "北京大学", show_fields: [:business])
      iex> Enum.map(asked.pois, & &1.business.rating)
      ["4.7"]
      iex> Amap.NewPlace.text(client, keywords: "北京大学", show_fields: [:business, :typo])
      ** (ArgumentError) :show_fields must be a subset of [:children, :business, :indoor, :navi, :photos], got unknown: [:typo]

  A group `:show_fields` did not ask for leaves its fields `nil`, and Amap
  **ignores** a group its page does not know while answering `ok` with base fields,
  so a typo would look like a request Amap chose to answer partly. This module
  refuses it instead.
  """

  alias Amap.Coord
  alias Amap.NewPlace.Business
  alias Amap.NewPlace.Child
  alias Amap.NewPlace.Indoor
  alias Amap.NewPlace.Navi
  alias Amap.NewPlace.Photo
  alias Amap.NewPlace.Poi
  alias Amap.NewPlace.Result
  alias Amap.Param
  alias Amap.Search
  alias Amap.Validate

  @text_path "/v5/place/text"
  @around_path "/v5/place/around"
  @polygon_path "/v5/place/polygon"
  @detail_path "/v5/place/detail"

  @show_fields ~w(children business indoor navi photos)a
  @max_keywords_length 80
  @max_page_size 25
  # 同请求参数翻页查询最多支持获取200条数据 — with at least one row per page, page 201 can
  # only ask beyond the ceiling.
  @max_page_num 200
  @max_detail_ids 10

  @doc """
  Searches places by keyword, by category, or by both — 关键字搜索.

  One of `:keywords` or `:types` is required (二选一必填), which is why both are options
  rather than a positional argument; a keyword is at most **80 characters** and `:types` is
  a list joined with `|`. `:region` adds recall weight for a city without restricting the
  answer unless `:city_limit` is `true`.

  `:show_fields` names the optional groups to return — `:children`, `:business`, `:indoor`,
  `:navi`, `:photos` — comma-joined on the wire; a group not asked for leaves its fields
  `nil`. `:page_size` (1..25, Amap's default 10) and `:page_num` (1..200) walk the answer;
  neither is sent unless given.

  Returns `Amap.NewPlace.Result`.
  """
  @spec text(Amap.Client.t(), keyword()) :: {:ok, Result.t()} | {:error, Amap.Error.t()}
  def text(client, opts \\ []) do
    params =
      Search.keyword_or_types(opts, @max_keywords_length) ++
        [
          region: Validate.optional_present!(Keyword.get(opts, :region), ":region"),
          city_limit:
            Validate.optional_boolean!(Keyword.get(opts, :city_limit), ":city_limit", as: :bool),
          show_fields: show_fields(opts),
          page_size: page_size(opts),
          page_num: page_num(opts),
          langCode: Search.lang_code(Keyword.get(opts, :lang_code))
        ]

    Search.fetch(client, @text_path, params, &to_result/1)
  end

  @doc """
  Searches places around a centre — 周边搜索.

  `location` is one `{lon, lat}` tuple; this page, like v3's, takes no multiple centres.
  `:keywords` and `:types` are both optional, and when both are left out Amap substitutes
  餐饮服务, 生活服务 and 商务住宅, so the module sends nothing rather than making up the
  defaults. A keyword here is capped at 80 characters too.

  `:radius` is 0..50000 metres, default 5000; the page says a value above 50000 falls back
  to the default, so the SDK refuses it rather than silently searching 5 km. `:sortrule` is
  `:distance` (Amap's default) or `:weight`, and distance ordering does not take effect
  when only `:keywords` is sent. `:region` and the rest are `text/2`'s.
  """
  @spec around(Amap.Client.t(), {number(), number()}, keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def around(client, location, opts \\ []) do
    params = [
      location: location |> Validate.point!(":location") |> Param.location(),
      keywords: Search.keyword(Keyword.get(opts, :keywords), @max_keywords_length),
      types: Search.types(Keyword.get(opts, :types), ":types"),
      radius: Validate.optional_range!(Keyword.get(opts, :radius), ":radius", 0, 50_000),
      sortrule:
        Validate.optional_enum!(Keyword.get(opts, :sortrule), ":sortrule", [:distance, :weight]),
      region: Validate.optional_present!(Keyword.get(opts, :region), ":region"),
      city_limit:
        Validate.optional_boolean!(Keyword.get(opts, :city_limit), ":city_limit", as: :bool),
      show_fields: show_fields(opts),
      page_size: page_size(opts),
      page_num: page_num(opts),
      langCode: Search.lang_code(Keyword.get(opts, :lang_code))
    ]

    Search.fetch(client, @around_path, params, &to_result/1)
  end

  @doc """
  Searches places inside a polygon — 多边形区域搜索.

  `polygon` is a non-empty list of `{lon, lat}` pairs joined with `|`, **longitude first**:
  a rectangle is its two corners, anything else repeats the first pair at the end. Both
  generation's polygon searches share `Amap.Search.polygon/1` because both pages state the
  same rule.

  `:keywords` and `:types` are optional here and Amap substitutes 商务住宅 and 交通设施服务
  when both are left out — the same two as v3's polygon search. This endpoint has no
  `:region`, `:city_limit`, `:radius` or `:sortrule`.
  """
  @spec polygon(Amap.Client.t(), [{number(), number()}], keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def polygon(client, polygon, opts \\ []) do
    params = [
      polygon: Search.polygon(polygon),
      keywords: Search.keyword(Keyword.get(opts, :keywords), @max_keywords_length),
      types: Search.types(Keyword.get(opts, :types), ":types"),
      show_fields: show_fields(opts),
      page_size: page_size(opts),
      page_num: page_num(opts),
      langCode: Search.lang_code(Keyword.get(opts, :lang_code))
    ]

    Search.fetch(client, @polygon_path, params, &to_result/1)
  end

  @doc """
  Reads up to ten POIs by id — ID 搜索.

  `id` is one POI id or a list of up to ten; a list reaches the wire `|`-separated, as the
  page's own sample does. v3's `Amap.Place.detail/3` takes one.

  Only `:show_fields` and `:lang_code` are documented beside the ids. The 2.0 detail table
  lists no `count`, but the service sends one anyway — a two-id call answered `count "2"` —
  so `Result.count` carries the string as sent. `atag` — a field the other three endpoints
  do not return — is read here.
  """
  @spec detail(Amap.Client.t(), String.t() | [String.t()], keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def detail(client, id, opts \\ []) do
    params = [
      id: encode_ids!(id),
      show_fields: show_fields(opts),
      langCode: Search.lang_code(Keyword.get(opts, :lang_code))
    ]

    Search.fetch(client, @detail_path, params, &to_result/1)
  end

  defp show_fields(opts) do
    Validate.optional_show_fields!(
      Keyword.get(opts, :show_fields),
      ":show_fields",
      @show_fields
    )
  end

  defp page_size(opts) do
    Validate.optional_range!(Keyword.get(opts, :page_size), ":page_size", 1, @max_page_size)
  end

  defp page_num(opts) do
    Validate.optional_range!(Keyword.get(opts, :page_num), ":page_num", 1, @max_page_num)
  end

  defp encode_ids!(id) when is_binary(id), do: Validate.present!(id, ":id")

  defp encode_ids!(ids) when is_list(ids) do
    count = length(ids)

    cond do
      count == 0 ->
        raise ArgumentError,
              ":id must be a non-empty string or a list of 1..#{@max_detail_ids} ids, got: []"

      count > @max_detail_ids ->
        raise ArgumentError, ":id must be at most #{@max_detail_ids} ids, got: #{count}"

      true ->
        ids |> Enum.map(&Validate.present!(&1, ":id")) |> Param.pipe()
    end
  end

  defp encode_ids!(other) do
    raise ArgumentError,
          ":id must be a non-empty string or a list of 1..#{@max_detail_ids} ids, " <>
            "got: #{inspect(other)}"
  end

  defp to_result(payload) do
    %Result{count: payload["count"], pois: Search.pois(payload, &to_poi/1)}
  end

  defp to_poi(payload) do
    %Poi{
      name: payload["name"],
      id: payload["id"],
      parent: payload["parent"],
      distance: payload["distance"],
      location: Coord.parse_location(payload["location"]),
      type: payload["type"],
      typecode: payload["typecode"],
      pname: payload["pname"],
      cityname: payload["cityname"],
      adname: payload["adname"],
      address: payload["address"],
      pcode: payload["pcode"],
      adcode: payload["adcode"],
      citycode: payload["citycode"],
      atag: payload["atag"],
      children: to_list_or_object(payload["children"], &to_child/1),
      business: to_object(payload["business"], &to_business/1),
      indoor: to_object(payload["indoor"], &to_indoor/1),
      navi: to_object(payload["navi"], &to_navi/1),
      photos: to_list_or_object(payload["photos"], &to_photo/1)
    }
  end

  # The page prints every group as an `object` whose fields follow, which cannot say
  # whether one child or several arrive. Both shapes are kept as sent rather than
  # normalised: the run has only shown lists, and the object branch stays because the
  # page draws every group as one and no run has sent one.
  defp to_list_or_object(nil, _mapper), do: nil

  defp to_list_or_object(list, mapper) when is_list(list),
    do: list |> Enum.filter(&is_map/1) |> Enum.map(mapper)

  defp to_list_or_object(payload, mapper) when is_map(payload), do: mapper.(payload)
  defp to_list_or_object(_other, _mapper), do: nil

  defp to_object(nil, _mapper), do: nil
  defp to_object(payload, mapper) when is_map(payload), do: mapper.(payload)
  defp to_object(_other, _mapper), do: nil

  defp to_child(payload) do
    %Child{
      id: payload["id"],
      name: payload["name"],
      location: Coord.parse_location(payload["location"]),
      address: payload["address"],
      subtype: payload["subtype"],
      typecode: payload["typecode"],
      sname: payload["sname"]
    }
  end

  defp to_business(payload) do
    %Business{
      business_area: payload["business_area"],
      opentime_today: payload["opentime_today"],
      opentime_week: payload["opentime_week"],
      tel: payload["tel"],
      tag: payload["tag"],
      rating: payload["rating"],
      cost: payload["cost"],
      parking_type: payload["parking_type"],
      alias: payload["alias"],
      keytag: payload["keytag"],
      rectag: payload["rectag"]
    }
  end

  defp to_indoor(payload) do
    %Indoor{
      indoor_map: payload["indoor_map"],
      cpid: payload["cpid"],
      floor: payload["floor"],
      truefloor: payload["truefloor"]
    }
  end

  defp to_navi(payload) do
    %Navi{
      navi_poiid: payload["navi_poiid"],
      entr_location: Coord.parse_location(payload["entr_location"]),
      exit_location: Coord.parse_location(payload["exit_location"]),
      gridcode: payload["gridcode"]
    }
  end

  defp to_photo(payload), do: %Photo{title: payload["title"], url: payload["url"]}
end
