defmodule Amap.Finch do
  @moduledoc """
  The connection pool the SDK uses when a client does not name one.

  Pass `pool: MyApp.Finch` to `Amap.new/1` to share an existing pool instead.
  """

  @doc "The registered name of the default pool."
  @spec name() :: module()
  def name, do: __MODULE__

  @doc false
  def child_spec(_arg) do
    Finch.child_spec(name: name(), pools: %{default: [size: 10, count: 1]})
  end
end
