defmodule Amap.Falcon.Paging do
  @moduledoc """
  Generates the page assembly several track endpoints share.

  Amap answers a page as `{count, results}` — a count for the whole result set and
  an array of rows — and each endpoint maps those rows into a struct of its own.
  The shape is written once here, and `use` puts a `to_page/1` into the module that
  owns both the struct and the row mapper:

      use Amap.Falcon.Paging, page: Page, mapper: :to_result

  A generated function is the only way to keep this both shared and precisely
  typed: a runtime helper would have to promise `struct()` and leave the caller to
  discover which one, and naming the page structs in a spec here would make this
  module depend on them while they depend on it.
  """

  @typedoc "A request result: whatever payload Amap answered with, or the failure it reported."
  @type result :: {:ok, Amap.Response.payload()} | {:error, Amap.Error.t()}

  defmacro __using__(opts) do
    page = Keyword.fetch!(opts, :page)
    mapper = Keyword.fetch!(opts, :mapper)

    quote do
      @spec to_page(Amap.Falcon.Paging.result()) ::
              {:ok, unquote(page).t()} | {:error, Amap.Error.t()}
      defp to_page({:ok, payload}) do
        case Amap.Falcon.Wire.rows(payload) do
          {:ok, rows} ->
            {:ok,
             %unquote(page){
               items: Enum.map(rows, &unquote(mapper)(&1)),
               count: page_count(payload)
             }}

          {:error, _} = error ->
            error
        end
      end

      defp to_page({:error, _} = error), do: error

      defp page_count(%{} = payload), do: Amap.Numeric.to_integer(payload["count"])
      defp page_count(_no_data), do: nil
    end
  end
end
