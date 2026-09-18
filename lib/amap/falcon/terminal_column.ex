defmodule Amap.Falcon.TerminalColumn do
  @moduledoc """
  Terminal custom fields — what makes a terminal's `props` legal.

  Amap rejects a `props` field that has not been declared, so declare it here
  first. A service holds at most five fields, and all of them are searchable in
  `Amap.Falcon.TerminalSearch`.

  The field's `type`, and whether it is searchable (`list: :y`), **cannot be
  changed after creation**.
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
