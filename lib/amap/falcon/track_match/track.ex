defmodule Amap.Falcon.TrackMatch.Track do
  @moduledoc """
  One of the two tracks compared, once Amap has corrected it.

  `points` is only there when the call asked for `is_points: true`, and `distance`
  is in metres.
  """

  defstruct [:points, :distance]

  @type t :: %__MODULE__{
          points: [{float(), float()}] | nil,
          distance: number() | nil
        }
end
