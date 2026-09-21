defmodule Amap.Falcon.FenceStatus do
  @moduledoc """
  Whether something is inside a fence.

  Two ways to ask — about a terminal, or about a coordinate — answering the same
  rows: a fence, and whether the thing is inside it. Both can be narrowed with
  `gfids`, which **turns pagination off**, or paged through otherwise.

  `in` is `false` when the monitored terminal has no position at all, and Amap then
  omits `location` and `time` entirely rather than sending them empty, which is why
  they are optional here.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, page} = Amap.Falcon.FenceStatus.terminal(client, 1000, 456)
      iex> Enum.map(page.items, &{&1.gfname, &1.in})
      [{"仓库一", true}, {"仓库二", false}]
      iex> hd(page.items).location
      {114.158, 22.279}
      iex> missing = List.last(page.items)
      iex> {missing.location, missing.time}
      {nil, nil}

  `in` is a decoded boolean rather than the `1`/`0` Amap writes, `location` arrives
  as a `{lon, lat}` tuple, and a terminal with no position is `false` for every
  fence with `location` and `time` left out — so they read as `nil` rather than as
  `""` or `0`.

  Asking about a coordinate answers the same rows, and `gfids` narrows them:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, page} =
      ...>   Amap.Falcon.FenceStatus.location(client, 1000, {114.158, 22.279}, gfids: [77])
      iex> Enum.map(page.items, & &1.gfid)
      [77]
  """

  use Amap.Falcon.Paging, page: Amap.Falcon.FenceStatus.Page, mapper: :to_status
  alias Amap.Falcon.FenceStatus.Page
  alias Amap.Falcon.Wire
  alias Amap.Numeric
  alias Amap.Param

  defstruct [:gfid, :gfname, :in, :location, :time]

  @type t :: %__MODULE__{
          gfid: integer() | nil,
          gfname: String.t() | nil,
          in: boolean() | nil,
          location: {float(), float()} | nil,
          time: integer() | nil
        }

  @base "/v1/track/geofence"

  @doc """
  Asks whether a terminal is inside its fences.

  One terminal at a time — Amap's `tid` takes a single id here, not a list — and
  the answer covers every fence the terminal is bound to, unless `gfids` narrows it.
  """
  @spec terminal(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, Page.t()} | {:error, Amap.Error.t()}
  def terminal(client, sid, tid, opts \\ []) do
    params = [sid: sid, tid: tid] ++ common_params(opts)

    client
    |> Amap.request(:tsapi, :get, @base <> "/status/terminal", params)
    |> to_page()
  end

  @doc """
  Asks whether a coordinate is inside a fence.

  `location` is a `{lon, lat}` tuple. Every fence in the service is checked unless
  `gfids` narrows it.
  """
  @spec location(Amap.Client.t(), integer(), {number(), number()}, keyword()) ::
          {:ok, Page.t()} | {:error, Amap.Error.t()}
  def location(client, sid, location, opts \\ []) do
    params = [sid: sid, location: Param.location(location)] ++ common_params(opts)

    client
    |> Amap.request(:tsapi, :get, @base <> "/status/location", params)
    |> to_page()
  end

  defp common_params(opts) do
    gfids = Keyword.get(opts, :gfids)

    [
      gfids: Wire.ids!(gfids, ":gfids")
    ] ++ Wire.pagination(opts, gfids)
  end

  # Amap ignores `page` and `pagesize` when `gfids` is given: see `Wire.pagination/2`.

  defp to_status(payload) do
    %__MODULE__{
      gfid: Numeric.to_integer(payload["gfid"]),
      gfname: payload["gfname"],
      in: Wire.decode_flag(payload["in"]),
      location: Amap.Coord.parse_location(payload["location"]),
      time: Numeric.to_integer(payload["time"])
    }
  end
end
