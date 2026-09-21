defmodule Amap.InputTips do
  @moduledoc """
  输入提示 — Amap's suggestions as a user types (`guide/api-advanced/inputtips`).

  One endpoint: `inputtips/3` on `/v3/assistant/inputtips`. It is the page beside the two
  place searches — same host, same family, no pagination — and it answers shorter rows:
  each tip has an `id`, a name, a district, an adcode, sometimes a location and an address,
  and nothing else. There is no `suggestion` field and no page/offset pair here, and the
  page documents no `langCode`.

  What its parameter table says, and what a caller otherwise trips over:

    * `keywords` is required and the only positional argument.
    * `type` — singular, where the place searches spell the same kind of list `types` — is
      a category list joined with `|`, and the page 强烈建议 using the six-digit codes
      (此处强烈建议使用分类代码，否则可能会得到不符合预期的结果).
    * `location` **only takes effect when `city` is also sent** (在请求参数 city 不为空时生效):
      it biases the suggestion towards that point rather than filtering by it.
    * `city` biases too (会尽量优先返回此城市数据); `citylimit` makes it strict. The
      parameter row allows a citycode or an adcode and says 不支持县级市 (county-level
      cities), while the page's sample table also lists city names — the value is passed
      through as given, so either reaches Amap.
    * `datatype` is `all` (Amap's default), `poi`, `bus` or `busline`, joined with `|`. The
      page contradicts itself: its parameter table marks the field 可选 with default `all`,
      its 服务示例 table marks it 必选. The SDK follows the parameter table and sends it only
      when the caller names it.

  The answer is `Amap.InputTips.Result` and, per row, `Amap.InputTips.Tip`. What matched
  decides what `id` is — a POI id, a bus id or a busline id — and a busline tip carries no
  `location` at all, which is the one shape a caller has to expect (`district` stays 省+市+区,
  or 市+区 for a 直辖市).

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
      iex> {:ok, result} = Amap.InputTips.inputtips(client, "招商银行")
      iex> {result.count, Enum.map(result.tips, &{&1.id, &1.location})}
      {"2", [{"B000A83M61", {116.45, 39.93}}, {"BV10002739", nil}]}

  One answer mixes kinds: the first tip is a POI with a location, the second a
  busline whose `location` is absent — the one shape a caller has to expect.
  """

  alias Amap.Coord
  alias Amap.InputTips.Result
  alias Amap.InputTips.Tip
  alias Amap.Param
  alias Amap.Search
  alias Amap.Validate

  @path "/v3/assistant/inputtips"
  @data_types [:all, :poi, :bus, :busline]

  @doc """
  Suggests places for a partial keyword.

  `keywords` is the text typed so far and is required. `:type` is the POI 分类 as a
  non-empty list joined with `|`; the page strongly advises six-digit category codes over
  names.

  `:location` is a `{lon, lat}` tuple and does nothing unless `:city` is given as well —
  the SDK sends it when asked and documents the page's condition rather than hiding it.
  `:city` takes a citycode or an adcode (the sample table also shows names) and `:city_limit`
  makes it strict. `:datatype` is a non-empty list of `:all`, `:poi`, `:bus`, `:busline`
  joined with `|`, sent only when named.

  Returns `Amap.InputTips.Result`: the tips, and Amap's count as the string it sent.
  """
  @spec inputtips(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Amap.Error.t()}
  def inputtips(client, keywords, opts \\ []) do
    params = [
      keywords: Validate.present!(keywords, ":keywords"),
      type: Search.types(Keyword.get(opts, :type), ":type"),
      location: location(opts),
      city: Validate.optional_present!(Keyword.get(opts, :city), ":city"),
      citylimit:
        Validate.optional_boolean!(Keyword.get(opts, :city_limit), ":city_limit", as: :bool),
      datatype: datatype(opts)
    ]

    Search.fetch(client, @path, params, &to_result/1)
  end

  defp location(opts) do
    case Keyword.get(opts, :location) do
      nil -> nil
      value -> value |> Validate.point!(":location") |> Param.location()
    end
  end

  defp datatype(opts) do
    case Keyword.get(opts, :datatype) do
      nil ->
        nil

      values when is_list(values) and values != [] ->
        case Enum.reject(values, &(&1 in @data_types)) do
          [] ->
            Param.pipe(Enum.map(values, &Atom.to_string/1))

          unknown ->
            raise ArgumentError,
                  ":datatype must be a subset of #{inspect(@data_types)}, got unknown: " <>
                    "#{inspect(unknown)}"
        end

      other ->
        raise ArgumentError,
              ":datatype must be a non-empty list of #{inspect(@data_types)}, got: " <>
                "#{inspect(other)}"
    end
  end

  defp to_result(payload) do
    %Result{count: payload["count"], tips: Search.rows(payload, "tips", "tip", &to_tip/1)}
  end

  defp to_tip(payload) do
    %Tip{
      id: payload["id"],
      name: payload["name"],
      district: payload["district"],
      adcode: payload["adcode"],
      location: Coord.parse_location(payload["location"]),
      address: payload["address"]
    }
  end
end
