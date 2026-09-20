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

  alias Amap.Bus.Line
  alias Amap.Bus.Lines
  alias Amap.Bus.Stop
  alias Amap.Bus.Stops
  alias Amap.Bus.Suggestion
  alias Amap.Coord
  alias Amap.Validate

  @stopid_path "/v3/bus/stopid"
  @stopname_path "/v3/bus/stopname"
  @lineid_path "/v3/bus/lineid"
  @linename_path "/v3/bus/linename"
  @max_offset 100
  @max_page 100
  @max_line_page 10

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

  `keywords` is a single keyword. `:city` narrows the search and takes an
  adcode or a citycode; **leaving it out searches without a city restriction**,
  which the page permits (its row says 必填=否) and a probe confirmed — it
  answered the same stations as the with-city control. `:offset` (1..100) and
  `:page` (1..100) walk the answer, whose rows Amap caps at 100 per page;
  neither is sent unless given, so Amap's own defaults (20 and 1) apply.
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

  @doc """
  Reads the lines a bus route id names.

  `id` is a line id such as `"131000010042"`. The line's `busstops` list is the
  stops it serves, each with its `sequence` on the line; `extensions: :all` is
  what the page says brings the route's detail (terminals, times), while `:base`
  is the default.
  """
  @spec lineid(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, Lines.t()} | {:error, Amap.Error.t()}
  def lineid(client, id, opts \\ []) do
    params = [
      id: Validate.present!(id, ":id"),
      extensions: line_extensions(opts)
    ]

    line_result(client, @lineid_path, params)
  end

  @doc """
  Searches lines by name.

  `keywords` is a single keyword, such as `"地铁1号线"`. **`:city` is optional and
  leaving it out searches the whole country** — the page's own rule text says
  「默认值：全国」, and a probe without a city answered with lines from another
  city. `:offset` (1..100) and `:page` (1..10) walk the answer; Amap caps the
  pages at 10 on this endpoint, so a higher value raises rather than letting the
  service answer a different page. `extensions: :all` adds the route detail.
  """
  @spec linename(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, Lines.t()} | {:error, Amap.Error.t()}
  def linename(client, keywords, opts \\ []) do
    params = [
      keywords: Validate.present!(keywords, ":keywords"),
      city: Validate.optional_present!(Keyword.get(opts, :city), ":city"),
      offset: Validate.optional_range!(Keyword.get(opts, :offset), ":offset", 1, @max_offset),
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, @max_line_page),
      extensions: line_extensions(opts)
    ]

    line_result(client, @linename_path, params)
  end

  defp line_result(client, path, params) do
    case Amap.request(client, :restapi, :get, path, params) do
      {:ok, payload} -> {:ok, to_lines(payload)}
      {:error, _} = error -> error
    end
  end

  # The station pages document `base` and no other value; the line pages document
  # `base`/`all`. Only what an endpoint's own page promises reaches the wire.
  defp station_extensions(opts) do
    Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base])
  end

  # The line pages document both values; `all` adds the route's detail (terminals,
  # times), while the station pages document `base` only.
  defp line_extensions(opts) do
    Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all])
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

  defp to_lines(payload) do
    %Lines{
      count: payload["count"],
      suggestion: to_suggestion(payload["suggestion"]),
      buslines: Enum.map(payload["buslines"] || [], &to_line/1)
    }
  end

  defp to_line(payload) do
    %Line{
      id: payload["id"],
      type: payload["type"],
      name: payload["name"],
      polyline: Coord.parse_polyline(payload["polyline"]),
      citycode: payload["citycode"],
      start_stop: payload["start_stop"],
      end_stop: payload["end_stop"],
      start_time: payload["start_time"],
      end_time: payload["end_time"],
      uicolor: payload["uicolor"],
      timedesc: payload["timedesc"],
      distance: payload["distance"],
      loop: payload["loop"],
      status: payload["status"],
      direc: payload["direc"],
      company: payload["company"],
      basic_price: payload["basic_price"],
      total_price: payload["total_price"],
      bounds: Coord.parse_locations(payload["bounds"]),
      busstops: Enum.map(payload["busstops"] || [], &to_line_stop/1)
    }
  end

  defp to_line_stop(payload) do
    %Line.Stop{
      id: payload["id"],
      name: payload["name"],
      location: Coord.parse_location(payload["location"]),
      sequence: payload["sequence"]
    }
  end
end
