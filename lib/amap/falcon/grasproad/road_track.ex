defmodule Amap.Falcon.Grasproad.RoadTrack do
  @moduledoc """
  One segment of a trajectory and the road it ran on.

  Amap sends these field names in camelCase, so they are snake_cased here:
  `roadName` → `road_name`, `speedLimit` → `speed_limit`, and so on. `road_class`
  is Amap's numeric road grade — 41000 is a motorway, 42000 a national road, and
  so on — with `road_class_name` carrying the same thing as text.
  """

  alias Amap.Falcon.Position

  defstruct [
    :road_name,
    :speed_limit,
    :road_class,
    :road_class_name,
    :is_toll,
    :is_ownership,
    points: []
  ]

  @type t :: %__MODULE__{
          road_name: String.t() | nil,
          speed_limit: integer() | nil,
          road_class: integer() | nil,
          road_class_name: String.t() | nil,
          is_toll: boolean() | nil,
          is_ownership: boolean() | nil,
          points: [Position.t()]
        }
end
