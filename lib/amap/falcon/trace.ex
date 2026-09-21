defmodule Amap.Falcon.Trace do
  @moduledoc """
  Falcon traces — one journey a terminal took.

  A trace belongs to a terminal, and points are uploaded against it. A terminal
  holds at most 500,000 of them.

  All functions take the client first and return `{:ok, struct | nil} |
  {:error, %Amap.Error{}}`.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, named} = Amap.Falcon.Trace.add(client, 1000, 456, trname: "早晨一趟")
      iex> {named.trid, named.trname}
      {20, "早晨一趟"}
      iex> {:ok, generated} = Amap.Falcon.Trace.add(client, 1000, 456)
      iex> {generated.trid, generated.trname}
      {21, "随机名字"}

  `trname` is optional, and leaving it out is what asks Amap for a generated one: the
  stand-in answers the generated name only to a request that carries no `trname` at
  all, so the second call shows the parameter left off the wire rather than sent
  empty. A name that breaks Amap's rules is refused before any request is built.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.Trace.delete(client, 1000, 456, 20)
      {:ok, nil}
      iex> Amap.Falcon.Trace.add(client, 1000, 456, trname: "morning trace")
      ** (ArgumentError) :trname may only contain Chinese, letters, digits, _ and -

  `delete/4` answers `{:ok, nil}` — Amap sends no data back for it — while `add/4`
  answers the trace as Amap recorded it.
  """

  alias Amap.Numeric
  alias Amap.Validate

  defstruct [:trid, :trname]

  @type t :: %__MODULE__{
          trid: integer() | nil,
          trname: String.t() | nil
        }

  @base "/v1/track/trace"

  @doc """
  Creates a trace on a terminal and returns it.

  `trname` is optional, follows Amap's naming rules (see
  `Amap.Validate.name!/2`), and Amap generates a random name when it is
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
