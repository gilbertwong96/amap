defmodule Amap.Direction.Transit.Walking do
  @moduledoc """
  步行方案 — the walk a transit segment makes, at one end of a plan.

  Amap sends this leg's own `origin` and `destination` as `{lon, lat}` tuples, because
  a walk is between two points on the plan rather than between the route's two ends.
  That is why this is not an `Amap.Direction.Path`: a `Path` gets its endpoints from the
  `route` around it, and this leg would lose them.

  `distance` and `duration` are the walk's own, and stay the strings the wire sends.
  `steps` is the same turn-by-turn breakdown a path carries, as `Amap.Direction.Step`
  structs — the page's 步行方案信息列表 prints the v3 step fields inside this leg.
  """

  alias Amap.Direction.Step

  defstruct [:origin, :destination, :distance, :duration, steps: []]

  @type t :: %__MODULE__{
          origin: {float(), float()} | nil,
          destination: {float(), float()} | nil,
          distance: String.t() | nil,
          duration: String.t() | nil,
          steps: [Step.t()]
        }
end
