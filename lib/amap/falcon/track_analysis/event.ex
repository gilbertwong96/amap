defmodule Amap.Falcon.TrackAnalysis.Event do
  @moduledoc """
  One harsh event at one point of a trajectory.

  Amap gives each of the four sections slightly different measurements, so this
  carries all of them and leaves the ones a given section does not report as `nil`:
  `acceleration` with `initial_speed`/`end_speed` for accelerating and braking,
  `centripetal_acc` with `speed` for steering, and `speed` with `speed_limit` for
  speeding.
  """

  defstruct [
    :location,
    :locate_time,
    :acceleration,
    :initial_speed,
    :end_speed,
    :centripetal_acc,
    :speed,
    :speed_limit
  ]

  @type t :: %__MODULE__{
          location: {float(), float()} | nil,
          locate_time: integer() | nil,
          acceleration: number() | nil,
          initial_speed: number() | nil,
          end_speed: number() | nil,
          centripetal_acc: number() | nil,
          speed: number() | nil,
          speed_limit: number() | nil
        }
end
