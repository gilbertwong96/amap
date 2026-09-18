defmodule Amap.Falcon.TrackAnalysis.DrivingBehaviour do
  @moduledoc """
  How a trace was driven.

  The three counts say how many harsh events Amap found of each kind, and the four
  sections carry the events themselves — speeding included, under `speed_limit`.
  """

  alias Amap.Falcon.TrackAnalysis.Section

  defstruct [
    :distance,
    :duration,
    :ave_speed,
    :max_speed,
    :harsh_acceleration_count,
    :harsh_deceleration_count,
    :harsh_steering_count,
    :harsh_acceleration,
    :harsh_deceleration,
    :harsh_steering,
    :speed_limit
  ]

  @type t :: %__MODULE__{
          distance: number() | nil,
          duration: integer() | nil,
          ave_speed: number() | nil,
          max_speed: number() | nil,
          harsh_acceleration_count: integer() | nil,
          harsh_deceleration_count: integer() | nil,
          harsh_steering_count: integer() | nil,
          harsh_acceleration: Section.t() | nil,
          harsh_deceleration: Section.t() | nil,
          harsh_steering: Section.t() | nil,
          speed_limit: Section.t() | nil
        }
end
