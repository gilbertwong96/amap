defmodule Amap.Direction.Route do
  @moduledoc """
  A planned route: one origin, one destination, and the paths Amap offers.

  `paths` is ranked, Amap's own preference first. `origin` and `destination` are
  `{lon, lat}` tuples, the same shape the request took.

  `taxi_cost` is driving's — the cost of taking a taxi instead, in yuan — and stays
  `nil` on every other answer in this module.
  """

  alias Amap.Direction.Path

  defstruct [:origin, :destination, :taxi_cost, paths: []]

  @type t :: %__MODULE__{
          origin: {float(), float()} | nil,
          destination: {float(), float()} | nil,
          taxi_cost: String.t() | nil,
          paths: [Path.t()]
        }
end
