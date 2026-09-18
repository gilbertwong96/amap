defmodule Amap.Falcon.FenceTerminal do
  @moduledoc """
  The terminals a geofence watches.

  Binding a terminal is what makes a fence answer for it: `Amap.Falcon.FenceStatus`
  reports only on terminals bound to the fence. **One fence holds at most 10,000
  bound terminals**, and one call changes at most 100 of them.
  """

  use Amap.Falcon.Paging, page: Amap.Falcon.FenceTerminal.Page, mapper: :to_terminal
  alias Amap.Falcon.FenceTerminal.Page
  alias Amap.Falcon.Wire
  alias Amap.Numeric
  alias Amap.Validate

  defstruct [:tid, :tname]

  @type t :: %__MODULE__{
          tid: integer() | nil,
          tname: String.t() | nil
        }

  @base "/v1/track/geofence/terminal"

  @doc """
  Binds terminals to a fence.

  At most 100 ids per call. Amap truncates a longer list and answers success, so
  this raises instead of letting a caller believe all of them were bound. The
  answer lists the ids that were.
  """
  @spec bind(Amap.Client.t(), integer(), integer(), [integer()]) ::
          {:ok, [integer()]} | {:error, Amap.Error.t()}
  def bind(client, sid, gfid, tids) do
    params = [sid: sid, gfid: gfid, tids: Wire.ids!(tids, ":tids")]

    case Amap.request(client, :tsapi, :post, @base <> "/bind", params) do
      {:ok, payload} -> {:ok, Wire.decode_ids(payload["tids"])}
      {:error, _} = error -> error
    end
  end

  @doc """
  Unbinds terminals from a fence.

  Takes ids, or `:all` to detach every terminal. `:all` answers `{:ok, nil}`,
  because Amap has nothing to enumerate.
  """
  @spec unbind(Amap.Client.t(), integer(), integer(), [integer()] | :all) ::
          {:ok, [integer()] | nil} | {:error, Amap.Error.t()}
  def unbind(client, sid, gfid, :all) do
    Amap.request(client, :tsapi, :post, @base <> "/unbind", sid: sid, gfid: gfid, tids: "#all")
  end

  def unbind(client, sid, gfid, tids) when is_list(tids) do
    params = [sid: sid, gfid: gfid, tids: Wire.ids!(tids, ":tids")]

    case Amap.request(client, :tsapi, :post, @base <> "/unbind", params) do
      {:ok, payload} -> {:ok, Wire.decode_ids(payload["tids"])}
      {:error, _} = error -> error
    end
  end

  @doc "Lists the terminals bound to a fence, 50 per page unless asked otherwise."
  @spec list(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, Page.t()} | {:error, Amap.Error.t()}
  def list(client, sid, gfid, opts \\ []) do
    params = [
      sid: sid,
      gfid: gfid,
      page: Validate.optional_range!(Keyword.get(opts, :page), ":page", 1, 1_000_000),
      pagesize: Validate.optional_range!(Keyword.get(opts, :pagesize), ":pagesize", 1, 100)
    ]

    client
    |> Amap.request(:tsapi, :get, @base <> "/list", params)
    |> to_page()
  end

  defp to_terminal(payload) do
    %__MODULE__{tid: Numeric.to_integer(payload["tid"]), tname: payload["tname"]}
  end
end
