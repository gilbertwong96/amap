defmodule Amap.Limiter.Supervisor do
  @moduledoc """
  Holds token buckets started on demand by `Amap.new/1`.

  Buckets are owned by clients rather than registered globally, so two clients
  for two Amap accounts keep independent quotas.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Starts a bucket under this supervisor."
  @spec start_bucket(Amap.Limiter.options()) ::
          {:ok, pid()}
          | {:error, Amap.Limiter.start_error() | :max_children | :noproc | :shutdown}
  def start_bucket(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Amap.Limiter, opts})
  end
end
