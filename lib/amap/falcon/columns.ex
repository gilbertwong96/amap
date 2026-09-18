defmodule Amap.Falcon.Columns do
  @moduledoc """
  Generates the operations both kinds of custom field share.

  Terminal fields and trace fields are documented on separate pages, live at
  different paths, and one of them has a "searchable" flag the other lacks — but
  deleting, renaming and listing a field are the same calls with a different
  path. Those three are generated here, and each module keeps what makes it
  itself: its own `@moduledoc`, struct, type and `add/4` or `add/5`.
  """

  defmacro __using__(opts) do
    base = Keyword.fetch!(opts, :base)

    quote do
      alias Amap.Falcon.Column

      @doc "Deletes a field and every value stored in it, then returns `{:ok, nil}`."
      @spec delete(Amap.Client.t(), integer(), String.t()) ::
              {:ok, nil} | {:error, Amap.Error.t()}
      def delete(client, sid, column), do: Column.delete(client, unquote(base), sid, column)

      @doc "Renames a field. Its values and its type are kept."
      @spec update(Amap.Client.t(), integer(), String.t(), String.t()) ::
              {:ok, nil} | {:error, Amap.Error.t()}
      def update(client, sid, column, newcolumn),
        do: Column.update(client, unquote(base), sid, column, newcolumn)

      @doc """
      Lists the declared fields, each with its name and type.

      Amap answers with those two and nothing else, so a struct with further
      fields — the terminal one carries a searchable flag — gets `nil` for them.
      """
      @spec list(Amap.Client.t(), integer()) :: {:ok, [struct()]} | {:error, Amap.Error.t()}
      def list(client, sid), do: Column.list(client, unquote(base), sid, __MODULE__)
    end
  end
end
