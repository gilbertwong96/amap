defmodule Amap.Direction.Road do
  @moduledoc """
  One road in the `roads` grouping `:roadaggregation` produces, in place of a driving
  path's `steps`.

  The third live run printed a whole entry: `road_distance` is how far the stretch
  runs, `road_name` the road it is on, `traffic_lights` how many lights it meets, and
  `steps` the legs it is made of — the shape `Amap.Direction.Step` reads for a path's
  own steps, which is why they are mapped rather than carried verbatim. The scalars
  keep the wire's form and arrive as strings, as v3's other distances and counts do.
  All seven entries in that run carried the same four keys.
  """

  alias Amap.Direction.Step

  defstruct [:road_distance, :road_name, :steps, :traffic_lights]

  @type t :: %__MODULE__{
          road_distance: String.t() | nil,
          road_name: String.t() | nil,
          steps: [Step.t()],
          traffic_lights: String.t() | nil
        }
end
