defmodule Amap.Falcon.Column do
  @moduledoc """
  The operations both kinds of custom field share.

  Terminal fields and trace fields are documented on separate pages, live at
  different paths, and one of them has a "searchable" flag the other lacks — but
  deleting, renaming and listing a field are the same calls with a different
  path. Those live here once, and `Amap.Falcon.TerminalColumn` and
  `Amap.Falcon.TraceColumn` supply their own path and struct.
  """

  alias Amap.Falcon.Validate

  @types [:string, :double, :int]

  @doc "Deletes a field and returns `{:ok, nil}`."
  def delete(client, base, sid, column) do
    Amap.request(client, :tsapi, :post, base <> "/delete",
      sid: sid,
      column: Validate.name!(column, ":column")
    )
  end

  @doc "Renames a field, keeping its values and type."
  def update(client, base, sid, column, newcolumn) do
    params = [
      sid: sid,
      column: Validate.name!(column, ":column"),
      newcolumn: Validate.name!(newcolumn, ":newcolumn")
    ]

    Amap.request(client, :tsapi, :post, base <> "/update", params)
  end

  @doc """
  Lists a service's fields into `module`'s struct.

  Amap answers with each field's name and type and nothing else, so a struct with
  further fields — the terminal one has a searchable flag — gets `nil` for them.
  """
  def list(client, base, sid, module) do
    case Amap.request(client, :tsapi, :get, base <> "/list", sid: sid) do
      {:ok, payload} ->
        {:ok,
         Enum.map(
           Map.get(payload, "results", []),
           &struct(module, column: &1["column"], type: &1["type"])
         )}

      {:error, _} = error ->
        error
    end
  end

  @doc "Encodes a field type, the one parameter both kinds validate identically."
  def encode_type(type) when type in @types, do: to_string(type)

  def encode_type(other),
    do: raise(ArgumentError, ":type must be one of #{inspect(@types)}, got: #{inspect(other)}")
end
