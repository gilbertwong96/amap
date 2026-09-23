defmodule Amap.Falcon.Column do
  @moduledoc """
  The operations both kinds of custom field share.

  Terminal fields and trace fields are documented on separate pages, live at
  different paths, and one of them has a "searchable" flag the other lacks — but
  deleting, renaming and listing a field are the same calls with a different
  path. Those live here once, and `Amap.Falcon.TerminalColumn` and
  `Amap.Falcon.TraceColumn` supply their own path and struct.
  """

  alias Amap.Validate

  @typedoc "One row of Amap's field list: the field's name and its type."
  @type row :: %{String.t() => String.t()}

  @types [:string, :double, :int]

  @doc "Deletes a field and returns `{:ok, nil}`."
  @spec delete(Amap.Client.t(), String.t(), integer(), String.t()) ::
          Amap.Result.t()
  def delete(client, base, sid, column) do
    Amap.request(client, :tsapi, :post, base <> "/delete",
      sid: sid,
      column: Validate.name!(column, ":column")
    )
  end

  @doc "Renames a field, keeping its values and type."
  @spec update(Amap.Client.t(), String.t(), integer(), String.t(), String.t()) ::
          Amap.Result.t()
  def update(client, base, sid, column, newcolumn) do
    params = [
      sid: sid,
      column: Validate.name!(column, ":column"),
      newcolumn: Validate.name!(newcolumn, ":newcolumn")
    ]

    Amap.request(client, :tsapi, :post, base <> "/update", params)
  end

  @doc """
  Lists a service's fields, as the name and type Amap answers with.

  The rows are payload maps rather than structs, because the struct belongs to the
  caller: `Amap.Falcon.Columns` generates the field modules, each of which knows
  its own type and maps these rows into it.
  """
  @spec list(Amap.Client.t(), String.t(), integer()) ::
          {:ok, [row()]} | {:error, Amap.Error.t()}
  def list(client, base, sid) do
    case Amap.request(client, :tsapi, :get, base <> "/list", sid: sid) do
      {:ok, payload} -> {:ok, Map.get(payload, "results") || []}
      {:error, _} = error -> error
    end
  end

  @doc "Encodes a field type, the one parameter both kinds validate identically."
  @spec encode_type(:string | :double | :int) :: String.t()
  def encode_type(type) when type in @types, do: to_string(type)

  def encode_type(other),
    do: raise(ArgumentError, ":type must be one of #{inspect(@types)}, got: #{inspect(other)}")
end
