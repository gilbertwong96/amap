defmodule Amap.Falcon.Geofence do
  @moduledoc """
  Falcon geofences — the virtual areas that answer whether something is inside.

  Four shapes exist, each with its own create and update endpoint: `circle`,
  `polygon`, `polyline` and `district`. A service holds **1000** of them; more
  than that needs a ticket from Amap.

  Coordinates are `{lon, lat}` tuples like everywhere else in this SDK, and Amap's
  wire form for them is `"lon,lat"` — **longitude first**, which is *not* the
  order the terminal-search endpoints' centre takes.

  Each shape's own parameters go in the options list rather than as positional
  arguments, because the four shapes need different ones; a missing one raises
  rather than sending a fence Amap will reject.
  """

  use Amap.Falcon.Paging, page: Amap.Falcon.Geofence.Page, mapper: :to_geofence_struct
  alias Amap.Falcon.Geofence.Page
  alias Amap.Falcon.Wire
  alias Amap.Numeric
  alias Amap.Param
  alias Amap.Validate

  defstruct [:gfid, :name, :desc, :shape, :points, :bufferradius, :createtime, :modifytime]

  @type t :: %__MODULE__{
          gfid: integer() | nil,
          name: String.t() | nil,
          desc: String.t() | nil,
          shape: Amap.JSON.object() | nil,
          points: String.t() | nil,
          bufferradius: integer() | nil,
          createtime: integer() | nil,
          modifytime: integer() | nil
        }

  @base "/v1/track/geofence"
  @shapes [:circle, :polygon, :polyline, :district]

  @doc """
  Creates a circular fence.

  `center` is a `{lon, lat}` tuple and `radius` is in metres, `1` to `50000`.
  """
  @spec add_circle(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def add_circle(client, sid, name, opts \\ []),
    do: create(client, sid, name, opts, :circle)

  @doc """
  Creates a polygonal fence.

  `points` is a ring of `{lon, lat}` tuples: 3 to 100 vertices, with a bounding box
  under 100 km² unless Amap has enabled the larger tier for your key by ticket.
  """
  @spec add_polygon(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def add_polygon(client, sid, name, opts \\ []),
    do: create(client, sid, name, opts, :polygon)

  @doc """
  Creates a linear fence — a corridor along a route.

  `points` is 2 to 100 coordinates along a route shorter than 500 km, and
  `bufferradius` is how far either side of it the fence reaches: `1` to `300`
  metres.
  """
  @spec add_polyline(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def add_polyline(client, sid, name, opts \\ []),
    do: create(client, sid, name, opts, :polyline)

  @doc """
  Creates a fence around an administrative district.

  `adcode` is Amap's district code, given as a string or an integer — the leading
  zeros some codes carry are why a string is accepted.
  """
  @spec add_district(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def add_district(client, sid, name, opts \\ []),
    do: create(client, sid, name, opts, :district)

  @doc "Updates a circular fence. `name` is required again, as Amap requires it."
  @spec update_circle(Amap.Client.t(), integer(), integer(), String.t(), keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def update_circle(client, sid, gfid, name, opts \\ []),
    do: change(client, sid, gfid, name, opts, :circle)

  @doc "Updates a polygonal fence."
  @spec update_polygon(Amap.Client.t(), integer(), integer(), String.t(), keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def update_polygon(client, sid, gfid, name, opts \\ []),
    do: change(client, sid, gfid, name, opts, :polygon)

  @doc "Updates a linear fence."
  @spec update_polyline(Amap.Client.t(), integer(), integer(), String.t(), keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def update_polyline(client, sid, gfid, name, opts \\ []),
    do: change(client, sid, gfid, name, opts, :polyline)

  @doc "Updates a district fence."
  @spec update_district(Amap.Client.t(), integer(), integer(), String.t(), keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def update_district(client, sid, gfid, name, opts \\ []),
    do: change(client, sid, gfid, name, opts, :district)

  @doc "Lists the shapes this module can build, for a caller that takes them as input."
  @spec shapes() :: [atom()]
  def shapes, do: @shapes

  @doc """
  Deletes fences.

  Pass at most 100 ids — Amap truncates a longer list silently rather than failing,
  so this raises instead — or `:all` to remove every fence in the service. `:all`
  answers `{:ok, nil}`, because Amap has nothing to enumerate; a list answers with
  the ids that were actually deleted.
  """
  @spec delete(Amap.Client.t(), integer(), [integer()] | :all) ::
          {:ok, [integer()] | nil} | {:error, Amap.Error.t()}
  def delete(client, sid, :all),
    do: Amap.request(client, :tsapi, :post, @base <> "/delete", sid: sid, gfids: "#all")

  def delete(client, sid, gfids) when is_list(gfids) do
    params = [sid: sid, gfids: Wire.ids!(gfids, ":gfids")]

    case Amap.request(client, :tsapi, :post, @base <> "/delete", params) do
      {:ok, payload} -> {:ok, Wire.decode_ids(payload["gfids"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Lists fences.

  `outputshape: true` adds each fence's `shape` object. `gfids` limits the answer to
  those ids and **turns pagination off** — Amap ignores `page` and `pagesize` in that
  case — while `page` and `pagesize` page through everything else, at most 100 at a
  time.
  """
  @spec list(Amap.Client.t(), integer(), keyword()) :: {:ok, Page.t()} | {:error, Amap.Error.t()}
  def list(client, sid, opts \\ []) do
    gfids = Keyword.get(opts, :gfids)

    params =
      [
        sid: sid,
        outputshape: Wire.flag!(Keyword.get(opts, :outputshape)),
        gfids: Wire.ids!(gfids, ":gfids")
      ] ++ Wire.pagination(opts, gfids)

    client
    |> Amap.request(:tsapi, :get, @base <> "/list", params)
    |> to_page()
  end

  # Amap ignores `page` and `pagesize` when `gfids` is given: see `Wire.pagination/2`.

  defp create(client, sid, name, opts, shape) do
    params =
      [sid: sid, name: Validate.name!(name, ":name"), desc: desc_param(opts)] ++
        shape_params(shape, opts)

    client
    |> Amap.request(:tsapi, :post, "#{@base}/add/#{shape}", params)
    |> to_geofence()
  end

  defp change(client, sid, gfid, name, opts, shape) do
    params =
      [sid: sid, gfid: gfid, name: Validate.name!(name, ":name"), desc: desc_param(opts)] ++
        shape_params(shape, opts)

    Amap.request(client, :tsapi, :post, "#{@base}/update/#{shape}", params)
  end

  # One builder per shape, used by both its create and its update, so the two
  # cannot drift apart.
  defp shape_params(:circle, opts) do
    [
      center: Param.location(required!(opts, :center)),
      radius: Validate.range!(required!(opts, :radius), ":radius", 1, 50_000)
    ]
  end

  defp shape_params(:polygon, opts) do
    points = required!(opts, :points)
    Validate.range!(length(points), ":points", 3, 100)

    [points: Param.locations(points)]
  end

  defp shape_params(:polyline, opts) do
    points = required!(opts, :points)
    Validate.range!(length(points), ":points", 2, 100)

    [
      points: Param.locations(points),
      bufferradius: Validate.range!(required!(opts, :bufferradius), ":bufferradius", 1, 300)
    ]
  end

  defp shape_params(:district, opts) do
    adcode = required!(opts, :adcode)

    if adcode in ["", nil] do
      raise ArgumentError, ":adcode must be a district code, got: #{inspect(adcode)}"
    end

    [adcode: adcode]
  end

  defp required!(opts, key) do
    case Keyword.get(opts, key) do
      nil -> raise ArgumentError, "#{inspect(key)} is required for this fence shape"
      value -> value
    end
  end

  defp desc_param(opts),
    do: Validate.optional!(&Validate.text!/2, Keyword.get(opts, :desc), ":desc")

  defp to_geofence({:ok, nil}), do: {:ok, nil}
  defp to_geofence({:ok, payload}), do: {:ok, to_geofence_struct(payload)}
  defp to_geofence({:error, _} = error), do: error

  defp to_geofence_struct(payload) do
    %__MODULE__{
      gfid: Numeric.to_integer(payload["gfid"]),
      name: payload["name"],
      desc: payload["desc"],
      shape: payload["shape"],
      points: payload["points"],
      bufferradius: Numeric.to_integer(payload["bufferradius"]),
      createtime: Numeric.to_integer(payload["createtime"]),
      modifytime: Numeric.to_integer(payload["modifytime"])
    }
  end
end
