defmodule Amap.Falcon.TraceColumn do
  @moduledoc """
  Trace custom fields — what makes a trace's `props` legal.

  These are the fields a trace carries: `Amap.Falcon.Point.upload/5`'s `props`
  and the `props` that `Amap.Falcon.Grasproad.trsearch/4` reads back. Amap
  rejects a field that has not been declared, so declare it here first, and a
  service holds at most five of them.

  **Amap's paths for this say `point/column`, but the fields are trace fields.**
  This page of the documentation is 轨迹自定义字段 (custom trace fields), and the module
  is named after the domain rather than the path. Unlike terminal fields there is no
  "searchable" flag here.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TraceColumn.add(client, 1000, "driver", :string)
      {:ok, nil}
      iex> Amap.Falcon.TraceColumn.add(client, 1000, "driver", :text)
      ** (ArgumentError) :type must be one of [:string, :double, :int], got: :text

  Declaring answers `{:ok, nil}` because Amap sends no data back, and the stand-in
  accepts it on the trace fields' own path — `/v1/track/point/column/add`, where the
  path says `point` while these are trace fields, and where the type has to arrive as
  the wire word `string` and with no searchable flag, which terminal fields have and
  trace fields do not. A type Amap does not document is refused here rather than sent.
  """

  use Amap.Falcon.Columns, base: "/v1/track/point/column"

  alias Amap.Falcon.Column
  alias Amap.Validate

  defstruct [:column, :type]

  @type t :: %__MODULE__{
          column: String.t() | nil,
          type: String.t() | nil
        }

  @doc """
  Declares a field.

  `type` is `:string`, `:double` or `:int`, and every `props` value for this
  field has to match it.
  """
  @spec add(Amap.Client.t(), integer(), String.t(), :string | :double | :int) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def add(client, sid, column, type) do
    params = [
      sid: sid,
      column: Validate.name!(column, ":column"),
      type: Column.encode_type(type)
    ]

    Amap.request(client, :tsapi, :post, "/v1/track/point/column/add", params)
  end
end
