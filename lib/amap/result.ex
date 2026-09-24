defmodule Amap.Result do
  @moduledoc """
  The answer of a call whose endpoint sends no data.

  Amap returns no body for its writes and deletes, so those calls answer `:ok`
  rather than a payload; a failure carries the same `Amap.Error` every other call
  reports.

  `Amap.request/6` is not this type: it hands back whatever payload arrived, so a
  body without `data` is `{:ok, nil}` there. A wrapper that knows no value can
  exist converts that with `without_data/1`, which is where the `:ok` comes from.
  """

  @typedoc """
  A call that answers with no data: `:ok`, or the failure it reported.
  """
  @type t :: :ok | {:error, Amap.Error.t()}

  @doc """
  Maps a write's answer onto this type.

  These endpoints send no data, so any success carries nothing and becomes `:ok`;
  a failure passes through unchanged.
  """
  @spec without_data({:ok, Amap.Response.payload()} | {:error, Amap.Error.t()}) :: t()
  def without_data({:ok, _payload}), do: :ok
  def without_data({:error, _reason} = error), do: error
end
