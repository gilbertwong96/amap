defmodule Amap.Limiter do
  @moduledoc false
  use GenServer

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  # Task 12 replaces this stub with the real token bucket. This function exists
  # because `child_spec/1` above names it: without it `start_bucket/1` could never
  # return `{:ok, pid}`, which its `@spec` promises.
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts), do: {:ok, opts}
end
