defmodule Amap.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Amap.Finch,
      Amap.Limiter.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Amap.Supervisor)
  end
end
