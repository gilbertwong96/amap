defmodule Amap.Direction.Road do
  @moduledoc """
  One road in the `roads` grouping `:roadaggregation` produces, in place of a driving
  path's `steps`.

  **The field names are the wire's; the value types under them are not.** The page
  states no entry shape, and the second live run printed the first entry's keys —
  `road_distance`, `road_name`, `steps`, `traffic_lights` — and nothing about their
  values. So each field carries `Amap.JSON.value()` rather than a type no source has
  shown, and the integration check prints the first entry in full, which is what a
  later run narrows them from.

  `steps` shares a path's key name without being evidence of a path's step shape:
  nothing here maps it into `Amap.Direction.Step`, because no source has said what
  this key holds.
  """

  defstruct [:road_distance, :road_name, :steps, :traffic_lights]

  @typedoc """
  One aggregated road: the four keys the wire proved, each still whatever Amap sends
  under it, because no value type has been seen yet.
  """
  @type t :: %__MODULE__{
          road_distance: Amap.JSON.value(),
          road_name: Amap.JSON.value(),
          steps: Amap.JSON.value(),
          traffic_lights: Amap.JSON.value()
        }
end
