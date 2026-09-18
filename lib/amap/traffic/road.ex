defmodule Amap.Traffic.Road do
  @moduledoc """
  One road in the answer, with how it is flowing.

  `status` is 0 未知 (unknown), 1 畅通 (flowing), 2 缓行 (slowed) or 3 拥堵
  (congested). `angle` runs 0 to 360 clockwise from due east and is how a direction
  of travel is told apart, `lcodes` is Amap's own road identifier and is **negative
  for the opposite direction**, and `speed` is the average in km/h, rounded.
  `polyline` is the road's points as `{lon, lat}` tuples.
  """

  defstruct [:name, :status, :direction, :angle, :lcodes, :speed, :polyline]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          status: String.t() | nil,
          direction: String.t() | nil,
          angle: String.t() | nil,
          lcodes: String.t() | nil,
          speed: String.t() | nil,
          polyline: [{float(), float()}] | nil
        }
end
