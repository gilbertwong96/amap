defmodule Amap.Falcon.TrackMatch.Match do
  @moduledoc """
  How much two trajectories overlap.

  `match_ratio` is a percentage as Amap wrote it, e.g. `"84.7"`. The distances are
  metres: `match_distance` for the overlapping part, `mismatch_distance` for what the
  target added, with `mismatch_time` marking the first time the target left the
  baseline — the last of those only when the baseline's points carry times.
  """

  alias Amap.Falcon.TrackMatch.Track

  defstruct [
    :match_ratio,
    :match_distance,
    :mismatch_distance,
    :mismatch_time,
    :match_points,
    :baseline,
    :target
  ]

  @type t :: %__MODULE__{
          match_ratio: String.t() | nil,
          match_distance: number() | nil,
          mismatch_distance: number() | nil,
          mismatch_time: integer() | nil,
          match_points: [{float(), float()}] | nil,
          baseline: Track.t() | nil,
          target: Track.t() | nil
        }
end
