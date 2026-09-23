defmodule Amap.Result do
  @moduledoc """
  The answer of a call whose endpoint sends no data.

  Amap returns no body for its writes and deletes, so those calls answer
  `{:ok, nil}` rather than a payload; a failure carries the same `Amap.Error`
  every other call reports.
  """

  @typedoc """
  A call that answers with no data: `{:ok, nil}`, or the failure it reported.
  """
  @type t :: {:ok, nil} | {:error, Amap.Error.t()}
end
