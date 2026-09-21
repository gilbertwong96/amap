defmodule Amap.Falcon.TerminalSearch do
  @moduledoc """
  Searching terminals: by keyword, around a point, inside a polygon, or inside
  an administrative district.

  All four answer with the same payload shape, so all four return
  `{:ok, %Amap.Falcon.TerminalSearch.Page{items: [...], count: n}}`.

  `filter` and `sort` are the two parameters Amap encodes rather than accepts as
  values. They are given here as Elixir terms:

      filter: [name: ["王师傅", "张师傅"], lastloctime: {:>=, 1_469_817_532}]
      sort: {:lastloctime, :desc}

  `filter` takes a `|`-separated exact list for `name`, a comparison for
  `lastloctime` (`:>=` for "has reported since", `:<` for "has not"), and plain
  strings for custom fields. `sort` accepts only `:lastloctime` and `:name`, in
  `:asc` or `:desc`. The names in the example are 王师傅 and 张师傅 — "Master Wang" and
  "Master Zhang", the ordinary way a driver is addressed.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, page} =
      ...>   Amap.Falcon.TerminalSearch.search(client, 1000, "王师傅",
      ...>     filter: [name: ["王师傅", "张师傅"], lastloctime: {:>=, 1_469_817_532}],
      ...>     sort: {:lastloctime, :desc}
      ...>   )
      iex> [driver] = page.items
      iex> {driver.tid, driver.location.longitude, driver.custom}
      {456, 114.158, %{"myfield" => "custom"}}

  The filter and sort are given as Elixir terms and encoded here: that call puts
  `name=王师傅|张师傅&&lastloctime>=1469817532` and `lastloctime:desc` on the wire.
  `location` is an object, as the search endpoints report it — the bare string is
  `Amap.Falcon.TerminalMonitor`'s form — and a field Amap returns that this SDK does
  not know is kept in `custom` rather than dropped.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, page} =
      ...>   Amap.Falcon.TerminalSearch.aroundsearch(client, 1000, {114.158, 22.279},
      ...>     radius: 1000
      ...>   )
      iex> [near] = page.items
      iex> {near.distance, near.name}
      {1200, "货车01"}

  `aroundsearch` takes the centre as a `{lon, lat}` tuple like everywhere else and
  puts it on the wire latitude-first, which is this endpoint's own order; `distance`
  is what only the around searches add.

  A `lastloctime` without an operator would silently select the wrong terminals, so
  it is refused by name rather than encoded:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TerminalSearch.search(client, 1000, "王师傅", filter: [lastloctime: "yesterday"])
      ** (ArgumentError) unsupported filter value for lastloctime: "yesterday"; expected {:>=, unix_seconds} for terminals that reported since, or {:<, unix_seconds} for those that have not

  A radius outside the endpoint's own 1–5000 metres is refused the same way:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TerminalSearch.aroundsearch(client, 1000, {114.158, 22.279}, radius: 0)
      ** (ArgumentError) :radius must be between 1 and 5000, got: 0
  """

  use Amap.Falcon.Paging, page: Amap.Falcon.TerminalSearch.Page, mapper: :to_result
  alias Amap.Falcon.TerminalSearch.Location
  alias Amap.Falcon.TerminalSearch.Page
  alias Amap.Falcon.TerminalSearch.Result
  alias Amap.Numeric
  alias Amap.Validate

  @base "/v1/track/terminal"

  # The keys Amap documents for a search result. Anything else in the payload is
  # one of the caller's custom track fields, collected into `custom` instead of
  # being dropped, without turning wire keys into atoms.
  @known_keys ~w(name tid desc createtime locatetime location props distance)

  @doc """
  Searches terminals by keyword, matching the name, the description or a custom
  field's contents.
  """
  @spec search(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, Page.t()} | {:error, Amap.Error.t()}
  def search(client, sid, keywords, opts \\ []) do
    params = [sid: sid, keywords: Validate.present!(keywords, ":keywords")] ++ common_params(opts)

    client
    |> Amap.request(:tsapi, :post, @base <> "/search", params)
    |> to_page()
  end

  @doc """
  Searches terminals within `radius` metres of `center`.

  `center` is a `{lon, lat}` tuple like everywhere else in this SDK; the wire
  format for this endpoint is latitude-first, which is handled here rather than
  left to the caller. `radius` is in metres, `1..5000`, and Amap applies its own
  default of 500 when it is not given.
  """
  @spec aroundsearch(Amap.Client.t(), integer(), {number(), number()}, keyword()) ::
          {:ok, Page.t()} | {:error, Amap.Error.t()}
  def aroundsearch(client, sid, center, opts \\ []) do
    params =
      [
        sid: sid,
        center: Amap.Param.lat_lng(center),
        radius: validate_radius(Keyword.get(opts, :radius))
      ] ++ common_params(opts)

    client
    |> Amap.request(:tsapi, :post, @base <> "/aroundsearch", params)
    |> to_page()
  end

  @doc """
  Searches terminals inside a polygon.

  `polygon` is a ring of `{lon, lat}` points, or a list of rings for several
  polygons at once — the wire form is latitude-first with rings joined by `;`
  and groups by `|`, which is handled here. Amap caps the total bounding area at
  3000 km², which this cannot check.
  """
  @spec polygonsearch(
          Amap.Client.t(),
          integer(),
          [{number(), number()}] | [[{number(), number()}]],
          keyword()
        ) :: {:ok, Page.t()} | {:error, Amap.Error.t()}
  def polygonsearch(client, sid, polygon, opts \\ []) do
    params = [sid: sid, polygon: Amap.Param.polygon(polygon)] ++ common_params(opts)

    client
    |> Amap.request(:tsapi, :post, @base <> "/polygonsearch", params)
    |> to_page()
  end

  @doc """
  Searches terminals inside an administrative district.

  `keywords` is a province, city or district name, or an adcode — Amap answers
  every region a two-piece district covers.
  """
  @spec districtsearch(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, Page.t()} | {:error, Amap.Error.t()}
  def districtsearch(client, sid, keywords, opts \\ []) do
    params = [sid: sid, keywords: Validate.present!(keywords, ":keywords")] ++ common_params(opts)

    client
    |> Amap.request(:tsapi, :post, @base <> "/districtsearch", params)
    |> to_page()
  end

  defp common_params(opts) do
    [
      filter: encode_filter(Keyword.get(opts, :filter)),
      sortrule: encode_sort(Keyword.get(opts, :sort)),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, 1_000_000),
      pagesize: Validate.optional_range!(Keyword.get(opts, :pagesize), ":pagesize", 1, 100)
    ]
  end

  defp encode_filter(nil), do: nil

  defp encode_filter(terms) when is_list(terms) do
    Enum.map_join(terms, "&&", fn {key, value} -> filter_term(to_string(key), value) end)
  end

  # Iodata rather than `"name=" <> …`: this is the one term assembled from another
  # string, and `encode_filter/1`'s `Enum.map_join/3` flattens chardata.
  defp filter_term("name", names) when is_list(names), do: ["name=", Enum.join(names, "|")]

  defp filter_term(key, {op, ts}) when op in [:>=, :<] and is_integer(ts),
    do: "#{key}#{op}#{ts}"

  # `lastloctime` is the one filter that needs an operator. A plain value here
  # would select the wrong terminals silently rather than fail, so it is rejected
  # by name instead of falling through to the generic clauses below.
  defp filter_term("lastloctime", value) do
    raise ArgumentError,
          "unsupported filter value for lastloctime: #{inspect(value)}; " <>
            "expected {:>=, unix_seconds} for terminals that reported since, " <>
            "or {:<, unix_seconds} for those that have not"
  end

  defp filter_term(key, value) when is_binary(value), do: "#{key}=#{value}"
  defp filter_term(key, value) when is_integer(value), do: "#{key}=#{value}"

  defp filter_term(key, value),
    do: raise(ArgumentError, "unsupported filter value for #{key}: #{inspect(value)}")

  defp encode_sort(nil), do: nil
  defp encode_sort({:lastloctime, dir}) when dir in [:asc, :desc], do: "lastloctime:#{dir}"
  defp encode_sort({:name, dir}) when dir in [:asc, :desc], do: "name:#{dir}"
  defp encode_sort(other), do: raise(ArgumentError, "unsupported sort: #{inspect(other)}")

  defp validate_radius(nil), do: nil
  defp validate_radius(radius), do: Validate.range!(radius, ":radius", 1, 5000)

  defp to_result(payload) do
    %Result{
      tid: Numeric.to_integer(payload["tid"]),
      name: payload["name"],
      desc: payload["desc"],
      createtime: Numeric.to_integer(payload["createtime"]),
      locatetime: Numeric.to_integer(payload["locatetime"]),
      location: to_location(payload["location"]),
      props: payload["props"],
      distance: payload["distance"],
      custom: Map.drop(payload, @known_keys)
    }
  end

  defp to_location(nil), do: nil

  defp to_location(payload) when is_map(payload) do
    %Location{
      latitude: payload["latitude"],
      longitude: payload["longitude"],
      speed: payload["speed"],
      direction: payload["direction"],
      height: payload["height"],
      accuracy: payload["accuracy"]
    }
  end
end
