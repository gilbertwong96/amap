defmodule Amap.Place do
  @moduledoc """
  搜索POI — searching Amap's places on the v3 page (`guide/api-advanced/search`).

  Four endpoints: `text/2` 关键字搜索, `around/3` 周边搜索, `polygon/3` 多边形搜索 and
  `detail/3` ID 查询. `Amap.NewPlace` asks the same four questions of v5's 搜索POI 2.0
  page, where the parameters (`page_size`/`page_num`/`show_fields`/`region`) and the
  answer's field depth differ; `Amap.InputTips` is the 输入提示 page beside them.

  What the pages say about searching, kept here because a caller otherwise meets it a call
  at a time:

    * `text` needs **one of `keywords` or `types`** — 二选一必填 — while `around` and
      `polygon` need neither and Amap substitutes `types` when both are left out:
      `050000` (餐饮服务), `070000` (生活服务) and `120000` (商务住宅) around a point;
      `120000` and `150000` (交通设施服务) inside a polygon.
    * `city` **biases rather than filters** — 会尽量优先返回此城市数据 — and only
      `city_limit: true` restricts the answer to it. Without a `city`, a generic keyword
      美食 answers a city list with per-city counts instead of POIs, which arrives as
      `Amap.Place.Result.suggestion`.
    * Paging is `offset` (每页记录数据, default 20) and `page` (default 1), and Amap answers
      at most **200 rows** for one set of request parameters. The page strongly advises
      `offset` ≤ 25 and warns that more 「可能造成访问报错」, so the SDK refuses an offset
      above 25 rather than risk the opaque error, and holds both options to their
      documented ranges. Neither default is sent, so an option left out is Amap's own.
    * `extensions: :all` carries the fields the response tree marks `extensions=all`, and
      `children` (0/1) folds sub-POIs under their parent; the page says it takes effect
      only with `extensions=all` or unset.
    * `:lang_code` is `:zh` (default) or `:en`, and the page marks the English POI search
      高级服务 (premium, opened by 工单): a key without that ticket is refused by Amap, not
      here.
    * `detail` takes **one** id at most, and its own page carries its gate — 如果未能获取到
      POI详情，请联系商务并提交工单申请高级权限 — so it can refuse while the three searches
      work on the same key.

  All four answers share one response tree and therefore one struct pair: `Amap.Place.Result`
  and, per row, `Amap.Place.Poi`. Every coordinate — `location`, `entr_location`,
  `exit_location` — comes back a `{lon, lat}` tuple.

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
      iex> {:ok, vague} = Amap.Place.text(client, keywords: "美食")
      iex> {vague.pois, Enum.map(vague.suggestion.cities, & &1.name)}
      {[], ["北京市", "上海市"]}
      iex> {:ok, scoped} = Amap.Place.text(client, keywords: "美食", city: "北京")
      iex> Enum.map(scoped.pois, & &1.name)
      ["烤鸭店"]

  `:city` biases rather than filters, and without it a generic keyword is answered
  with the cities that keyword could mean instead of POIs — that list is the
  `suggestion`, so an empty `pois` is an answer rather than a failure.

  `text/2` needs one of `:keywords` or `:types`, and says so locally:

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> Amap.Place.text(client, city: "北京")
      ** (ArgumentError) one of :keywords or :types is required
  """

  alias Amap.Coord
  alias Amap.Param
  alias Amap.Place.BizExt
  alias Amap.Place.IndoorData
  alias Amap.Place.Photo
  alias Amap.Place.Poi
  alias Amap.Place.Result
  alias Amap.Place.Suggestion
  alias Amap.Search
  alias Amap.Validate

  @text_path "/v3/place/text"
  @around_path "/v3/place/around"
  @polygon_path "/v3/place/polygon"
  @detail_path "/v3/place/detail"

  # The page's own words are a strong advice (强烈建议不超过25) plus a warning that more
  # 「可能造成访问报错」, which this turns into the field name instead of an opaque error.
  @max_offset 25
  # Both generations' pages: 同请求参数翻页查询最多支持获取200条数据.
  @max_page 200

  @doc """
  Searches POIs by keyword, by category, or by both — 关键字搜索.

  One of `:keywords` or `:types` is required, which is why both are options here rather
  than a positional argument: `Amap.Place.text(client, types: ["141201"])` is as valid a
  call as one with a keyword. `:types` is a list, joined with `|`; the page's 6-digit
  codes pull in their child categories (指定 `010000` includes every `010xxx`).

  `:city` takes a name, a citycode or an adcode and biases the search; `:city_limit`
  makes it strict (「仅返回指定城市数据」). `:children` is `0` (sub-POIs shown, Amap's
  default) or `1` (folded under their parent), and the page says it takes effect only with
  `extensions: :all` or unset.

  `:offset` (1..25) and `:page` (1..200) walk the answer; leaving them out sends nothing,
  so Amap's defaults — 20 rows, page 1 — apply. See the module doc for why 25 and 200.

  Returns `Amap.Place.Result`: the POIs, the count, and Amap's suggestion when a generic
  keyword had nothing in the scope.
  """
  @spec text(Amap.Client.t(), keyword()) :: {:ok, Result.t()} | {:error, Amap.Error.t()}
  def text(client, opts \\ []) do
    params =
      Search.keyword_or_types(opts) ++
        [
          city: Validate.optional_present!(Keyword.get(opts, :city), ":city"),
          citylimit:
            Validate.optional_boolean!(Keyword.get(opts, :city_limit), ":city_limit", as: :bool),
          children: Validate.integer_one_of!(Keyword.get(opts, :children), ":children", [0, 1]),
          offset: Validate.optional_range!(Keyword.get(opts, :offset), ":offset", 1, @max_offset),
          page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, @max_page),
          extensions: extensions(opts),
          langCode: Search.lang_code(Keyword.get(opts, :lang_code))
        ]

    Search.fetch(client, @text_path, params, &to_result/1)
  end

  @doc """
  Searches POIs around a centre — 周边搜索.

  `location` is one `{lon, lat}` tuple, at most six decimals; the page takes no multiple
  centres here. `:keywords` and `:types` are both optional, and when both are left out
  Amap substitutes 餐饮服务, 生活服务 and 商务住宅 (the call still works, so this module
  sends nothing rather than making up the defaults).

  `:radius` is 0..50000 metres, default 5000, and the page says a value above 50000 falls
  back to the default rather than clamping — the SDK refuses it instead of silently
  searching a 5 km circle. `:sortrule` is `:distance` (Amap's default) or `:weight`, and
  the page notes that distance ordering does not take effect when only `:keywords` is
  sent. `:city` and the rest are `text/2`'s.
  """
  @spec around(Amap.Client.t(), {number(), number()}, keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def around(client, location, opts \\ []) do
    params = [
      location: location |> Validate.point!(":location") |> Param.location(),
      keywords: Validate.optional_present!(Keyword.get(opts, :keywords), ":keywords"),
      types: Search.types(Keyword.get(opts, :types), ":types"),
      radius: Validate.optional_range!(Keyword.get(opts, :radius), ":radius", 0, 50_000),
      sortrule:
        Validate.optional_enum!(Keyword.get(opts, :sortrule), ":sortrule", [:distance, :weight]),
      city: Validate.optional_present!(Keyword.get(opts, :city), ":city"),
      citylimit:
        Validate.optional_boolean!(Keyword.get(opts, :city_limit), ":city_limit", as: :bool),
      offset: Validate.optional_range!(Keyword.get(opts, :offset), ":offset", 1, @max_offset),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, @max_page),
      extensions: extensions(opts),
      langCode: Search.lang_code(Keyword.get(opts, :lang_code))
    ]

    Search.fetch(client, @around_path, params, &to_result/1)
  end

  @doc """
  Searches POIs inside a polygon — 多边形搜索.

  `polygon` is a non-empty list of `{lon, lat}` pairs joined with `|`, **longitude
  first**: a rectangle is its two corners, anything else repeats the first pair at the
  end, as the page's own sample does. This is the one encoder in the SDK that writes that
  separator — `Amap.Param.polygon/1` is Falcon's latitude-first form and
  `Amap.Param.polygon_lon_first/1` is the routing `|`-between-groups form — so
  `Amap.Search.polygon/1` owns it.

  `:keywords` and `:types` are optional with the same one-of-less substitution as
  `around/3`, except that the substituted categories are 商务住宅 and 交通设施服务.
  Paging and the rest are `text/2`'s; there is no `:city`, `:city_limit` or `:children`
  on this endpoint.
  """
  @spec polygon(Amap.Client.t(), [{number(), number()}], keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def polygon(client, polygon, opts \\ []) do
    params = [
      polygon: Search.polygon(polygon),
      keywords: Validate.optional_present!(Keyword.get(opts, :keywords), ":keywords"),
      types: Search.types(Keyword.get(opts, :types), ":types"),
      offset: Validate.optional_range!(Keyword.get(opts, :offset), ":offset", 1, @max_offset),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, @max_page),
      extensions: extensions(opts),
      langCode: Search.lang_code(Keyword.get(opts, :lang_code))
    ]

    Search.fetch(client, @polygon_path, params, &to_result/1)
  end

  @doc """
  Reads one POI by its id — ID 查询.

  `id` is one POI id and no more: the page says 最多可以传入1个 id, where v5's
  `Amap.NewPlace.detail/3` takes up to ten. Only `:lang_code` is documented beside it —
  no `extensions`, even though the response section points at the shared tree — so the
  fields that tree marks `extensions=all` are mapped from whatever arrives.

  The page carries its own gate (如果未能获取到 POI 详情，请联系商务并提交工单申请高级权限), so
  this endpoint may refuse on a key whose other searches work.
  """
  @spec detail(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def detail(client, id, opts \\ []) do
    params = [
      id: Validate.present!(id, ":id"),
      langCode: Search.lang_code(Keyword.get(opts, :lang_code))
    ]

    Search.fetch(client, @detail_path, params, &to_result/1)
  end

  defp extensions(opts) do
    Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all])
  end

  defp to_result(payload) do
    %Result{
      count: payload["count"],
      suggestion: to_suggestion(payload["suggestion"]),
      pois: Search.pois(payload, &to_poi/1)
    }
  end

  # The whole object is absent on an answer that carried none, and a value that is not an
  # object is not one either — both read as no suggestion rather than a crash.
  defp to_suggestion(payload) when is_map(payload) do
    %Suggestion{keywords: payload["keywords"] || [], cities: to_cities(payload["cities"])}
  end

  defp to_suggestion(_other), do: nil

  defp to_cities(list) when is_list(list),
    do: list |> Enum.filter(&is_map/1) |> Enum.map(&to_city/1)

  defp to_cities(_other), do: []

  defp to_city(payload) do
    %Suggestion.City{
      name: payload["name"],
      num: payload["num"],
      citycode: payload["citycode"],
      adcode: payload["adcode"]
    }
  end

  defp to_poi(payload) do
    %Poi{
      id: payload["id"],
      parent: payload["parent"],
      name: payload["name"],
      type: payload["type"],
      typecode: payload["typecode"],
      biz_type: payload["biz_type"],
      address: payload["address"],
      location: Coord.parse_location(payload["location"]),
      distance: payload["distance"],
      tel: payload["tel"],
      postcode: payload["postcode"],
      website: payload["website"],
      email: payload["email"],
      pcode: payload["pcode"],
      pname: payload["pname"],
      citycode: payload["citycode"],
      cityname: payload["cityname"],
      adcode: payload["adcode"],
      adname: payload["adname"],
      entr_location: Coord.parse_location(payload["entr_location"]),
      exit_location: Coord.parse_location(payload["exit_location"]),
      navi_poiid: payload["navi_poiid"],
      gridcode: payload["gridcode"],
      alias: payload["alias"],
      parking_type: payload["parking_type"],
      tag: payload["tag"],
      indoor_map: payload["indoor_map"],
      indoor_data: to_indoor_data(payload["indoor_data"]),
      groupbuy_num: payload["groupbuy_num"],
      business_area: payload["business_area"],
      atag: payload["atag"],
      discount_num: payload["discount_num"],
      biz_ext: to_biz_ext(payload["biz_ext"]),
      photos: to_photos(payload["photos"])
    }
  end

  defp to_indoor_data(payload) when is_map(payload) do
    %IndoorData{
      cpid: payload["cpid"],
      floor: payload["floor"],
      truefloor: payload["truefloor"]
    }
  end

  defp to_indoor_data(_other), do: nil

  defp to_biz_ext(payload) when is_map(payload) do
    %BizExt{
      rating: payload["rating"],
      cost: payload["cost"],
      meal_ordering: payload["meal_ordering"],
      seat_ordering: payload["seat_ordering"],
      ticket_ordering: payload["ticket_ordering"],
      hotel_ordering: payload["hotel_ordering"]
    }
  end

  defp to_biz_ext(_other), do: nil

  defp to_photos(list) when is_list(list),
    do: list |> Enum.filter(&is_map/1) |> Enum.map(&to_photo/1)

  defp to_photos(_other), do: []

  defp to_photo(payload), do: %Photo{title: payload["title"], url: payload["url"]}
end
