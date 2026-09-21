defmodule Amap.District do
  @moduledoc """
  行政区域查询 — China's administrative divisions, and their boundaries.

  Every parameter on this endpoint is optional: `keywords` is a single area name,
  `citycode` or `adcode`, and Amap answers with that division plus as many levels
  of children as `subdistrict` asked for.

  What the page documents and a caller will otherwise trip over:

    * a 直辖市 — a municipality directly under the central government — appears at
      `level: "province"` and has no `city` of its own;
    * a street inherits its district's `adcode` instead of having one, so an
      `adcode` alone does not identify a street;
    * `polyline` comes back only down to district level, and a district made of
      separated pieces (朝阳区, Chaoyang district) separates each piece with `|`;
    * `center` is not a centroid — at street level it is a point on the boundary;
    * 东莞 and 文昌 (Dongguan and Wenchang) have no district level at all, so streets sit
      directly under the city, and Taiwan has no detailed division here.

  The answer carries Amap's `suggestion` list too, which is the only way to see
  what it thought was meant when a keyword matches nothing: `districts` is empty
  and `suggestion` is not.

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
      iex> {:ok, found} =
      ...>   Amap.District.district(client, keywords: "朝阳区", extensions: :all)
      iex> Enum.map(found.items, & &1.adcode)
      ["110105", "220104"]
      iex> [first | _] = found.items
      iex> {first.name, first.polyline}
      {"朝阳区", [[{116.4, 39.9}, {116.5, 39.95}], [{116.6, 40.0}]]}

  A keyword is not an identifier: 朝阳区 exists in more than one city, so one call
  can answer a list, and a repeated name is what two entries have in common. The
  same answer shows `extensions: :all` at work — `polyline` arrives only then, and
  a division made of separated pieces keeps them apart.

  When nothing matches, `items` is empty and Amap's `suggestion` says what it
  thought was meant — an empty answer is not a failure:

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> {:ok, missed} = Amap.District.district(client, keywords: "北金")
      iex> {missed.items, missed.suggestion.keywords}
      {[], ["北京"]}
  """

  alias Amap.Coord
  alias Amap.District.Result
  alias Amap.District.Suggestion
  alias Amap.Validate

  @path "/v3/config/district"
  @max_offset 20

  defstruct [:citycode, :adcode, :name, :polyline, :center, :level, districts: []]

  @type t :: %__MODULE__{
          citycode: String.t() | nil,
          adcode: String.t() | nil,
          name: String.t() | nil,
          polyline: [[{float(), float()}]] | nil,
          center: {float(), float()} | nil,
          level: String.t() | nil,
          districts: [t()]
        }

  @doc """
  Queries administrative divisions.

  `:keywords` is a single keyword — an area name, a `citycode` or an `adcode`.
  `:subdistrict` says how many levels of children to include (0 to 4; Amap's own
  default is 1). `:extensions` adds the boundary of the **queried** division and
  never its children's. `:filter` narrows the answer to one province or
  municipality by `adcode`, which the page strongly recommends. `:page` and
  `:offset` walk the outer list, which holds at most 20 divisions.
  """
  @spec district(Amap.Client.t(), keyword()) :: {:ok, Result.t()} | {:error, Amap.Error.t()}
  def district(client, opts \\ []) do
    params = [
      keywords: Validate.optional_present!(Keyword.get(opts, :keywords), ":keywords"),
      subdistrict:
        Validate.optional_range!(Keyword.get(opts, :subdistrict), ":subdistrict", 0, 4),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, 1_000_000),
      offset: Validate.optional_range!(Keyword.get(opts, :offset), ":offset", 1, @max_offset),
      extensions:
        Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all]),
      filter: Validate.optional_present!(Keyword.get(opts, :filter), ":filter")
    ]

    case Amap.request(client, :restapi, :get, @path, params) do
      {:ok, payload} -> {:ok, to_result(payload)}
      {:error, _} = error -> error
    end
  end

  defp to_result(payload) do
    %Result{
      items: Enum.map(payload["districts"] || [], &to_district/1),
      suggestion: to_suggestion(payload["suggestion"])
    }
  end

  defp to_suggestion(nil), do: nil

  defp to_suggestion(payload) do
    %Suggestion{keywords: payload["keywords"] || [], cities: payload["cities"] || []}
  end

  defp to_district(payload) do
    %__MODULE__{
      citycode: payload["citycode"],
      adcode: payload["adcode"],
      name: payload["name"],
      polyline: Coord.parse_polyline(payload["polyline"]),
      center: Coord.parse_location(payload["center"]),
      level: payload["level"],
      districts: Enum.map(payload["districts"] || [], &to_district/1)
    }
  end
end
