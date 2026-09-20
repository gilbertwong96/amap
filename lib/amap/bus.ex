defmodule Amap.Bus do
  @moduledoc """
  公交信息查询 — the stops a bus line serves, and the lines that serve a stop.

  Four endpoints, two pairs. `stopid/3` and `stopname/3` look up stations and
  answer with `busstops[]`, each station carrying a summary of the lines that
  pass through it; `lineid/3` and `linename/3` look up lines and answer with
  `buslines[]`, each line carrying the stops it serves. Every response also
  carries `count`, which Amap sends as a **string** on this family.

  What the pages and the wire disagree about, kept here because a caller would
  otherwise meet it a call at a time:

    * `city` is **optional on both keyword searches**. `stopname`'s page row says
      必填=否, and a probe without it answered the same three stations; `linename`'s
      page row says 必填=是 while its own rule text — and the wire — say 「默认值：
      全国」 (the whole country), so a `linename` call without a city really does
      search nationwide.
    * `offset` and `page` follow each endpoint's own row: `stopname` takes up to
      100 pages of 100 rows, `linename` up to 10. A value above an endpoint's
      ceiling raises, rather than letting Amap answer its default page instead of
      the one asked for.
    * The two station pages document `extensions=base` only; the line pages
      document `base` and `all`.
    * `output` is never exposed: the SDK asks for JSON, which Amap defaults to.

  The keyword searches can carry Amap's `suggestion` list, which has been empty in
  every probe so far. It is carried as `Amap.Bus.Suggestion`; the search batch may
  own a richer version of that type later.
  """

  alias Amap.Bus.Stop
  alias Amap.Bus.Stops
  alias Amap.Bus.Suggestion
  alias Amap.Coord
  alias Amap.Validate

  @stopid_path "/v3/bus/stopid"
  @stopname_path "/v3/bus/stopname"
  @max_offset 100
  @max_page 100

  @doc """
  Reads the stations a bus stop id names.

  `id` is a stop id such as `"BV10006672"`. The answer is usually one station,
  whose `buslines` field lists the lines serving it as five-field summaries.
  """
  @spec stopid(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, Stops.t()} | {:error, Amap.Error.t()}
  def stopid(client, id, opts \\ []) do
    params = [
      id: Validate.present!(id, ":id"),
      extensions: station_extensions(opts)
    ]

    stop_result(client, @stopid_path, params)
  end

  @doc """
  Searches stations by name.

  `keywords` is a single keyword. `:city` narrows the search and may be an
  adcode, a citycode or a name; **leaving it out searches the whole country**,
  which the page permits and a probe confirmed. `:offset` (1..100) and `:page`
  (1..100) walk the answer, whose rows Amap caps at 100 per page; neither is sent
  unless given, so Amap's own defaults (20 and 1) apply.
  """
  @spec stopname(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, Stops.t()} | {:error, Amap.Error.t()}
  def stopname(client, keywords, opts \\ []) do
    params = [
      keywords: Validate.present!(keywords, ":keywords"),
      city: Validate.optional_present!(Keyword.get(opts, :city), ":city"),
      offset: Validate.optional_range!(Keyword.get(opts, :offset), ":offset", 1, @max_offset),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, @max_page),
      extensions: station_extensions(opts)
    ]

    stop_result(client, @stopname_path, params)
  end

  defp stop_result(client, path, params) do
    case Amap.request(client, :restapi, :get, path, params) do
      {:ok, payload} -> {:ok, to_stops(payload)}
      {:error, _} = error -> error
    end
  end

  # The station pages document `base` and no other value; the line pages document
  # `base`/`all`. Only what an endpoint's own page promises reaches the wire.
  defp station_extensions(opts) do
    Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base])
  end

  defp to_stops(payload) do
    %Stops{
      count: payload["count"],
      suggestion: to_suggestion(payload["suggestion"]),
      busstops: Enum.map(payload["busstops"] || [], &to_stop/1)
    }
  end

  defp to_suggestion(nil), do: nil

  defp to_suggestion(payload) do
    %Suggestion{keywords: payload["keywords"] || [], cities: payload["cities"] || []}
  end

  defp to_stop(payload) do
    %Stop{
      id: payload["id"],
      name: payload["name"],
      location: Coord.parse_location(payload["location"]),
      adcode: payload["adcode"],
      citycode: payload["citycode"],
      buslines: Enum.map(payload["buslines"] || [], &to_stop_busline/1)
    }
  end

  defp to_stop_busline(payload) do
    %Stop.Busline{
      id: payload["id"],
      location: Coord.parse_location(payload["location"]),
      name: payload["name"],
      start_stop: payload["start_stop"],
      end_stop: payload["end_stop"]
    }
  end
end
