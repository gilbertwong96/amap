defmodule Amap.Falcon.FenceStatus do
  @moduledoc """
  Whether something is inside a fence.

  Two ways to ask — about a terminal, or about a coordinate — answering the same
  rows: a fence, and whether the thing is inside it. Both can be narrowed with
  `gfids`, which **turns pagination off**, or paged through otherwise.

  `in` is `false` when the monitored terminal has no position at all, and Amap then
  omits `location` and `time` entirely rather than sending them empty, which is why
  they are optional here.
  """

  alias Amap.Falcon.FenceStatus.Page
  alias Amap.Falcon.Paging
  alias Amap.Falcon.Validate
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
      gfids: encode_gfids(gfids)
    ] ++ pagination(opts, gfids)
  end

  # Amap ignores `page` and `pagesize` when `gfids` is given, so sending them anyway
  # would suggest a paging that is not happening.
  defp pagination(_opts, gfids) when not is_nil(gfids), do: []

  defp pagination(opts, _gfids) do
    [
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, 1_000_000),
      pagesize: Validate.optional_range!(Keyword.get(opts, :pagesize), ":pagesize", 1, 100)
    ]
  end

  defp encode_gfids(nil), do: nil
  defp encode_gfids(gfids), do: Wire.ids!(gfids, ":gfids")

  defp to_page(result), do: Paging.from(result, Page, &to_status/1)

  defp to_status(payload) do
    %__MODULE__{
      gfid: Numeric.to_integer(payload["gfid"]),
      gfname: payload["gfname"],
      in: Wire.decode_flag(payload["in"]),
      location: Amap.Falcon.Point.parse_location(payload["location"]),
      time: Numeric.to_integer(payload["time"])
    }
  end
end
