defmodule Amap.Search do
  @moduledoc """
  What the search pages share.

  `Amap.Place` covers Amap's v3 搜索POI page (`/v3/place/*`), `Amap.NewPlace` its v5 搜索POI
  2.0 page (`/v5/place/*`), and `Amap.InputTips` the 输入提示 page. The three ask different
  questions and answer with different structures; what lives here is what is the same on all
  of them, because it is Amap's own convention rather than any page's:

    * the category list — `types` on the place searches, `type` on 输入提示 — a non-empty
      list joined with `|`;
    * the rule both 关键字搜索 pages state as 二选一必填 (`keywords` or `types`, one of the
      two), which `keyword_or_types/2` enforces, together with the v5 pages'
      80-character keyword limit when it is asked for;
    * the `polygon` parameter both polygon searches take: one ring of `{lon, lat}` pairs
      joined with `|`, **longitude first** — 经度在前，纬度在后. `Amap.Param.polygon/1` is
      latitude-first (Falcon's rule for its own search endpoints) and reusing it here
      would transpose every vertex without the request failing;
    * the `pois.poi[]` wrapper both generations answer with;
    * the GET-and-map step every endpoint in the family takes.

  The v3 and v5 place searches are two modules, as `Amap.Direction` and `Amap.NewRoute` are
  for the two routing generations: the two pages put the same fields at different depths
  (v3 keeps `parking_type`, `alias`, `rating` and `cost` flat on a poi, v5 nests them under
  `business` and `indoor`), and one struct cannot hold both shapes.
  """

  alias Amap.Param
  alias Amap.Validate

  @doc """
  Encodes a category list: `["住宿服务", "餐饮服务"]` becomes `住宿服务|餐饮服务`.

  Both 关键字搜索 pages take `types` and 输入提示 takes the singular `type`, and all three
  want several categories joined with `|`. A bare string is refused rather than passed
  through, because the encoder joins a *list* and a string would be split character by
  character.
  """
  @spec types(Validate.input(), String.t()) :: String.t() | nil
  def types(nil, _field), do: nil

  def types(values, field) when is_list(values) and values != [] do
    Enum.each(values, fn value ->
      if not is_binary(value) or value == "" do
        raise ArgumentError,
              "#{field} must be a list of non-empty strings, got: #{inspect(values)}"
      end
    end)

    Param.pipe(values)
  end

  def types(values, field) do
    raise ArgumentError,
          "#{field} must be a non-empty list of non-empty strings, got: #{inspect(values)}"
  end

  @doc """
  Validates an optional keyword, with the v5 pages' 80-character rule when it is given.

  The length is optional because only the 2.0 pages state it (文本总长度不可超过80字符) and
  they state it on every keyword endpoint, which is why `around/3` and `polygon/3` use this
  rather than `optional_present!` directly.
  """
  @spec keyword(Validate.input(), pos_integer() | nil) :: String.t() | nil
  def keyword(value, max_length \\ nil) do
    value
    |> Validate.optional_present!(":keywords")
    |> validate_length(max_length)
  end

  @doc """
  Validates the one-of pair the two 关键字搜索 pages state — `keywords` or `types`.

  Returns the two as a keyword list, the one that was not given as `nil`, for a function to
  splice into its parameters. Neither given raises, because Amap would answer `20001
  MISSING_REQUIRED_PARAMS` without naming the field.

  `max_keywords_length` is the v5 pages' 80-character rule (文本总长度不可超过80字符); the v3
  pages state no length, so it is optional and unset means no length check.
  """
  @spec keyword_or_types(keyword(), pos_integer() | nil) :: keyword()
  def keyword_or_types(opts, max_keywords_length \\ nil) do
    keywords = keyword(Keyword.get(opts, :keywords), max_keywords_length)
    types = types(Keyword.get(opts, :types), ":types")

    if is_nil(keywords) and is_nil(types) do
      raise ArgumentError, "one of :keywords or :types is required"
    end

    [keywords: keywords, types: types]
  end

  defp validate_length(nil, _max), do: nil
  defp validate_length(keywords, nil), do: keywords

  defp validate_length(keywords, max) do
    if String.length(keywords) > max do
      raise ArgumentError,
            ":keywords must be at most #{max} characters, got: #{String.length(keywords)}"
    end

    keywords
  end

  @doc """
  Validates an optional `langCode`, the language every endpoint on all three pages takes.

  `:zh` is Amap's default and `:en` is the 高级服务 (premium) form — the pages say the
  English POI search needs a 工单 — so `:en` is exposed and either reaches the wire;
  whether the account may use it is Amap's answer to give.
  """
  @spec lang_code(Validate.input()) :: String.t() | nil
  def lang_code(value), do: Validate.optional_enum!(value, ":lang_code", [:zh, :en])

  @doc """
  Encodes the `polygon` parameter both polygon searches take.

  A non-empty list of `{lon, lat}` pairs joined with `|`, as both pages write it: a rectangle
  is two pairs, anything else repeats the first pair at the end. Amap reads the pairs
  **longitude first**; `Amap.Param.polygon/1` — latitude-first — is Falcon's and belongs to
  its own search endpoints.
  """
  @spec polygon(Validate.input()) :: String.t()
  def polygon(points) do
    points
    |> Validate.points!(":polygon")
    |> Enum.map_join("|", &Param.location/1)
  end

  @doc """
  Reads both generations' `pois` wrapper into a list of entries.

  The place searches nest their rows one level down (`pois.poi`), which `rows/4` unwraps;
  see it for the shapes an absent or emptied wrapper takes.
  """
  @spec pois(Amap.JSON.object(), (Amap.JSON.object() -> poi)) :: [poi] when poi: var
  def pois(payload, mapper), do: rows(payload, "pois", "poi", mapper)

  @doc """
  Reads a `{plural: {singular: [...]}}` wrapper — `pois.poi`, `tips.tip` — into rows.

  Amap nests these lists one level down; a bare list is read the same way because the
  pages also write the field as a list, and an absent or emptied wrapper —
  `Amap.Response` turns an empty array into `nil` — answers `[]`. An entry that is not an
  object is dropped rather than handed to a mapper.
  """
  @spec rows(Amap.JSON.object(), String.t(), String.t(), (Amap.JSON.object() -> row)) :: [row]
        when row: var
  def rows(payload, wrapper, singular, mapper) do
    payload
    |> Map.get(wrapper)
    |> row_list(singular)
    |> Enum.map(mapper)
  end

  defp row_list(wrapper, singular) when is_map(wrapper) do
    case wrapper[singular] do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _other -> []
    end
  end

  defp row_list(list, _singular) when is_list(list), do: Enum.filter(list, &is_map/1)
  defp row_list(_other, _singular), do: []

  @doc """
  Issues the family's GET and hands the payload to the mapper.

  Every endpoint in this batch is a `GET` on `restapi` whose endpoints differ only in the
  path, the parameters and which structs the answer becomes; the mapper is the last of
  those. A refusal is returned as an error, as every other module does.
  """
  @spec fetch(Amap.Client.t(), String.t(), keyword(), (Amap.Response.payload() -> result)) ::
          {:ok, result} | {:error, Amap.Error.t()}
        when result: var
  def fetch(client, path, params, mapper) do
    case Amap.request(client, :restapi, :get, path, params) do
      {:ok, payload} -> {:ok, mapper.(payload)}
      {:error, _} = error -> error
    end
  end
end
