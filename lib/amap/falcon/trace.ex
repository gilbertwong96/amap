defmodule Amap.Falcon.Trace do
  @moduledoc """
  Falcon traces — one journey a terminal took.

  A trace belongs to a terminal, and points are uploaded against it. A terminal
  holds at most 500,000 of them.

  All functions take the client first and return `{:ok, struct | nil} |
  {:error, %Amap.Error{}}`.
  """

  alias Amap.Falcon.Validate
  alias Amap.Numeric

  defstruct [:trid, :trname]

  @type t :: %__MODULE__{
          trid: integer() | nil,
          trname: String.t() | nil
        }

  @base "/v1/track/trace"

  @doc """
  Creates a trace on a terminal and returns it.

  `trname` is optional, follows Amap's naming rules (see
  `Amap.Falcon.Validate.name!/2`), and Amap generates a random name when it is
  left out.
  """
  @spec add(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def add(client, sid, tid, opts \\ []) do
    params = [
      sid: sid,
      tid: tid,
      trname: Validate.optional!(&Validate.name!/2, Keyword.get(opts, :trname), ":trname")
    ]

    client
    |> Amap.request(:tsapi, :post, @base <> "/add", params)
    |> to_trace()
  end

  @doc "Deletes a trace and everything uploaded against it, then returns `{:ok, nil}`."
  @spec delete(Amap.Client.t(), integer(), integer(), integer()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def delete(client, sid, tid, trid),
    do: Amap.request(client, :tsapi, :post, @base <> "/delete", sid: sid, tid: tid, trid: trid)

  defp to_trace_struct(payload) do
    %__MODULE__{trid: Numeric.to_integer(payload["trid"]), trname: payload["trname"]}
  end

  defp to_trace({:ok, nil}), do: {:ok, nil}
  defp to_trace({:ok, payload}), do: {:ok, to_trace_struct(payload)}
  defp to_trace({:error, _} = error), do: error
end
