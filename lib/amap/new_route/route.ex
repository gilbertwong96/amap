defmodule Amap.NewRoute.Route do
  @moduledoc """
  The way Amap would take you — v5's answer to a `/v5/direction/…` call.

  `paths` holds the ways it offers — one unless the strategy asked for several — and
  the endpoints are the two that were asked about, decoded from Amap's `lon,lat`
  strings into `{lon, lat}` tuples.

  **This is not `Amap.Direction.Route`.** The v5 pages rename fields and regroup others
  — a step's `road` became `road_name` and its `distance` became `step_distance` — so
  the two versions carry their own structs rather than one with two shapes' worth of
  optional fields, which would make both versions' documentation wrong.

  Scalars keep the wire's form: `taxi_cost` stays the string Amap sends.
  """

  alias Amap.NewRoute.Path

  defstruct [:origin, :destination, :taxi_cost, paths: []]

  @type t :: %__MODULE__{
          origin: {float(), float()} | nil,
          destination: {float(), float()} | nil,
          taxi_cost: String.t() | nil,
          paths: [Path.t()]
        }
end
