defmodule Amap.Falcon.TerminalColumn do
  @moduledoc """
  Terminal custom fields — what makes a terminal's `props` legal.

  Amap rejects a `props` field that has not been declared, so declare it here
  first. A service holds at most five fields, and all of them are searchable in
  `Amap.Falcon.TerminalSearch`.

  The field's `type`, and whether it is searchable (`list: :y`), **cannot be
  changed after creation**.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TerminalColumn.add(client, 1000, "plate", :string, list: :y)
      {:ok, nil}
      iex> {:ok, [field]} = Amap.Falcon.TerminalColumn.list(client, 1000)
      iex> {field.column, field.type, field.list}
      {"plate", "string", nil}

  Declaring answers `{:ok, nil}` — the endpoint sends no data — and the list
  endpoint reports only the name and the type, so the searchable flag reads as
  `nil` even for the field just declared `list: :y`: it was not reported, and that
  is not the same as `:n`.

  A type or a flag Amap does not document is refused here rather than sent:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TerminalColumn.add(client, 1000, "plate", :boolean)
      ** (ArgumentError) :type must be one of [:string, :double, :int], got: :boolean

  The searchable flag takes `:y` or `:n`, and nothing else:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TerminalColumn.add(client, 1000, "plate", :string, list: "yes")
      ** (ArgumentError) :list must be :y or :n, got: "yes"
  """

  use Amap.Falcon.Columns, base: "/v1/track/terminal/column"

  alias Amap.Falcon.Column
  alias Amap.Validate

  defstruct [:column, :type, :list]

  @type t :: %__MODULE__{
          column: String.t() | nil,
          type: String.t() | nil,
          list: String.t() | nil
        }

  @doc """
  Declares a field.

  `type` is `:string`, `:double` or `:int`, and every `props` value for this
  field has to match it. `list: :y` makes the field searchable and cannot be
  changed afterwards; it defaults to `:n` at Amap's end.
  """
  @spec add(Amap.Client.t(), integer(), String.t(), :string | :double | :int, keyword()) ::
          {:ok, nil} | {:error, Amap.Error.t()}
  def add(client, sid, column, type, opts \\ []) do
    params = [
      sid: sid,
      column: Validate.name!(column, ":column"),
      type: Column.encode_type(type),
      list: encode_list(Keyword.get(opts, :list))
    ]

    Amap.request(client, :tsapi, :post, "/v1/track/terminal/column/add", params)
  end

  defp encode_list(nil), do: nil
  defp encode_list(:y), do: "y"
  defp encode_list(:n), do: "n"

  defp encode_list(other),
    do: raise(ArgumentError, ":list must be :y or :n, got: #{inspect(other)}")
end
