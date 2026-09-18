defmodule Amap.Falcon.Grasproad.Point do
  @moduledoc """
  One point of a trajectory.

  `location` is a `{lon, lat}` tuple, parsed from Amap's `"lon,lat"` string.

  Every field except `location` may be `nil`: when correction was applied, Amap
  drops the attributes it cannot derive from the snapped track.
  """

  defstruct [:location, :locatetime, :accuracy, :direction, :speed, :height, :props]

  @type t :: %__MODULE__{
          location: {float(), float()} | nil,
          locatetime: integer() | nil,
          accuracy: number() | nil,
          direction: number() | nil,
          speed: number() | nil,
          height: number() | nil,
          props: map() | nil
        }
end
